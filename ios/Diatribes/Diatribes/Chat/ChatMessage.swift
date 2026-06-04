import Foundation
import UIKit

enum MessageRole: String, Codable {
    case user
    case assistant
    case correction
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    /// Plain text content (stored in history sent to Claude)
    let text: String
    /// Optional attributed text for display (POS-colored words)
    let attributed: NSAttributedString?

    init(role: MessageRole, text: String, attributed: NSAttributedString? = nil) {
        self.role = role
        self.text = text
        self.attributed = attributed
    }
}

/// Wire format for Claude's conversation history
struct HistoryMessage: Codable {
    let role: String
    let content: String
}
