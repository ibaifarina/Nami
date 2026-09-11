import Foundation

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var normalizedWhitespace: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    var plainTextFromHTML: String {
        guard !isEmpty else { return self }
        var text = self
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</p\\s*>", with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.decodingHTMLEntities()
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: " *\n *", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func decodingHTMLEntities() -> String {
        var text = self
        for (entity, replacement) in Self.namedHTMLEntities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return Self.replacingNumericHTMLEntities(in: text)
    }

    private static let namedHTMLEntities: [String: String] = [
        "&amp;": "&",
        "&quot;": "\"",
        "&#039;": "'",
        "&#39;": "'",
        "&apos;": "'",
        "&lt;": "<",
        "&gt;": ">",
        "&nbsp;": " ",
        "&mdash;": "\u{2014}",
        "&ndash;": "\u{2013}",
        "&hellip;": "\u{2026}",
        "&rsquo;": "\u{2019}",
        "&lsquo;": "\u{2018}",
        "&ldquo;": "\u{201C}",
        "&rdquo;": "\u{201D}",
    ]

    private static func replacingNumericHTMLEntities(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#(x?[0-9A-Fa-f]+);") else {
            return text
        }
        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard
                let digitsRange = Range(match.range(at: 1), in: text),
                let replacementRange = Range(match.range, in: result)
            else { continue }
            let digits = String(text[digitsRange])
            let isHex = digits.hasPrefix("x") || digits.hasPrefix("X")
            let value = isHex
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits)
            guard let value, let scalar = UnicodeScalar(value) else { continue }
            result.replaceSubrange(replacementRange, with: String(Character(scalar)))
        }
        return result
    }
}
