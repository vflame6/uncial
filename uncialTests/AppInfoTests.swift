import Testing
@testable import Uncial

@Suite struct AppInfoTests {
    @Test func formatsVersionAndBuild() {
        let info = AppInfo(info: ["CFBundleName": "Uncial", "CFBundleShortVersionString": "1.2", "CFBundleVersion": "34"])
        #expect(info.name == "Uncial")
        #expect(info.version == "1.2 (34)")
        #expect(info.copyright == nil)
    }

    @Test func toleratesMissingBuildAndBlankCopyright() {
        let info = AppInfo(info: ["CFBundleShortVersionString": "2.0", "NSHumanReadableCopyright": "  "])
        #expect(info.version == "2.0")
        #expect(info.name == "Uncial")
        #expect(info.copyright == nil)
        #expect(AppInfo(info: ["NSHumanReadableCopyright": "© Me"]).copyright == "© Me")
    }

    @Test func readsTheHostBundle() {
        #expect(!AppInfo().version.isEmpty)
    }
}
