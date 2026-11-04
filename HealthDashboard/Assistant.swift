import Foundation
import Security
import HealthCore

/// Where questions go. Gemini has its own API; everything else here speaks the OpenAI-compatible chat format,
/// so a new provider is usually just a base URL and a model name under "Custom".
enum AssistantProvider: String, CaseIterable, Identifiable {
    case gemini, groq, ollama, custom

    var id: String { rawValue }

    var name: String {
        switch self {
        case .gemini: "Google Gemini"
        case .groq: "Groq"
        case .ollama: "Ollama on my Mac"
        case .custom: "Custom (OpenAI-compatible)"
        }
    }

    var usesGeminiAPI: Bool { self == .gemini }
    var needsKey: Bool { self == .gemini || self == .groq }
    var editableURL: Bool { self == .ollama || self == .custom }

    var defaultURL: String {
        switch self {
        case .gemini: "https://generativelanguage.googleapis.com/v1beta"
        case .groq: "https://api.groq.com/openai/v1"
        case .ollama: "http://localhost:11434/v1"
        case .custom: "https://"
        }
    }

    /// Starting points; "Load models" lists what the provider actually offers.
    var defaultModel: String {
        switch self {
        case .gemini: "gemini-flash-latest"
        case .groq: "openai/gpt-oss-120b"
        case .ollama: "llama3.2"
        case .custom: ""
        }
    }

    var keyHelp: String {
        switch self {
        case .gemini: "Create a free key at aistudio.google.com."
        case .groq: "Create a free key at console.groq.com."
        case .ollama: "No key. Run Ollama on your Mac and use its address, for example http://your-mac.local:11434/v1, on the same Wi-Fi."
        case .custom: "Any service with an OpenAI-compatible /chat/completions endpoint."
        }
    }
}

/// Settings per provider, in UserDefaults; keys in the Keychain.
struct AssistantConfig {
    static let enabledKey = "assistantEnabled"
    static let providerKey = "assistantProvider"
    static let daysKey = "assistantDays"

    let provider: AssistantProvider
    let baseURL: String
    let model: String
    let key: String?

    static var current: AssistantConfig {
        let d = UserDefaults.standard
        let p = AssistantProvider(rawValue: d.string(forKey: providerKey) ?? "") ?? .gemini
        return AssistantConfig(provider: p,
                               baseURL: d.string(forKey: "assistantURL." + p.rawValue) ?? p.defaultURL,
                               model: d.string(forKey: "assistantModel." + p.rawValue) ?? p.defaultModel,
                               key: Keychain.get(p.rawValue))
    }
}

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
    /// The model's thinking, kept apart from the answer and never sent back in later turns.
    var reasoning: String? = nil
}

struct AssistantReply {
    let answer: String
    let reasoning: String?
}

struct AssistantError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum AssistantClient {
    static func send(system: String, messages: [ChatMessage], config c: AssistantConfig) async throws -> AssistantReply {
        guard !c.model.isEmpty else { throw AssistantError(message: "Choose a model first.") }
        if c.provider.needsKey && (c.key ?? "").isEmpty { throw AssistantError(message: "Add an API key first.") }
        let base = c.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        var request: URLRequest
        let body: [String: Any]
        if c.provider.usesGeminiAPI {
            guard let url = URL(string: "\(base)/models/\(c.model):generateContent") else { throw AssistantError(message: "Bad address.") }
            request = URLRequest(url: url)
            request.setValue(c.key, forHTTPHeaderField: "x-goog-api-key")
            body = [
                "systemInstruction": ["parts": [["text": system]]],
                "contents": messages.map { ["role": $0.role == .user ? "user" : "model", "parts": [["text": $0.text]]] },
            ]
        } else {
            guard let url = URL(string: "\(base)/chat/completions") else { throw AssistantError(message: "Bad address.") }
            request = URLRequest(url: url)
            if let key = c.key, !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            body = [
                "model": c.model,
                "messages": [["role": "system", "content": system]]
                    + messages.map { ["role": $0.role == .user ? "user" : "assistant", "content": $0.text] },
            ]
        }
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let json = try await fetch(request)
        var text = "", thoughts: [String] = []
        if c.provider.usesGeminiAPI {
            // Thinking models flag reasoning parts with "thought": true
            let parts = ((json["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
            for p in parts {
                guard let t = p["text"] as? String else { continue }
                if p["thought"] as? Bool == true { thoughts.append(t) } else { text += t }
            }
        } else {
            // Some OpenAI-compatible servers return reasoning in its own field
            let message = (json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
            text = message?["content"] as? String ?? ""
            if let r = (message?["reasoning"] ?? message?["reasoning_content"]) as? String { thoughts.append(r) }
        }
        // Others write it inline, in tags
        let split = ReasoningSplitter.split(text)
        if let r = split.reasoning { thoughts.append(r) }
        guard !split.answer.isEmpty else { throw AssistantError(message: "The provider sent an empty answer.") }
        let reasoning = thoughts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return AssistantReply(answer: split.answer, reasoning: reasoning.isEmpty ? nil : reasoning.joined(separator: "\n\n"))
    }

    /// Models the provider offers for chat.
    static func models(config c: AssistantConfig) async throws -> [String] {
        let base = c.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: c.provider.usesGeminiAPI ? "\(base)/models?pageSize=200" : "\(base)/models") else {
            throw AssistantError(message: "Bad address.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        if c.provider.usesGeminiAPI {
            request.setValue(c.key, forHTTPHeaderField: "x-goog-api-key")
        } else if let key = c.key, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        let json = try await fetch(request)
        if c.provider.usesGeminiAPI {
            return ((json["models"] as? [[String: Any]]) ?? [])
                .filter { ($0["supportedGenerationMethods"] as? [String])?.contains("generateContent") == true }
                .compactMap { ($0["name"] as? String)?.replacingOccurrences(of: "models/", with: "") }
                .sorted()
        }
        return ((json["data"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }.sorted()
    }

    private static func fetch(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let detail = (json["error"] as? [String: Any])?["message"] as? String ?? String(data: data, encoding: .utf8) ?? ""
            throw AssistantError(message: "Error \(http.statusCode): \(detail.prefix(300))")
        }
        return json
    }
}

/// API keys live in the Keychain, only on this device.
enum Keychain {
    static let assistant = "dk.gustavwex.HealthDashboard.assistant"
    static let withings = "dk.gustavwex.HealthDashboard.withings"

    static func get(_ account: String, service: String = assistant) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String, service: String = assistant) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}
