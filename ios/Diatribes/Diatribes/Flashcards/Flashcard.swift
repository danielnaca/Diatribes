import Foundation
import SwiftData

@Model
final class Flashcard {
    var id: UUID
    var english: String
    var translation: String
    var pos: String          // "noun" | "verb" | "adj" | "adv"
    var language: String     // "French" | "Spanish"
    var createdAt: Date
    var dueAt: Date
    var interval: Int        // days until next review
    var easeFactor: Double   // SM-2 ease factor

    init(english: String, translation: String, pos: String, language: String) {
        self.id          = UUID()
        self.english     = english
        self.translation = translation
        self.pos         = pos
        self.language    = language
        self.createdAt   = Date()
        self.dueAt       = Date()
        self.interval    = 1
        self.easeFactor  = 2.5
    }

    // SM-2 simplified: Hard keeps same interval, Easy multiplies by ease factor
    func reviewedHard() {
        dueAt = Calendar.current.date(byAdding: .day, value: interval, to: Date()) ?? Date()
    }

    func reviewedEasy() {
        interval = max(1, Int(Double(interval) * easeFactor))
        easeFactor = min(3.0, easeFactor + 0.1)
        dueAt = Calendar.current.date(byAdding: .day, value: interval, to: Date()) ?? Date()
    }
}
