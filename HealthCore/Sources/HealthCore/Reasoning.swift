import Foundation

/// Separates a model's reasoning from its answer. Thinking models put reasoning in the reply in several ways:
/// Gemma 4 between `<|channel>` and `<channel|>` (Gemma 4 prompt formatting docs, ai.google.dev), and many open
/// models in `<think>` tags. Some servers drop the opening tag, leaving only the closing one.
public enum ReasoningSplitter {
    static let tags = [("<|channel>", "<channel|>"), ("<think>", "</think>"), ("<thinking>", "</thinking>"), ("<thought>", "</thought>")]

    public static func split(_ text: String) -> (answer: String, reasoning: String?) {
        var answer = text
        var reasoning: [String] = []
        for (open, close) in tags {
            // Paired blocks
            while let o = answer.range(of: open), let c = answer.range(of: close, range: o.upperBound..<answer.endIndex) {
                reasoning.append(String(answer[o.upperBound..<c.lowerBound]))
                answer.removeSubrange(o.lowerBound..<c.upperBound)
            }
            // A closing tag with no opening: everything before it was reasoning
            if let c = answer.range(of: close) {
                reasoning.append(String(answer[..<c.lowerBound]))
                answer.removeSubrange(..<c.upperBound)
            }
            // An opening tag never closed: the reply was cut off mid-thought
            if let o = answer.range(of: open) {
                reasoning.append(String(answer[o.upperBound...]))
                answer.removeSubrange(o.lowerBound...)
            }
        }
        let cleaned = reasoning.map(clean).filter { !$0.isEmpty }
        return (answer.trimmingCharacters(in: .whitespacesAndNewlines), cleaned.isEmpty ? nil : cleaned.joined(separator: "\n\n"))
    }

    /// Gemma labels its channel ("thought") on the first line.
    private static func clean(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        for label in ["thought", "analysis"] where t.lowercased().hasPrefix(label) {
            t = String(t.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t
    }
}
