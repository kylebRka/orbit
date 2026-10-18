import Foundation

func L(_ english: String, _ russian: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("ru") == true ? russian : english
}
