import Foundation
import Testing
@testable import Nami

struct StringNormalizationTests {
    @Test func stripsHTMLTags() {
        let input = "A <b>bold</b> statement"
        #expect(input.plainTextFromHTML == "A bold statement")
    }

    @Test func convertsLineBreaks() {
        let input = "First line<br>Second line<br/>Third line"
        #expect(input.plainTextFromHTML == "First line\nSecond line\nThird line")
    }

    @Test func decodesNamedEntities() {
        let input = "Tom &amp; Jerry &quot;quote&quot; &mdash; done &hellip;"
        #expect(input.plainTextFromHTML == "Tom & Jerry \"quote\" \u{2014} done \u{2026}")
    }

    @Test func decodesNumericEntities() {
        let input = "It&#039;s 100&#37; &#x2764;"
        #expect(input.plainTextFromHTML == "It's 100% \u{2764}")
    }

    @Test func collapsesExcessWhitespaceAndNewlines() {
        let input = "Line one<br><br><br>Line two"
        #expect(input.plainTextFromHTML == "Line one\n\nLine two")
    }

    @Test func trimsWhitespace() {
        let input = "   padded   "
        #expect(input.plainTextFromHTML == "padded")
    }

    @Test func emptyStringReturnsEmpty() {
        #expect("".plainTextFromHTML.isEmpty)
        #expect("".nilIfEmpty == nil)
    }

    @Test func normalizedWhitespaceCollapsesSpaces() {
        #expect("  a   b \n c ".normalizedWhitespace == "a b c")
    }
}
