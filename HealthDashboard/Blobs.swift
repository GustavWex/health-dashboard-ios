import SwiftUI
import HealthCore

/// One part of the day shown as a soft gradient blob: sleep, food or strain.
struct BlobPart: Identifiable {
    enum Kind { case sleep, food, recovery, strain }
    let kind: Kind
    let fraction: Double          // 0...1, sets the blob's size
    let value: String
    let label: String
    let colors: [Color]           // gradient, darker to lighter
    var id: Kind { kind }
}

/// The day as glassy gradient blobs, inspired by the Apple Card spending view. Together they melt into one
/// large blob showing the balance score; tap it and it flows apart into its parts (sleep, food, strain),
/// each sized by its score; tap again to collect them. When split, buttons under the blobs open each part.
struct BlobCluster: View {
    let parts: [BlobPart]
    let headline: String
    let caption: String
    /// When set, the merged blob is washed in this colour (a good or bad indicator) and each part takes its own
    /// colour back as they split.
    var mergedTint: Color? = nil
    var onOpen: (BlobPart.Kind) -> Void

    /// 0 is merged, 1 is split. A single animated number drives positions, sizes, blur and labels, so every
    /// frame in between is drawn, including the merged outline.
    @State private var progress: Double = 0
    private var isSplit: Bool { progress > 0.5 }

    var body: some View {
        VStack(spacing: 10) {
            BlobField(parts: parts, headline: headline, caption: caption, tint: mergedTint, progress: progress)
                .frame(height: 230)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(duration: 0.9, bounce: 0.28)) { progress = isSplit ? 0 : 1 }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(isSplit ? parts.map { "\($0.label) \($0.value)" }.joined(separator: ", ") : "\(caption) \(headline)")
                .accessibilityHint(isSplit ? "Collects the parts" : "Shows the parts")
                .accessibilityAddTraits(.isButton)
            if isSplit {
                HStack(spacing: 8) {
                    ForEach(parts) { p in
                        Button { onOpen(p.kind) } label: {
                            HStack(spacing: 4) {
                                Circle().fill(p.colors.first!).frame(width: 8, height: 8)
                                Text(p.label.capitalized).lineLimit(1)
                                Image(systemName: "chevron.right").font(.caption2)
                            }
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                        }
                        .glassButton()
                        .controlSize(.small)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// The drawing, with `progress` as its animatable value: SwiftUI interpolates it frame by frame and this body
/// is redrawn for each, so the Canvas mask morphs instead of jumping.
private struct BlobField: View, @preconcurrency Animatable {
    let parts: [BlobPart]
    let headline: String
    let caption: String
    let tint: Color?
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            let layout = positions(width: geo.size.width, height: geo.size.height)
            ZStack {
                // Colour: radial gradients, blurred so neighbouring colours run into each other while merged
                ZStack {
                    ForEach(parts) { p in
                        let l = layout[p.kind]!
                        ZStack {
                            Circle()
                                .fill(RadialGradient(colors: [p.colors.last!, p.colors.first!], center: .init(x: 0.35, y: 0.3),
                                                     startRadius: 0, endRadius: max(1, l.r * 1.3)))
                                .opacity(tint == nil ? 1 : min(1, max(0, progress)))
                            if let tint {
                                Circle()
                                    .fill(RadialGradient(colors: [tint.lighter(0.45), tint], center: .init(x: 0.35, y: 0.3),
                                                         startRadius: 0, endRadius: max(1, l.r * 1.3)))
                                    .opacity(min(1, max(0, 1 - progress)))
                            }
                        }
                        .frame(width: l.r * 2, height: l.r * 2)
                        .position(l.center)
                    }
                }
                .blur(radius: lerp(22, 6))
                .mask(gooMask(layout))
                // Glass sheen from the top left, through the same outline
                LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)], startPoint: .topLeading, endPoint: .center)
                    .mask(gooMask(layout))
                    .blendMode(.softLight)

                // Merged label fades out over the first half, part labels fade in over the second
                VStack(spacing: 2) {
                    Text(headline).font(.system(size: 54, weight: .bold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: geo.size.width * 0.6)
                    Text(caption).font(.subheadline.weight(.semibold))
                    Text("tap to see the parts").font(.caption2).opacity(0.8)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .opacity(max(0, 1 - progress * 2))
                ForEach(parts) { p in
                    let l = layout[p.kind]!
                    VStack(spacing: 0) {
                        Text(p.value).font(.system(size: max(8, l.r * 0.5), weight: .bold, design: .rounded)).monospacedDigit()
                        Text(p.label).font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                    .position(l.center)
                    .opacity(max(0, min(1, progress * 2 - 1)))
                }
            }
        }
    }

    private func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * progress }

    /// The silhouette: blurred black circles cut at half opacity (a metaball), softened a hair for clean edges.
    private func gooMask(_ layout: [BlobPart.Kind: (center: CGPoint, r: CGFloat)]) -> some View {
        Canvas { ctx, _ in
            ctx.addFilter(.alphaThreshold(min: 0.5, color: .black))
            ctx.addFilter(.blur(radius: 18))
            ctx.drawLayer { layer in
                for p in parts {
                    let l = layout[p.kind]!
                    layer.fill(Path(ellipseIn: CGRect(x: l.center.x - l.r, y: l.center.y - l.r, width: l.r * 2, height: l.r * 2)),
                               with: .color(.black))
                }
            }
        }
        .blur(radius: 1.2)
    }

    /// Merged: overlapping around the centre into one big blob. Split: side by side, each sized by its score.
    /// Positions and radii are interpolated by `progress` (which may overshoot a little with the spring).
    private func positions(width: CGFloat, height: CGFloat) -> [BlobPart.Kind: (center: CGPoint, r: CGFloat)] {
        let cy = height / 2, slot = width / 3, t = CGFloat(progress)
        let merged: [CGPoint] = [CGPoint(x: width / 2 - 44, y: cy - 26), CGPoint(x: width / 2 + 10, y: cy + 6),
                                 CGPoint(x: width / 2 + 40, y: cy - 30)]
        var out: [BlobPart.Kind: (center: CGPoint, r: CGFloat)] = [:]
        for (i, p) in parts.prefix(3).enumerated() {
            let kind = p.kind
            let f = CGFloat(max(0.05, min(1, p.fraction)))
            let apart = CGPoint(x: slot * (CGFloat(i) + 0.5), y: cy + (i == 1 ? -8 : 10))
            let rMerged = 62 + 26 * f, rApart = min(slot * 0.46, 30 + 22 * f)
            out[kind] = (CGPoint(x: merged[i].x + (apart.x - merged[i].x) * t, y: merged[i].y + (apart.y - merged[i].y) * t),
                         max(4, rMerged + (rApart - rMerged) * t))
        }
        return out
    }
}

/// The three habits under the blob: target, the last 7 days as dots, streak and habit strength. Built on
/// self-monitoring and progress feedback, two of the most effective behaviour-change techniques (Michie et al.
/// 2009, Health Psychol 28(6); Harkin et al. 2016, Psychol Bull 142(2)).
struct HabitStrip: View {
    let habits: [Habit]
    let proteinTarget: Double
    var onOpen: (BlobPart.Kind) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(habits) { h in
                Button { onOpen(blob(h.kind)) } label: { row(h) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func row(_ h: Habit) -> some View {
        let color = self.color(h.kind)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name(h.kind)).font(.subheadline.weight(.semibold))
                Text(target(h.kind)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                ForEach(h.week) { d in
                    Circle()
                        .fill(d.hit == true ? color : (d.hit == false ? color.opacity(0.18) : Color.clear))
                        .overlay(Circle().strokeBorder(d.hit == nil ? Color.secondary.opacity(0.3) : .clear, lineWidth: 1))
                        .frame(width: 10, height: 10)
                }
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text(h.streak > 0 ? "\(h.streak) in a row" : "\(h.hitsThisWeek) of \(h.daysThisWeek)")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                Text("strength \(Int(h.strength.rounded()))").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(width: 78, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name(h.kind)), \(target(h.kind)). \(h.hitsThisWeek) of the last \(h.daysThisWeek) days on target, streak \(h.streak).")
    }

    private func name(_ k: HabitKind) -> String {
        switch k {
        case .sleep: "Sleep"
        case .wake: "Wake on time"
        case .food: "Food"
        case .training: "Training"
        }
    }

    /// Each target and where it comes from (see `HabitEngine`).
    private func target(_ k: HabitKind) -> String {
        switch k {
        case .sleep: "7 h or more"
        case .wake: "within 30 min of " + SleepPlanText.clock(UserDefaults.standard.object(forKey: AppSettings.wakeGoalKey) as? Double ?? AppSettings.defaultWakeGoal)
        case .food: String(format: "%.1f g/kg protein, calories near goal", proteinTarget)
        case .training: "strain on target, rest days count"
        }
    }

    private func color(_ k: HabitKind) -> Color {
        switch k {
        case .sleep, .wake: Palette.sleep
        case .food: Palette.nutrition
        case .training: Palette.strain
        }
    }

    private func blob(_ k: HabitKind) -> BlobPart.Kind {
        switch k {
        case .sleep, .wake: .sleep
        case .food: .food
        case .training: .strain
        }
    }
}

/// Yesterday's food as three bars from bad to good, with a marker where the day landed. Calories are good in the
/// middle (at the goal) and bad at both ends; protein and diet quality get better to the right.
struct FoodSliders: View {
    let model: DashboardModel
    let proteinTarget: Double
    var onOpen: () -> Void

    private var yesterday: Date { Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: .now))! }

    var body: some View {
        let s = model.snapshot
        let intake = s.dietaryEnergy.value(on: yesterday).flatMap { $0 > 300 ? $0 : nil }
        let weight = model.bodyComp?.trendWeight
        let goal = model.nutrition?.suggestedIntake(kgPerWeek: UserDefaults.standard.object(forKey: AppSettings.weightGoalKey) as? Double ?? AppSettings.defaultWeightGoal)
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Food yesterday").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                if intake == nil {
                    Text("Nothing logged yesterday.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    if let q = DietQualityEngine.score(s, on: yesterday, proteinTarget: weight.map { $0 * proteinTarget }) {
                        GoodBadSlider(title: "Quality", value: "\(Int(q.score.rounded())) of 100", position: q.score / 100, twoSided: false)
                    }
                    if let p = s.protein.value(on: yesterday), let w = weight, w > 0 {
                        // 0.8 g/kg (the general adult minimum) at the left, your target from Settings near the right
                        let ppk = p / w, t = max(proteinTarget, 0.9)
                        GoodBadSlider(title: "Protein", value: String(format: "%.1f of %.1f", ppk, proteinTarget),
                                      position: ppk < t ? 0.85 * (ppk - 0.8) / (t - 0.8) : 0.85 + 0.15 * min(1, (ppk - t) / 0.6), twoSided: false)
                    }
                    if let i = intake, let g = goal, g > 0 {
                        GoodBadSlider(title: "Calories", value: "\(Int(i)) of \(Int(g))", position: 0.5 + (i - g) / g / 0.5, twoSided: true)
                    }
                }
            }
            .padding(12)
            .background(Palette.nutrition.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// A bar coloured from bad to good with a marker at `position` (0 to 1). Two-sided bars are good in the middle.
struct GoodBadSlider: View {
    let title: String
    let value: String
    let position: Double
    let twoSided: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.caption).frame(width: 58, alignment: .leading)
            GeometryReader { g in
                let x = g.size.width * CGFloat(min(1, max(0, position)))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: twoSided ? [Palette.bad, Palette.caution, Palette.good, Palette.caution, Palette.bad]
                                                              : [Palette.bad, Palette.caution, Palette.good],
                                             startPoint: .leading, endPoint: .trailing))
                        .opacity(0.35)
                        .frame(height: 6)
                    Circle()
                        .fill(.white)
                        .overlay(Circle().strokeBorder(Theme.ink.opacity(0.7), lineWidth: 2))
                        .frame(width: 14, height: 14)
                        .offset(x: x - 7)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 16)
            Text(value).font(.caption.weight(.semibold)).monospacedDigit().frame(width: 84, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
    }
}

enum SleepPlanText {
    /// "07:40" from minutes after midnight.
    static func clock(_ m: Double) -> String {
        let v = Int(SleepPlan.wrap(m).rounded()) % 1440
        return String(format: "%02d:%02d", v / 60, v % 60)
    }
}
