import Foundation
import SwiftUI
import WebKit
import HealthCore

/// Withings API: OAuth 2 sign-in, token refresh, and body composition sync. Only traffic is phone to Withings,
/// which already holds this data. Tokens in the Keychain, measurements cached in Application Support.
enum WithingsService {
    /// Registered in the Withings developer dashboard. Withings checks that callback URLs answer, and this one
    /// always does; the in-app sign-in sheet catches the redirect before it loads.
    static let redirect = "https://example.com/"
    static let types = WithingsBody.Kind.allCases.map { String($0.rawValue) }.joined(separator: ",")

    static var clientID: String { Bundle.main.object(forInfoDictionaryKey: "WithingsClientID") as? String ?? "" }
    static var clientSecret: String { Bundle.main.object(forInfoDictionaryKey: "WithingsClientSecret") as? String ?? "" }
    static var isConfigured: Bool { !clientID.isEmpty && !clientSecret.isEmpty }
    static var isConnected: Bool { Keychain.get("tokens", service: Keychain.withings) != nil }

    struct Tokens: Codable {
        var access: String
        var refresh: String
        var expiry: Date
    }

    struct Cache: Codable {
        var groups: [WithingsGroup] = []
        var updateTime: Int?
        var fetchedAt: Date?
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: Sign-in

    static func authorizeURL(state: String) -> URL {
        var c = URLComponents(string: "https://account.withings.com/oauth2_user/authorize2")!
        c.queryItems = [.init(name: "response_type", value: "code"), .init(name: "client_id", value: clientID),
                        .init(name: "scope", value: "user.metrics"), .init(name: "redirect_uri", value: redirect),
                        .init(name: "state", value: state)]
        return c.url!
    }

    /// The code from the redirect is only valid for 30 seconds, so this runs right away.
    static func exchange(code: String) async throws {
        try await requestToken(["grant_type": "authorization_code", "code": code, "redirect_uri": redirect])
    }

    static func disconnect() {
        Keychain.set(nil, for: "tokens", service: Keychain.withings)
        try? FileManager.default.removeItem(at: cacheURL)
    }

    // MARK: Tokens

    private static var tokens: Tokens? {
        get { Keychain.get("tokens", service: Keychain.withings).flatMap { try? JSONDecoder().decode(Tokens.self, from: Data($0.utf8)) } }
        set {
            let json = newValue.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
            Keychain.set(json, for: "tokens", service: Keychain.withings)
        }
    }

    /// Each refresh returns a new refresh token; the old one stops working 8 hours later, so always keep the newest.
    private static func requestToken(_ fields: [String: String]) async throws {
        let json = try await post("https://wbsapi.withings.net/v2/oauth2",
                                  fields.merging(["action": "requesttoken", "client_id": clientID, "client_secret": clientSecret]) { a, _ in a })
        guard let body = json["body"] as? [String: Any], let access = body["access_token"] as? String,
              let refresh = body["refresh_token"] as? String else { throw Failure(message: "Withings sign-in failed.") }
        let seconds = body["expires_in"] as? Double ?? (body["expires_in"] as? Int).map(Double.init) ?? 10800
        tokens = Tokens(access: access, refresh: refresh, expiry: Date.now.addingTimeInterval(seconds))
    }

    private static func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let t = tokens else { throw Failure(message: "Not connected to Withings.") }
        if !forceRefresh && t.expiry.timeIntervalSinceNow > 300 { return t.access }
        try await requestToken(["grant_type": "refresh_token", "refresh_token": t.refresh])
        guard let fresh = tokens?.access else { throw Failure(message: "Withings sign-in expired. Connect again.") }
        return fresh
    }

    // MARK: Sync

    private static var cacheURL: URL { URL.applicationSupportDirectory.appendingPathComponent("withings.json") }

    static func cached() -> Cache {
        (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) } ?? Cache()
    }

    /// New and changed weigh-ins since the last sync (everything the first time), merged into the cache.
    /// Withings asks for at most one poll per 10 minutes per user, so a recent cache is returned as it is.
    static func sync() async throws -> Cache {
        var cache = cached()
        if let last = cache.fetchedAt, Date.now.timeIntervalSince(last) < 600 { return cache }
        var fields = ["action": "getmeas", "category": "1", "meastypes": types]
        if let u = cache.updateTime { fields["lastupdate"] = String(u) } else { fields["startdate"] = "0"; fields["enddate"] = String(Int(Date.now.timeIntervalSince1970)) }
        var fetched: [WithingsGroup] = [], update: Int?, offset: Int?
        repeat {
            var f = fields
            if let offset { f["offset"] = String(offset) }
            let page = try await measurePage(f)
            fetched += page.groups
            update = update ?? page.updateTime
            offset = page.more ? page.offset : nil
        } while offset != nil
        cache.groups = WithingsBody.merge(cache.groups, fetched)
        cache.updateTime = update ?? cache.updateTime
        cache.fetchedAt = .now
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(cache).write(to: cacheURL, options: [.atomic, .completeFileProtection])
        return cache
    }

    /// One page, refreshing the token once if Withings says it is invalid (status 401).
    private static func measurePage(_ fields: [String: String], retried: Bool = false) async throws -> WithingsPage {
        let data = try await postData("https://wbsapi.withings.net/measure", fields, token: try await accessToken(forceRefresh: retried))
        do {
            return try WithingsBody.parse(data)
        } catch WithingsError.status(401) where !retried {
            return try await measurePage(fields, retried: true)
        } catch WithingsError.status(let s) {
            throw Failure(message: s == 401
                ? "Withings sign-in expired. Connect again."
                : "Withings refused the request (status \(s)). Under its current terms this can mean a Withings+ subscription is needed.")
        }
    }

    // MARK: HTTP

    private static func post(_ url: String, _ fields: [String: String]) async throws -> [String: Any] {
        let data = try await postData(url, fields, token: nil)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure(message: "Unexpected answer from Withings.") }
        if let status = json["status"] as? Int, status != 0 {
            throw Failure(message: "Withings error \(status): \(json["error"] as? String ?? "")")
        }
        return json
    }

    private static func postData(_ url: String, _ fields: [String: String], token: String?) async throws -> Data {
        var r = URLRequest(url: URL(string: url)!)
        r.httpMethod = "POST"
        r.timeoutInterval = 30
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        var c = URLComponents()
        c.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        r.httpBody = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        return try await URLSession.shared.data(for: r).0
    }
}

/// Withings sign-in in a web view. When Withings redirects to the registered callback, the code is taken from
/// the address and the page is never loaded.
struct WithingsSignInView: UIViewRepresentable {
    let state: String
    let onCode: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: WithingsService.authorizeURL(state: state)))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WithingsSignInView
        init(_ parent: WithingsSignInView) { self.parent = parent }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, url.absoluteString.hasPrefix(WithingsService.redirect) else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let value = { (name: String) in items.first { $0.name == name }?.value }
            if let code = value("code"), value("state") == parent.state {
                parent.onCode(code)
            } else {
                parent.onError(value("error") ?? "Withings didn't grant access.")
            }
        }
    }
}

struct WithingsSection: View {
    let model: DashboardModel

    var body: some View {
        Section {
            if !WithingsService.isConfigured {
                Text("Not set up in this build. Run scripts/withings-secrets.sh on the Mac and rebuild.")
                    .foregroundStyle(.secondary)
            } else if model.withingsConnected {
                LabeledContent("Status", value: "Connected")
                if let last = WithingsService.cached().fetchedAt {
                    LabeledContent("Last sync", value: last.formatted(.dateTime.day().month().hour().minute()))
                }
                Button("Disconnect", role: .destructive) {
                    WithingsService.disconnect()
                    Task { await model.refresh() }
                }
            } else {
                NavigationLink("Connect Withings") { WithingsConnectPage(model: model) }
            }
            if let message = model.withingsMessage {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Withings")
        } footer: {
            Text("Adds muscle mass, body water, bone mass and visceral fat from your Body Smart, which Apple Health can't store. Only your phone and Withings talk.")
        }
    }
}

/// A full page rather than a sheet: a sheet presented from a row of a Form that is itself in a sheet gets
/// dismissed on the next redraw, which closed the sign-in before you could type.
struct WithingsConnectPage: View {
    let model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    @State private var state = UUID().uuidString
    @State private var working = false
    @State private var error: String?

    var body: some View {
        ZStack {
            if working {
                ProgressView("Connecting…")
            } else if let error {
                VStack(spacing: 12) {
                    Text(error).multilineTextAlignment(.center)
                    Button("Try again") {
                        state = UUID().uuidString
                        self.error = nil
                    }
                }
                .padding()
            } else {
                WithingsSignInView(state: state, onCode: connect, onError: { error = $0 })
                    .id(state)
            }
        }
        .navigationTitle("Connect Withings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func connect(_ code: String) {
        working = true
        Task {
            do {
                try await WithingsService.exchange(code: code)
                model.withingsMessage = nil
                await model.refresh()
                dismiss()
            } catch {
                working = false
                self.error = error.localizedDescription
            }
        }
    }
}
