import Testing
@testable import Uncial

@Suite struct DiskSyncTests {
    @Test func ownWriteEchoIsIgnored() {
        #expect(DiskSync.decide(disk: "a", text: "a", diskText: "a") == .ignore)
        #expect(DiskSync.decide(disk: "a", text: "b", diskText: "a") == .ignore)
    }

    @Test func externalChangeAdoptedWhenEditorIsClean() {
        #expect(DiskSync.decide(disk: "new", text: "old", diskText: "old") == .adopt)
    }

    @Test func diskAlreadyMatchingEditorIsAdopted() {
        #expect(DiskSync.decide(disk: "b", text: "b", diskText: "a") == .adopt)
    }

    @Test func localEditsWinOverConcurrentExternalChange() {
        #expect(DiskSync.decide(disk: "theirs", text: "mine", diskText: "old") == .keepLocal)
    }
}
