import Testing
import Foundation
@testable import SwiftUIAssistant

@Suite("Markdown Rendering Tests")
struct MarkdownRenderingTests {

    // MARK: - Plain Text

    @Test
    func testPlainTextParsing() throws {
        let content = "Hello, world!"
        let attributed = try AttributedString(markdown: content)
        #expect(String(attributed.characters) == "Hello, world!")
    }

    @Test
    func testEmptyString() throws {
        let content = ""
        let attributed = try AttributedString(markdown: content)
        #expect(String(attributed.characters) == "")
    }

    @Test
    func testMultilineText() throws {
        // With inlineOnlyPreservingWhitespace, newlines are preserved
        let content = "Line 1\nLine 2\nLine 3"
        let attributed = try AttributedString(
            markdown: content,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )
        let text = String(attributed.characters)
        // Verify line breaks are preserved
        #expect(text == "Line 1\nLine 2\nLine 3")
    }

    // MARK: - Bold

    @Test
    func testBoldWithDoubleAsterisks() throws {
        let content = "This is **bold** text"
        let attributed = try AttributedString(markdown: content)
        #expect(String(attributed.characters) == "This is bold text")
    }

    @Test
    func testBoldWithDoubleUnderscores() throws {
        let content = "This is __bold__ text"
        let attributed = try AttributedString(markdown: content)
        #expect(String(attributed.characters) == "This is bold text")
    }

    @Test
    func testMultipleBoldSections() throws {
        let content = "**First** and **second** bold"
        let attributed = try AttributedString(markdown: content)
        #expect(String(attributed.characters) == "First and second bold")
    }

    // MARK: - Italic

    @Test
    func testItalicWithSingleAsterisk() throws {
        let content = "This is *italic* text"
        let attributed = try AttributedString(markdown: content)
        #expect(String(attributed.characters) == "This is italic text")
    }

    @Test
    func testItalicWithSingleUnderscore() throws {
        let content = "This is _italic_ text"
        let attributed = try AttributedString(markdown: content)
        #expect(String(attributed.characters) == "This is italic text")
    }

    // MARK: - Code

    @Test
    func testInlineCode() throws {
        let content = "Use `swift build` command"
        let attributed = try AttributedString(markdown: content)
        #expect(String(attributed.characters) == "Use swift build command")
    }

    @Test
    func testMultipleCodeSpans() throws {
        let content = "Use `git add` then `git commit`"
        let attributed = try AttributedString(markdown: content)
        #expect(String(attributed.characters) == "Use git add then git commit")
    }

    // MARK: - Mixed Formatting

    @Test
    func testMixedBoldAndItalic() throws {
        let content = "**Bold** and *italic* text"
        let attributed = try AttributedString(markdown: content)
        #expect(String(attributed.characters) == "Bold and italic text")
    }

    @Test
    func testMixedWithCode() throws {
        let content = "**Bold** and *italic* with `code`"
        let attributed = try AttributedString(markdown: content)
        #expect(String(attributed.characters) == "Bold and italic with code")
    }

    @Test
    func testBoldItalicCombined() throws {
        let content = "This is ***bold and italic***"
        let attributed = try AttributedString(markdown: content)
        #expect(String(attributed.characters) == "This is bold and italic")
    }

    // MARK: - Links

    @Test
    func testMarkdownLink() throws {
        let content = "Visit [Apple](https://apple.com)"
        let attributed = try AttributedString(markdown: content)
        #expect(String(attributed.characters) == "Visit Apple")
    }

    @Test
    func testAutoLink() throws {
        let content = "Visit https://apple.com"
        let attributed = try AttributedString(markdown: content)
        // Auto-links should preserve the URL text
        #expect(String(attributed.characters).contains("apple.com"))
    }

    // MARK: - Strikethrough

    @Test
    func testStrikethrough() throws {
        let content = "This is ~~deleted~~ text"
        let attributed = try AttributedString(markdown: content)
        #expect(String(attributed.characters) == "This is deleted text")
    }

    // MARK: - Special Characters

    @Test
    func testEscapedCharacters() throws {
        let content = "Use \\*asterisks\\* literally"
        let attributed = try AttributedString(markdown: content)
        #expect(String(attributed.characters) == "Use *asterisks* literally")
    }

    @Test
    func testAmpersandAndAngles() throws {
        let content = "Compare a < b & c > d"
        let attributed = try AttributedString(markdown: content)
        #expect(String(attributed.characters) == "Compare a < b & c > d")
    }

    // MARK: - Edge Cases

    @Test
    func testUnbalancedMarkdown() {
        // Unbalanced markdown should still render something
        let content = "Unbalanced **bold"
        let attributed = (try? AttributedString(markdown: content))
            ?? AttributedString(content)
        #expect(!String(attributed.characters).isEmpty)
    }

    @Test
    func testEmptyFormatting() throws {
        let content = "Empty ** ** bold"
        let attributed = try AttributedString(markdown: content)
        // Should handle gracefully
        #expect(!String(attributed.characters).isEmpty)
    }

    @Test
    func testNestedFormatting() throws {
        let content = "**Bold with *nested italic***"
        let attributed = try AttributedString(markdown: content)
        #expect(String(attributed.characters) == "Bold with nested italic")
    }

    // MARK: - Lists (Text Only)

    @Test
    func testBulletListRendersText() throws {
        let content = "- Item 1\n- Item 2"
        let attributed = try AttributedString(markdown: content)
        // Bullet lists should render their text content
        let text = String(attributed.characters)
        #expect(text.contains("Item 1"))
        #expect(text.contains("Item 2"))
    }

    // MARK: - Paragraph Preservation

    @Test
    func testParagraphsPreserved() throws {
        let content = "First paragraph.\n\nSecond paragraph."
        let attributed = try AttributedString(
            markdown: content,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )
        let text = String(attributed.characters)
        // Double newlines should be preserved
        #expect(text.contains("\n\n"))
        #expect(text == "First paragraph.\n\nSecond paragraph.")
    }

    // MARK: - Typical Assistant Messages

    @Test
    func testTypicalAssistantResponse() throws {
        let content = """
            I'll create a **red cube** for you using `create_primitive`.

            Here's what I did:
            - Created a *box* primitive
            - Set the color to **red**
            """
        let attributed = try AttributedString(
            markdown: content,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )
        let text = String(attributed.characters)

        #expect(text.contains("red cube"))
        #expect(text.contains("create_primitive"))
        #expect(text.contains("box"))
        #expect(text.contains("red"))
        // Verify paragraph break is preserved
        #expect(text.contains("\n\n"))
    }
}
