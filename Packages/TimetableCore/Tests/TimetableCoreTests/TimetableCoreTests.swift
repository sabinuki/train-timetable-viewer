import Testing
@testable import TimetableCore

@Test func versionIsDefined() {
    #expect(!TimetableCore.version.isEmpty)
}
