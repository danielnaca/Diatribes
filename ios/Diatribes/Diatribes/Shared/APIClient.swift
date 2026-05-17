import Foundation

// MARK: - Claude response types

struct ClaudeResponse: Codable {
    let correction: String?
    let response: String
    let trouble_words: [String]?
}

// MARK: - APIClient

enum APIError: LocalizedError {
    case httpError(Int)
    case decodingError(String)
    case noData

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "HTTP \(code)"
        case .decodingError(let msg): return "Decode error: \(msg)"
        case .noData: return "No data received"
        }
    }
}

struct APIClient {
    static let shared = APIClient()
    private init() {}

    // MARK: Whisper transcription

    func transcribe(audioData: Data, mimeType: String = "audio/m4a") async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Config.openAIKey)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendFormField(name: "model", value: "whisper-1", boundary: boundary)
        body.appendFileField(name: "file", filename: "audio.m4a", mimeType: mimeType, data: audioData, boundary: boundary)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw APIError.httpError(http.statusCode)
        }

        struct TranscriptResponse: Codable { let text: String }
        let decoded = try JSONDecoder().decode(TranscriptResponse.self, from: data)
        return decoded.text
    }

    // MARK: Claude respond

    func respond(
        userText: String,
        history: [HistoryMessage],
        systemPrompt: String
    ) async throws -> ClaudeResponse {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.anthropicKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var messages = history.map { ["role": $0.role, "content": $0.content] }
        messages.append(["role": "user", "content": userText])

        let payload: [String: Any] = [
            "model": Config.claudeModel,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": messages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw APIError.httpError(http.statusCode)
        }

        // Parse Anthropic envelope → extract content[0].text → decode JSON
        struct AnthropicEnvelope: Codable {
            struct ContentBlock: Codable { let type: String; let text: String? }
            let content: [ContentBlock]
        }
        let envelope = try JSONDecoder().decode(AnthropicEnvelope.self, from: data)
        guard let text = envelope.content.first?.text else { throw APIError.noData }

        // The text is itself a JSON object
        guard let jsonData = text.data(using: .utf8) else { throw APIError.noData }
        do {
            return try JSONDecoder().decode(ClaudeResponse.self, from: jsonData)
        } catch {
            // Fallback: treat raw text as response
            return ClaudeResponse(correction: nil, response: text, trouble_words: nil)
        }
    }

    // MARK: TTS

    func speak(text: String, voice: String, language: String, speakingRate: Double = 1.0) async throws -> Data {
        if voice.hasPrefix("google-") {
            return try await speakGoogle(text: text, voice: voice, speakingRate: speakingRate)
        } else {
            return try await speakOpenAI(text: text, voice: voice, language: language)
        }
    }

    private func speakGoogle(text: String, voice: String, speakingRate: Double) async throws -> Data {
        // voice key format: "google-fr-a" → languageCode "fr-FR", name "fr-FR-Neural2-A"
        let parts = voice.split(separator: "-") // ["google", "fr", "a"]
        guard parts.count == 3 else { throw APIError.noData }
        let lang = String(parts[1]).lowercased()          // "fr"
        let letter = String(parts[2]).uppercased()        // "A"
        let bcp47 = "\(lang)-\(lang.uppercased())"        // "fr-FR"
        let voiceName = "\(bcp47)-Neural2-\(letter)"      // "fr-FR-Neural2-A"

        let apiKey = Config.googleTTSKey
        let urlStr = "https://texttospeech.googleapis.com/v1/text:synthesize?key=\(apiKey)"
        let url = URL(string: urlStr)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "input": ["text": text],
            "voice": ["languageCode": bcp47, "name": voiceName],
            "audioConfig": ["audioEncoding": "MP3", "speakingRate": speakingRate]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw APIError.httpError(http.statusCode)
        }

        struct GoogleTTSResponse: Codable { let audioContent: String }
        let decoded = try JSONDecoder().decode(GoogleTTSResponse.self, from: data)
        guard let mp3 = Data(base64Encoded: decoded.audioContent) else { throw APIError.noData }
        return mp3
    }

    private func speakOpenAI(text: String, voice: String, language: String) async throws -> Data {
        let url = URL(string: "https://api.openai.com/v1/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Config.openAIKey)", forHTTPHeaderField: "Authorization")

        let instructions = """
        You are a native \(language) speaker who learned English as a second language. \
        Your \(language) accent is always present — it never disappears, not even on a single word. \
        Every English word you say carries the full rhythm, intonation, and phonology of a native \(language) speaker. \
        You cannot turn your accent off.
        """

        let payload: [String: Any] = [
            "model": Config.ttsModel,
            "voice": voice,
            "input": text,
            "instructions": instructions
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw APIError.httpError(http.statusCode)
        }
        return data
    }

    // MARK: Fetch article

    func fetchArticle(urlString: String) async throws -> FetchedArticle {
        let url = URL(string: "\(Config.serverBase)/api/fetch-article")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.appendFormField(name: "url", value: urlString, boundary: boundary)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw APIError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(FetchedArticle.self, from: data)
    }

    // MARK: Fetch feed

    func fetchFeed(urlString: String) async throws -> FetchedFeed {
        let url = URL(string: "\(Config.serverBase)/api/fetch-feed")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.appendFormField(name: "url", value: urlString, boundary: boundary)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw APIError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(FetchedFeed.self, from: data)
    }
}

// MARK: - Data helpers

private extension Data {
    mutating func appendFormField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendFileField(name: String, filename: String, mimeType: String, data fileData: Data, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(fileData)
        append("\r\n".data(using: .utf8)!)
    }
}
