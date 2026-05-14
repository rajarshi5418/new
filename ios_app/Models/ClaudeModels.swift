// Models/ClaudeModels.swift
// Codable structs for the Anthropic Messages API plus parsed AnalysisResult.

import Foundation

// MARK: - API Request

struct ClaudeRequest: Encodable {
    let model: String
    let max_tokens: Int
    let system: [SystemBlock]
    let messages: [Message]

    struct SystemBlock: Encodable {
        let type: String
        let text: String
        let cache_control: CacheControl

        struct CacheControl: Encodable {
            let type: String
        }
    }

    struct Message: Encodable {
        let role: String
        let content: [ContentBlock]
    }

    struct ContentBlock: Encodable {
        let type: String
        // For image blocks
        let source: ImageSource?
        // For text blocks
        let text: String?

        init(text: String) {
            self.type = "text"
            self.source = nil
            self.text = text
        }

        init(imageSource: ImageSource) {
            self.type = "image"
            self.source = imageSource
            self.text = nil
        }
    }

    struct ImageSource: Encodable {
        let type: String
        let media_type: String
        let data: String
    }
}

// MARK: - API Response

struct ClaudeResponse: Decodable {
    let content: [ContentBlock]
    let usage: Usage

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    struct Usage: Decodable {
        let input_tokens: Int
        let output_tokens: Int
        let cache_creation_input_tokens: Int?
        let cache_read_input_tokens: Int?
    }

    /// Concatenated text from all text content blocks.
    var fullText: String {
        content.compactMap { $0.text }.joined(separator: "\n")
    }
}

// MARK: - Parsed Analysis Result

struct AnalysisResult {
    // Six structured sections
    var summary: String = ""
    var mainSubjects: String = ""
    var environmentContext: String = ""
    var technicalQuality: String = ""
    var notableDetails: String = ""
    var suggestedFollowUp: String = ""

    // Document metadata extracted via regex
    var name: String = ""
    var department: String = ""
    var fileNo: String = ""
    var sanchikaNo: String = ""
    var rankId: String = ""
    var unit: String = ""
    var subjectHindi: String = ""
    var subjectEnglish: String = ""
    var year: String = ""
    var purpose: String = ""

    // Full raw text from Claude
    var rawText: String = ""

    // MARK: - Parser

    static func parse(from text: String) -> AnalysisResult {
        var result = AnalysisResult()
        result.rawText = text

        // --- Extract the 6 standard sections ---
        // Pattern: **Section Name** (optional trailing dash / colon) then content
        // until the next numbered bold heading or end of string.
        let sectionDefs: [(key: WritableKeyPath<AnalysisResult, String>, name: String)] = [
            (\.summary,            "Summary"),
            (\.mainSubjects,       "Main Subjects"),
            (\.environmentContext, "Environment & Context"),
            (\.technicalQuality,   "Technical Quality"),
            (\.notableDetails,     "Notable Details"),
            (\.suggestedFollowUp,  "Suggested Follow-up")
        ]

        for (keyPath, sectionName) in sectionDefs {
            let escaped = NSRegularExpression.escapedPattern(for: sectionName)
            let pattern = "\\*\\*\(escaped)\\*\\*[^\\n]*\\n?(.*?)(?=\\n\\d+\\.\\s+\\*\\*|\\z)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               match.numberOfRanges > 1,
               let bodyRange = Range(match.range(at: 1), in: text) {
                result[keyPath: keyPath] = String(text[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // --- Extract document metadata via regex ---
        result.name         = extract(pattern: "(?i)name\\s*[:\\-]\\s*(.+?)(?:\\n|$)", from: text)
        result.department   = extract(pattern: "(?i)department\\s*[:\\-]\\s*(.+?)(?:\\n|$)", from: text)
        result.fileNo       = extract(pattern: "(?i)(?:file\\s*no\\.?|file\\s*number)\\s*[:\\-]\\s*(.+?)(?:\\n|$)", from: text)
        result.sanchikaNo   = extract(pattern: "(?i)sanchika\\s*(?:no\\.?|number)?\\s*[:\\-]\\s*(.+?)(?:\\n|$)", from: text)
        result.rankId       = extract(pattern: "(?i)rank(?:\\s*id)?\\s*[:\\-]\\s*(.+?)(?:\\n|$)", from: text)
        result.unit         = extract(pattern: "(?i)unit\\s*[:\\-]\\s*(.+?)(?:\\n|$)", from: text)
        result.year         = extract(pattern: "(?i)year\\s*[:\\-]\\s*(\\d{4}(?:[\\-/]\\d{2,4})?)", from: text)
        result.purpose      = extract(pattern: "(?i)purpose\\s*[:\\-]\\s*(.+?)(?:\\n|$)", from: text)

        // Subject lines — try Hindi first, then generic subject
        result.subjectHindi   = extract(pattern: "(?i)subject\\s*(?:hindi|\\(hindi\\))?\\s*[:\\-]\\s*(.+?)(?:\\n|$)", from: text)
        result.subjectEnglish = extract(pattern: "(?i)subject\\s*(?:english|\\(english\\))?\\s*[:\\-]\\s*(.+?)(?:\\n|$)", from: text)

        return result
    }

    private static func extract(pattern: String, from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return ""
        }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
