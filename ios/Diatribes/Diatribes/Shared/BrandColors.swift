import SwiftUI
import UIKit

extension Color {
    static let brandSand        = Color(red: 191/255, green: 180/255, blue: 143/255) // #BFB48F
    static let brandParchment   = Color(red: 242/255, green: 239/255, blue: 233/255) // #F2EFE9
    static let brandCarbonBlack = Color(red:  37/255, green:  38/255, blue:  39/255) // #252627
    static let brandNoun        = Color(red:  86/255, green:  78/255, blue:  88/255) // #564E58
    static let brandVerb        = Color(red: 144/255, green:  78/255, blue:  85/255) // #904E55
    static let brandAdj         = Color(red: 0.761,   green: 0.255,   blue: 0.047)   // #C2410C
    static let brandAdv         = Color(red: 0.486,   green: 0.231,   blue: 0.929)   // #7C3AED
}

func posColor(_ pos: String) -> Color {
    switch pos {
    case "noun": return .brandNoun
    case "verb": return .brandVerb
    case "adj":  return .brandAdj
    case "adv":  return .brandAdv
    default:     return .secondary
    }
}

func posLabel(_ pos: String) -> String {
    switch pos {
    case "noun": return "Noun"
    case "verb": return "Verb"
    case "adj":  return "Adjective"
    case "adv":  return "Adverb"
    default:     return pos
    }
}

func posUIColor(_ pos: String) -> UIColor {
    switch pos {
    case "noun": return UIColor(red: 86/255,  green: 78/255,  blue: 88/255,  alpha: 1)
    case "verb": return UIColor(red: 144/255, green: 78/255,  blue: 85/255,  alpha: 1)
    case "adj":  return UIColor(red: 0.761,   green: 0.255,   blue: 0.047,   alpha: 1)
    case "adv":  return UIColor(red: 0.486,   green: 0.231,   blue: 0.929,   alpha: 1)
    default:     return .secondaryLabel
    }
}
