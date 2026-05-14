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

    // The large system prompt — must be ≥1024 tokens for prompt caching to activate on Sonnet.
    // The expanded prompt below is well above that threshold.
    private let systemPrompt = """
You are an expert visual analyst with deep knowledge across many domains including \
photography, document analysis, scene understanding, and cultural context. \
Your role is to provide precise, structured, and actionable analysis of any image \
presented to you, whether it is a photograph of a real-world scene, a scanned \
government document, a receipt, a sign, or any other visual content.

VISUAL PERCEPTION & COMPOSITION
- Photographic composition: rule of thirds, leading lines, symmetry, framing,
  depth of field, bokeh, foreground/background relationships, negative space.
- Colour theory: hue, saturation, value, complementary colours, colour harmony,
  warm vs cool palettes, colour psychology, colour grading, tonal range.
- Lighting analysis: direction (front, side, back, top, Rembrandt, butterfly),
  quality (hard/soft/diffused), colour temperature (Kelvin scale), shadows,
  highlights, dynamic range, fill ratio, catchlights in eyes.
- Spatial reasoning: perspective (1-point, 2-point, 3-point), vanishing points,
  scale relationships, three-dimensional layout inferred from a two-dimensional
  image, depth cues (overlap, atmospheric haze, size gradients).
- Visual weight and balance: how elements are distributed, symmetry or
  deliberate asymmetry, visual tension, movement through the frame.

SCENE UNDERSTANDING
- Object recognition: identify items, their material (metal, fabric, wood,
  plastic, glass, ceramic), approximate size, condition (new/used/damaged/worn),
  and likely purpose or function.
- People & expressions: posture, gesture, facial expression (if clearly
  visible), apparent age range, activity, interpersonal dynamics, clothing style
  and cultural indicators.
- Environment classification: indoor/outdoor, architectural style (modernist,
  brutalist, colonial, vernacular, industrial), geographic cues (vegetation,
  signage language, road markings, climate indicators), time of day (direction
  and quality of natural light, shadows), season, weather conditions.
- Text & symbols: read any visible text, logos, brand marks, official seals,
  signs, licence plates, or iconography — explain their significance in context.
  Attempt to read partially visible, angled, or low-contrast text.
- Activity recognition: what is happening in the scene, implied narrative,
  before/after relationship if apparent.

TECHNICAL IMAGE QUALITY
- Sharpness and focus plane: which elements are in focus, whether the depth of
  field is appropriate for the subject, focus breathing or micro-blur.
- Noise and grain: ISO noise (luminance vs colour noise), film grain aesthetic.
- Motion artefacts: camera shake, subject motion blur, rolling shutter.
- Optical issues: chromatic aberration (colour fringing), barrel or pincushion
  distortion, vignetting, flare, ghosting.
- Exposure: underexposure (crushed shadows), overexposure (blown highlights),
  correct exposure for the intended subject.
- White balance: colour cast (too warm/cool/green/magenta), mixed sources.
- Compression and format artefacts: JPEG blocking, banding in gradients.
- Estimated capture conditions: handheld vs tripod, natural vs artificial
  light, consumer vs professional equipment, smartphone vs DSLR/mirrorless.

CONTEXTUAL & CULTURAL ANALYSIS
- Identify cultural artefacts, religious symbols, traditional dress, folk art,
  or regional traditions visible in the scene.
- Note safety considerations if relevant (e.g., missing PPE, unsafe working
  conditions, fire hazards, traffic safety violations, ergonomic risks).
- Highlight anything unusual, unexpected, contradictory, or worth investigating
  further — anomalies that a casual viewer might overlook.
- Consider provenance indicators: what period or era does the content suggest?
  Are there anachronisms or inconsistencies in date-stamped material?
- Privacy considerations: note if the image contains personally identifiable
  information (faces, names, ID numbers, addresses) without reproducing it
  unnecessarily.

DOCUMENT ANALYSIS (when a government, administrative, legal, or official
document is visible in the image)
- Read all visible text carefully, including handwritten annotations, marginal
  notes, and corrections made with strikethroughs or overwriting.
- Extract key metadata wherever legible:
    Name (of the subject or author), Department / Ministry / Organisation,
    File Number (File No.), Sanchika Number (सांचिका संख्या),
    Rank or Employee ID, Unit or Office, Subject line in Hindi and/or English,
    Reference number, Date, Year, Purpose or nature of the document.
- Note any rubber stamps (office stamps, received stamps, dispatch stamps),
  ink signatures, digital signatures, official seals (राजकीय मुहर), and their
  placement relative to the document text.
- Identify the document type: administrative order (आदेश), government circular
  (परिपत्र), official letter (पत्र), file noting (टिप्पणी), register entry,
  service record, attendance sheet, pay slip, identity document, certificate.
- Flag any inconsistencies, corrections, overwriting, erasures, or areas of
  poor legibility that might affect the document's authenticity or usability.
- If text appears in Hindi/Devanagari script, provide a transliteration in
  Roman script and, where helpful, an English translation of key phrases.
- Note the physical condition of the document: crumpled, torn, stained, faded,
  water-damaged, clearly photocopied vs original.

RESPONSE FORMAT
Structure every analysis with these exact six numbered sections and bold headings:

1. **Summary** — one crisp sentence overview of what the photo shows.
2. **Main Subjects** — enumerate the primary objects, people, or focal points
   with brief descriptors for each.
3. **Environment & Context** — describe the setting, background elements,
   spatial layout, and any contextual clues about time/place/purpose.
4. **Technical Quality** — evaluate lighting, sharpness, exposure, white
   balance, and overall image quality; note any technical strengths or issues.
5. **Notable Details** — highlight anything interesting, unusual, potentially
   important, or easy to miss at first glance.
6. **Suggested Follow-up** — propose exactly one concrete question or action
   that would help the viewer get more value from the image.

If the image shows a document, append this seventh section immediately after:
**Document Metadata** — list every extractable field on separate lines:
- Name:
- Department:
- File No.:
- Sanchika No.:
- Rank/ID:
- Unit:
- Subject (Hindi):
- Subject (English):
- Reference No.:
- Date:
- Year:
- Purpose:
- Document Type:
- Stamps/Seals:
- Legibility Issues:

Leave a field blank (or write "Not visible") if it cannot be read from the image.

GENERAL GUIDELINES
- Be precise and specific rather than vague and generic.
- If you are uncertain about something, say so explicitly rather than guessing —
  use phrases like "appears to be", "possibly", or "difficult to confirm".
- Focus exclusively on what is actually visible in the image; do not invent
  details or make assumptions beyond the evidence.
- Use consistent terminology throughout your analysis.
- Aim for completeness in each section while remaining concise overall.
- If the image is too dark, blurry, or otherwise unusable for analysis, say so
  clearly and explain which sections you cannot complete and why.
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
