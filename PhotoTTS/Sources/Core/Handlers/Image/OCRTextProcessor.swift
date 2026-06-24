import Foundation

struct OCRTextProcessor {
    static func process(_ text: String) -> String {
        var processedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        processedText = processedText.replacingOccurrences(of: "\n\n+", with: "\n", options: .regularExpression)
        processedText = processedText.replacingOccurrences(of: "\\.{6,}", with: "...", options: .regularExpression)
        return processedText
    }
}
