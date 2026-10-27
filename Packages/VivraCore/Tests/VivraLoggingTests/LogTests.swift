import Testing

@testable import VivraLogging

@Suite struct LogTests {
    @Test func categoriesAreDistinct() {
        #expect(Log.app.category == "app")
        #expect(Log.store.category == "store")
    }

    @Test func loggingDoesNotTrap() {
        let log = Log(category: "test")
        log.event("event")
        log.event("event with count", count: 3)
        log.failure("failure", code: -1)
    }

    @Test func measureReturnsAndRethrows() async {
        let log = Log(category: "test")
        let value = await log.measure("interval") { 42 }
        #expect(value == 42)

        struct Failure: Error {}
        await #expect(throws: Failure.self) {
            try await log.measure("failing interval") { throw Failure() }
        }
    }
}
