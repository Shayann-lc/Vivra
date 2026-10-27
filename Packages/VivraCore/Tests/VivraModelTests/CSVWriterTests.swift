import Testing

@testable import VivraModel

@Suite struct CSVWriterTests {
    @Test func plainFieldsAreNotQuoted() {
        #expect(CSVWriter.render(header: ["a", "b"], rows: [["1", "2"]]) == "a,b\r\n1,2\r\n")
    }

    @Test func specialCharactersAreQuotedAndQuotesDoubled() {
        #expect(CSVWriter.field("lunch, outside") == "\"lunch, outside\"")
        #expect(CSVWriter.field("said \"hi\"") == "\"said \"\"hi\"\"\"")
        #expect(CSVWriter.field("two\nlines") == "\"two\nlines\"")
        #expect(CSVWriter.field("") == "")
    }

    @Test func emptyTablesKeepTheirHeader() {
        #expect(CSVWriter.render(header: ["id"], rows: []) == "id\r\n")
    }
}
