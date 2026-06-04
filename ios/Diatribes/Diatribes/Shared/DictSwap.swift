import Foundation
import NaturalLanguage
import UIKit

// MARK: - Types

struct SwapResult {
    let attributed: NSAttributedString  // colored display text (UITextView)
    let plain: String                   // for TTS (no markup)
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
    /// density (0–1): fraction of eligible words actually swapped.
    func swap(text: String, langCode: String, enabledPOS: Set<String>, highlightsOn: Bool = true, density: Double = 1.0) -> SwapResult {
        load()

        let lemmaMap = buildLemmaMap(text: text)
        let result   = NSMutableAttributedString()
        var plainParts: [String] = []

        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = 6
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .paragraphStyle: paraStyle,
            .foregroundColor: UIColor.label
        ]

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var lastEnd = text.startIndex

        tagger.enumerateTags(in: text.startIndex ..< text.endIndex,
                             unit: .word,
                             scheme: .lexicalClass,
                             options: [.omitWhitespace]) { _, tokenRange in

            if lastEnd < tokenRange.lowerBound {
                let gap = String(text[lastEnd ..< tokenRange.lowerBound])
                result.append(NSAttributedString(string: gap, attributes: baseAttrs))
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
                    var attrs = baseAttrs
                    if let url = tapURL { attrs[.link] = url }
                    if highlightsOn {
                        attrs[.foregroundColor] = posUIColor(entry.pos)
                        attrs[.underlineStyle]  = NSUnderlineStyle.single.rawValue
                        attrs[.underlineColor]  = posUIColor(entry.pos)
                    }
                    result.append(NSAttributedString(string: translation, attributes: attrs))
                    plainParts.append(translation)
                } else {
                    result.append(NSAttributedString(string: word, attributes: baseAttrs))
                    plainParts.append(word)
                }
            } else {
                result.append(NSAttributedString(string: word, attributes: baseAttrs))
                plainParts.append(word)
            }
            return true
        }

        if lastEnd < text.endIndex {
            let tail = String(text[lastEnd...])
            result.append(NSAttributedString(string: tail, attributes: baseAttrs))
            plainParts.append(tail)
        }

        return SwapResult(attributed: result, plain: plainParts.joined())
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
