import Foundation

enum KretaError: LocalizedError, Equatable, Sendable {
    case noAccount
    case authentication
    case login
    case institution
    case invalid(String)
    case network
    case http(Int)
    case response
    case storage
    case keychain

    var errorDescription: String? {
        switch self {
        case .noAccount: "Nincs bejelentkezett fiók."
        case .authentication: "A munkamenet lejárt. Jelentkezz be újra."
        case .login: "Érvénytelen vagy lejárt bejelentkezési kérés."
        case .institution: "Érvénytelen intézménykód."
        case .invalid(let what): "Érvénytelen kérés: \(what)"
        case .network: "A KRÉTA szolgáltatása jelenleg nem érhető el."
        case .http(let code): "A KRÉTA elutasította a kérést (HTTP \(code))."
        case .response: "A KRÉTA válasza nem feldolgozható."
        case .storage: "A helyi adatok nem olvashatók vagy írhatók."
        case .keychain: "A titkosító kulcs nem érhető el a kulcskarikában."
        }
    }
}
