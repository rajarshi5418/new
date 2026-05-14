// Services/ClaudeService.swift
// Sends images to the Anthropic Messages API and returns parsed AnalysisResult.

import Foundation
import UIKit

// MARK: - Errors

enum ClaudeError: LocalizedError {
    case noAPIKey
    case invalidResponse(Int, String)
    case networkError(Error)
    case imageEncodingFailed
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Anthropic API key is not set. Please add it in the Settings tab."
        case .invalidResponse(let code, let body):
            return "API error \(code): \(body)"
        case .networkError(let err):
            return "Network error: \(err.localizedDescription)"
        case .imageEncodingFailed:
            return "Could not encode the image for upload."
        case .decodingFailed(let err):
            return "Failed to decode API response: \(err.localizedDescription)"
        }
    }
}

// MARK: - ClaudeService

actor ClaudeService {
    static let shared = ClaudeService()

    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let maxImageDimension: CGFloat = 1568
    private let jpegCompressionQuality: CGFloat = 0.85
    private let model = "claude-sonnet-4-6"
    private let maxTokens = 2048

    // The large system prompt — must be >2048 tokens for prompt caching to activate.
    private let systemPrompt = """
You are an expert visual analyst with deep knowledge across many domains including:

VISUAL PERCEPTION & COMPOSITION
- Photographic composition: rule of thirds, leading lines, symmetry, framing,
  depth of field, bokeh, foreground/background relationships.
- Colour theory: hue, saturation, value, complementary colours, colour harmony,
  warm vs cool palettes, colour psychology.
- Lighting analysis: direction (front, side, back, top), quality (hard/soft),
  colour temperature (Kelvin scale), shadows, highlights, dynamic range.
- Spatial reasoning: perspective, vanishing points, scale relationships,
  three-dimensional layout inferred from a two-dimensional image.

SCENE UNDERSTANDING
- Object recognition: identify items, their material, approximate size, state
  (new/used/damaged), and likely purpose.
- People & expressions: posture, gesture, facial expression (if clearly
  visible), apparent activity, interpersonal dynamics.
- Environment classification: indoor/outdoor, architectural style, geographic
  cues, time of day, season, weather conditions.
- Text & symbols: read any visible text, logos, signs, or iconography and
  explain their significance in context.

TECHNICAL IMAGE QUALITY
- Sharpness, noise/grain level, motion blur, chromatic aberration, lens
  distortion, exposure (under/over/correct), white balance.
- Estimated capture conditions: handheld vs tripod, natural vs artificial
  light, consumer vs professional equipment.

CONTEXTUAL & CULTURAL ANALYSIS
- Identify cultural artefacts, traditions, or references visible in the scene.
- Note safety considerations if relevant (e.g., hazards, PPE compliance).
- Highlight anything unusual, unexpected, or noteworthy in the scene.

DOCUMENT ANALYSIS (when a government or administrative document is visible)
- Read all visible text carefully, including handwritten annotations.
- Extract key metadata: Name, Department, File No., Sanchika No., Rank/ID,
  Unit, Subject (Hindi and/or English), Year, Purpose.
- Note any stamps, signatures, reference numbers, or official seals.
- Identify the document type (order, circular, letter, file, register, etc.).
- Flag any inconsistencies, corrections, or areas of poor legibility.
- If text appears in Hindi/Devanagari, transliterate or translate where helpful.

RESPONSE FORMAT
Structure every analysis with these exact sections and headings:
1. **Summary** — one-sentence overview of what the photo shows.
2. **Main Subjects** — primary objects, people, or focal points.
3. **Environment & Context** — setting, background, spatial layout.
4. **Technical Quality** — lighting, sharpness, exposure, colour balance.
5. **Notable Details** — anything interesting, unusual, or worth pointing out.
6. **Suggested Follow-up** — one question or action the viewer might explore.

After the six sections, if the image shows a document, add a section:
**Document Metadata** — list any extractable fields:
- Name:
- Department:
- File No.:
- Sanchika No.:
- Rank/ID:
- Unit:
- Subject (Hindi):
- Subject (English):
- Year:
- Purpose:

Be precise, concise, and informative. If you are uncertain about something,
say so rather than guessing. Focus on what is actually visible in the image.
"""

    private init() {}

    // MARK: - Public API

    func analyze(image: UIImage, prompt: String = "") async throws -> AnalysisResult {
        let apiKey = UserDefaults.standard.string(forKey: "anthropic_api_key") ?? ""
        guard !apiKey.isEmpty else { throw ClaudeError.noAPIKey }

        // Resize and encode
        guard let imageData = prepareImage(image) else {
            throw ClaudeError.imageEncodingFailed
        }
        let base64 = imageData.base64EncodedString()

        let question = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Please analyse this photo in detail following your structured format."
            : prompt

        // Build request body
        let requestBody = ClaudeRequest(
            model: model,
            max_tokens: maxTokens,
            system: [
                ClaudeRequest.SystemBlock(
                    type: "text",
                    text: systemPrompt,
                    cache_control: ClaudeRequest.SystemBlock.CacheControl(type: "ephemeral")
                )
            ],
            messages: [
                ClaudeRequest.Message(
                    role: "user",
                    content: [
                        ClaudeRequest.ContentBlock(imageSource: ClaudeRequest.ImageSource(
                            type: "base64",
                            media_type: "image/jpeg",
                            data: base64
                        )),
                        ClaudeRequest.ContentBlock(text: question)
                    ]
                )
            ]
        )

        let jsonData: Data
        do {
            jsonData = try JSONEncoder().encode(requestBody)
        } catch {
            throw ClaudeError.decodingFailed(error)
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = jsonData

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ClaudeError.networkError(error)
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw ClaudeError.invalidResponse(httpResponse.statusCode, body)
        }

        let claudeResponse: ClaudeResponse
        do {
            claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        } catch {
            throw ClaudeError.decodingFailed(error)
        }

        // Log token usage
        let usage = claudeResponse.usage
        print("[ClaudeService] Tokens — input: \(usage.input_tokens), "
            + "cache_write: \(usage.cache_creation_input_tokens ?? 0), "
            + "cache_read: \(usage.cache_read_input_tokens ?? 0), "
            + "output: \(usage.output_tokens)")

        let rawText = claudeResponse.fullText
        return AnalysisResult.parse(from: rawText)
    }

    // MARK: - Image Preparation

    private func prepareImage(_ image: UIImage) -> Data? {
        let resized = resizeImage(image, maxDimension: maxImageDimension)
        return resized.jpegData(compressionQuality: jpegCompressionQuality)
    }

    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return image }

        let scale = maxDimension / longestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Photo Saver

/// Saves a UIImage as JPEG in the app's Documents directory.
/// Returns the absolute file path string.
func savePhotoToDisk(_ image: UIImage) -> String? {
    guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
        return nil
    }
    let fileName = "\(UUID().uuidString).jpg"
    let fileURL = documentsURL.appendingPathComponent(fileName)
    guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
    do {
        try data.write(to: fileURL)
        return fileURL.path
    } catch {
        print("[savePhoto] Error writing photo: \(error)")
        return nil
    }
}
