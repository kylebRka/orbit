import Foundation

enum AppLanguage:String, CaseIterable, Identifiable {
    case system, english = "en", russian = "ru"
    var id:String { rawValue }
    static var current:Self { Self(rawValue:UserDefaults.standard.string(forKey:"orbitLanguage") ?? "system") ?? .system }
    var isRussian:Bool { self == .russian || (self == .system && Locale.preferredLanguages.first?.hasPrefix("ru") == true) }
    var locale:Locale { self == .system ? .autoupdatingCurrent : Locale(identifier:rawValue) }
}

func L(_ english:String, _ russian:String) -> String {
    AppLanguage.current.isRussian ? russian : english
}
