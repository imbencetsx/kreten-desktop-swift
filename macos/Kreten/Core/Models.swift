import Foundation

struct Account: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var institutionCode: String
    var institutionName: String
    var username: String
}

struct AppNotification: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var kind: String
    var title: String
    var body: String
    var createdAt: Date
    var accountID: String
}

struct Tokens: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

struct AccountCache: Codable, Sendable {
    var data: [String: JSON] = [:]
    var lastSyncedAt: Date?
    var errors: [String: String] = [:]
    var completedHomework: Set<String> = []
    var fingerprints: [String: [String: String]] = [:]
    var messageDetails: [String: JSON] = [:]
    var timetableRange: ClosedRange<String>?
}

struct StoredAccount: Codable, Sendable {
    var account: Account
    var tokens: Tokens
    var cache = AccountCache()
}

/// Everything persisted in the encrypted store. Tokens never leave the core actor.
struct StoreState: Codable, Sendable {
    var accounts: [StoredAccount] = []
    var activeAccountID: String?
    var notifications: [AppNotification] = []
}

/// The read-only projection the UI renders.
struct Snapshot: Sendable {
    var accounts: [Account] = []
    var activeAccountID: String?
    var data: [String: JSON] = [:]
    var lastSyncedAt: Date?
    var offline = true
    var errors: [String: String] = [:]
    var notifications: [AppNotification] = []
    var completedHomework: Set<String> = []

    var activeAccount: Account? { accounts.first { $0.id == activeAccountID } }
    subscript(key: String) -> JSON { data[key] ?? .null }
}

struct BankAccountUpdate: Sendable {
    var accountNumber: String
    var ownerName: String
    var ownerTypeID: Int
    var bankName: String
}

enum NotificationCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case grades, homework, tests, absences, timetable, notes, notices, messagesInbox
    var id: String { rawValue }
    var label: String {
        switch self {
        case .grades: "Jegyek"
        case .homework: "Házi feladatok"
        case .tests: "Dolgozatok"
        case .absences: "Hiányzások"
        case .timetable: "Órarendváltozás"
        case .notes: "Feljegyzések"
        case .notices: "Faliújság"
        case .messagesInbox: "Üzenetek"
        }
    }
    var title: String {
        switch self {
        case .grades: "Új vagy módosult értékelés"
        case .homework: "Házi feladat frissült"
        case .tests: "Bejelentett dolgozat frissült"
        case .absences: "Mulasztás frissült"
        case .notes, .notices: "Új iskolai közlemény"
        case .messagesInbox: "Új üzenet"
        case .timetable: "Órarendváltozás"
        }
    }
}

/// Sync-time preferences the core needs to decide which changes notify.
struct SyncPreferences: Sendable {
    var categories: Set<NotificationCategory>
    var mutedSubjects: Set<String>
    var privateGrades: Bool
}
