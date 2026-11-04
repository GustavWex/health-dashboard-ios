import Testing
@testable import HealthCore

@Suite struct ReasoningTests {
    @Test func gemmaChannel() {
        let r = ReasoningSplitter.split("<|channel>thought\nThe user said test.<channel|>Hi, it works.")
        #expect(r.answer == "Hi, it works.")
        #expect(r.reasoning == "The user said test.")
    }

    @Test func thinkTagsAndOrphans() {
        #expect(ReasoningSplitter.split("<think>hmm</think>\n\nAnswer").answer == "Answer")
        let orphanClose = ReasoningSplitter.split("first I consider X</think>Answer")
        #expect(orphanClose.answer == "Answer")
        #expect(orphanClose.reasoning == "first I consider X")
        #expect(ReasoningSplitter.split("Answer <think>cut off").answer == "Answer")
    }

    @Test func plainTextUntouched() {
        let r = ReasoningSplitter.split("Recovery was lower after late meals.")
        #expect(r.answer == "Recovery was lower after late meals.")
        #expect(r.reasoning == nil)
    }
}
