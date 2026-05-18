import Foundation
import NaturalLanguage
import SwiftUI

// MARK: - Types

struct SwapResult {
    let attributed: AttributedString   // colored display text
    let plain: String                  // for TTS (no markup)
}

// MARK: - DictSwap

final class DictSwap {
    static let shared = DictSwap()

    private var dict: [String: DictEntry] = [:]
    private var isLoaded = false

    private init() {}

    // MARK: Load

    func load() {
        guard !isLoaded else { return }
        guard let url = Bundle.main.url(forResource: "en_es_fr", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: DictEntry].self, from: data)
        else {
            print("DictSwap: failed to load en_es_fr.json")
            return
        }
        dict = decoded
        isLoaded = true
    }

    // MARK: Swap

    /// Swap English words with target-language translations, color-coded by POS.
    /// density (0–1): fraction of eligible words actually swapped. All recognised
    /// dictionary words are still tappable regardless of density/POS filter.
    func swap(text: String, langCode: String, enabledPOS: Set<String>, highlightsOn: Bool = true, density: Double = 1.0) -> SwapResult {
        load()

        let lemmaMap = buildLemmaMap(text: text)

        var attributed = AttributedString()
        var plainParts: [String] = []

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        var lastEnd = text.startIndex

        tagger.enumerateTags(in: text.startIndex ..< text.endIndex,
                             unit: .word,
                             scheme: .lexicalClass,
                             options: [.omitWhitespace]) { _, tokenRange in

            if lastEnd < tokenRange.lowerBound {
                let gap = String(text[lastEnd ..< tokenRange.lowerBound])
                attributed += AttributedString(gap)
                plainParts.append(gap)
            }
            lastEnd = tokenRange.upperBound

            let word  = String(text[tokenRange])
            let lower = word.lowercased()
            let lemma = lemmaMap[tokenRange.lowerBound] ?? lower
            let base  = dict[lemma] != nil ? lemma : (dict[lower] != nil ? lower : nil)

            if let base,
               let entry = dict[base],
               let translation = entry.translation(for: langCode) {

                let enEnc = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word
                let trEnc = translation.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? translation
                let tapURL = URL(string: "diatribes://word?en=\(enEnc)&tr=\(trEnc)&pos=\(entry.pos)&lang=\(langCode)")

                let shouldSwap = enabledPOS.contains(entry.pos) && Double.random(in: 0...1) < density

                if shouldSwap {
                    var tAttr = AttributedString(translation)
                    if highlightsOn {
                        tAttr.foregroundColor = colorForPOS(entry.pos)
                        tAttr.font = .body.bold()
                    }
                    if let url = tapURL { tAttr.link = url }
                    attributed += tAttr
                    plainParts.append(translation)
                } else {
                    // Keep English text — but still tappable (link, no colour change)
                    var wAttr = AttributedString(word)
                    if let url = tapURL { wAttr.link = url }
                    attributed += wAttr
                    plainParts.append(word)
                }
            } else {
                attributed += AttributedString(word)
                plainParts.append(word)
            }

            return true
        }

        // Remaining tail (if any)
        if lastEnd < text.endIndex {
            let tail = String(text[lastEnd...])
            attributed += AttributedString(tail)
            plainParts.append(tail)
        }

        return SwapResult(
            attributed: attributed,
            plain: plainParts.joined()
        )
    }

    // MARK: - Lemma pass

    private func buildLemmaMap(text: String) -> [String.Index: String] {
        var map: [String.Index: String] = [:]
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        tagger.enumerateTags(in: text.startIndex ..< text.endIndex,
                             unit: .word,
                             scheme: .lemma,
                             options: [.omitWhitespace]) { tag, tokenRange in
            if let lemma = tag?.rawValue, !lemma.isEmpty {
                map[tokenRange.lowerBound] = lemma.lowercased()
            }
            return true
        }
        return map
    }

    // MARK: Helpers

    private func colorForPOS(_ pos: String) -> Color {
        switch pos {
        case "noun": return Color(red: 0.145, green: 0.388, blue: 0.922)   // #2563eb
        case "verb": return Color(red: 0.086, green: 0.639, blue: 0.239)   // #16a34a
        case "adj":  return Color(red: 0.761, green: 0.255, blue: 0.047)   // #c2410c
        case "adv":  return Color(red: 0.486, green: 0.231, blue: 0.929)   // #7c3aed
        default:     return .primary
        }
    }
}

// MARK: - DictEntry

struct DictEntry: Codable {
    let pos: String
    let es: String?
    let fr: String?

    func translation(for langCode: String) -> String? {
        switch langCode {
        case "es": return es
        case "fr": return fr
        default:   return nil
        }
    }
}
