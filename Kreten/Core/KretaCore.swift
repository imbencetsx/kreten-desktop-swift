// Local-only KRÉTA mobile sessions, encrypted cache, and change notifications.
// Protocol adapted from Firka (QwIT Development) and KRETEN (micr0softstore).
import Foundation

/// Owns tokens, the encrypted store and all KRÉTA traffic. The actor serializes
/// token rotation and persistence; the UI only ever sees `Snapshot`s.
actor KretaCore {
    private let store: SecureStore
    var state: StoreState
    let api = KretaAPI()
    private var pending: PendingLogin?
    var offline = true
    private var tokenRefreshes: [String: Task<String, Error>] = [:]

    init() throws {
        store = try SecureStore()
        state = try store.read()
    }

    // MARK: Snapshot

    func snapshot() -> Snapshot {
        let cache = selected?.cache
        return Snapshot(
            accounts: state.accounts.map(\.account),
            activeAccountID: state.activeAccountID,
            data: cache?.data ?? [:],
            lastSyncedAt: cache?.lastSyncedAt,
            offline: offline,
            errors: cache?.errors ?? [:],
            notifications: state.notifications,
            completedHomework: cache?.completedHomework ?? []
        )
    }

    private var selected: StoredAccount? { state.accounts.first { $0.account.id == state.activeAccountID } }
    func index(of id: String) throws -> Int {
        guard let i = state.accounts.firstIndex(where: { $0.account.id == id }) else { throw KretaError.noAccount }
        return i
    }
    private func selectedIndex() throws -> Int { try index(of: state.activeAccountID ?? "") }
    func save() throws { try store.write(state) }

    // MARK: Login

    func beginLogin() throws -> (id: String, url: URL) {
        let p = try PendingLogin()
        pending = p
        return (p.id, p.url)
    }

    func cancelLogin(_ id: String? = nil) {
        if id == nil || pending?.id == id { pending = nil }
    }

    func completeLogin(attempt: String, redirect: URL) async throws -> Snapshot {
        guard let p = pending, p.id == attempt else { throw KretaError.login }
        pending = nil
        let code = try p.code(from: redirect)
        let token = try await api.token([
            ("code", code), ("code_verifier", p.verifier), ("redirect_uri", OAuth.redirectURI),
            ("client_id", OAuth.clientID), ("grant_type", "authorization_code"),
        ])
        let claims = try OAuth.claims(token["id_token"].text)
        guard claims["nonce"].text == p.nonce else { throw KretaError.login }
        let aud = claims["aud"]
        if !aud.isNull, aud.text != OAuth.clientID, !(aud.array ?? []).contains(where: { $0.text == OAuth.clientID }) {
            throw KretaError.login
        }
        func claim(_ k: String) throws -> String {
            let v = claims[k].text
            guard !v.isEmpty else { throw KretaError.response }
            return v
        }
        let institution = try OAuth.validateInstitution(try claim("kreta:institute_code"))
        let username = try claim("kreta:user_name")
        let userID = try claim("kreta:institute_user_id")
        let studentID = claims["kreta:student_id"].isNull ? userID : claims["kreta:student_id"].text
        let id = Data("\(institution)\0\(userID)\0\(studentID)".utf8).sha256Hex
        let tokens = try Self.tokens(from: token, old: nil)
        if let i = state.accounts.firstIndex(where: { $0.account.id == id }) {
            state.accounts[i].tokens = tokens
        } else {
            let name = claims["name"].text
            state.accounts.append(StoredAccount(
                account: Account(id: id, name: name.isEmpty ? username : name, institutionCode: institution,
                                 institutionName: institution, username: username),
                tokens: tokens))
        }
        state.activeAccountID = id
        try save()
        return snapshot()
    }

    func selectAccount(_ id: String) throws -> Snapshot {
        _ = try index(of: id)
        state.activeAccountID = id
        offline = true
        try save()
        return snapshot()
    }

    func logout(_ id: String) throws -> Snapshot {
        state.accounts.removeAll { $0.account.id == id }
        state.notifications.removeAll { $0.accountID == id }
        if state.activeAccountID == id { state.activeAccountID = state.accounts.first?.account.id }
        try save()
        return snapshot()
    }

    func setHomework(_ id: String, complete: Bool) throws -> Snapshot {
        guard !id.isEmpty, id.count <= 256 else { throw KretaError.invalid("házi feladat") }
        let i = try selectedIndex()
        if complete { state.accounts[i].cache.completedHomework.insert(id) }
        else { state.accounts[i].cache.completedHomework.remove(id) }
        try save()
        return snapshot()
    }

    func dismissNotification(_ id: String?) throws -> Snapshot {
        if let id { state.notifications.removeAll { $0.id == id } } else { state.notifications.removeAll() }
        try save()
        return snapshot()
    }

    // MARK: Tokens

    private static func tokens(from v: JSON, old: Tokens?) throws -> Tokens {
        let access = v["access_token"].text
        let refresh = v["refresh_token"].text.isEmpty ? (old?.refreshToken ?? "") : v["refresh_token"].text
        guard !access.isEmpty, !refresh.isEmpty, let expires = v["expires_in"].number,
              (1...(7 * 24 * 3600)).contains(expires) else { throw KretaError.response }
        return Tokens(accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval(expires))
    }

    func ensureToken(_ accountID: String, force: Bool = false) async throws -> String {
        // Refresh tokens rotate: two overlapping refreshes would burn one and log the user out.
        if let inFlight = tokenRefreshes[accountID] { return try await inFlight.value }
        let i = try index(of: accountID)
        let old = state.accounts[i].tokens
        if !force, old.expiresAt > Date().addingTimeInterval(60) { return old.accessToken }
        let institution = state.accounts[i].account.institutionCode
        let api = self.api
        let task = Task<String, Error> {
            let token = try await api.token([
                ("institute_code", institution), ("refresh_token", old.refreshToken),
                ("grant_type", "refresh_token"), ("client_id", OAuth.clientID),
            ])
            return try self.storeRefreshed(token, old: old, accountID: accountID)
        }
        tokenRefreshes[accountID] = task
        defer { tokenRefreshes[accountID] = nil }
        return try await task.value
    }

    private func storeRefreshed(_ token: JSON, old: Tokens, accountID: String) throws -> String {
        let fresh = try Self.tokens(from: token, old: old)
        state.accounts[try index(of: accountID)].tokens = fresh
        // Rotated refresh tokens must reach disk before any API call can fail.
        try save()
        return fresh.accessToken
    }

    private func getSelected(_ path: String, admin: Bool = false) async throws -> JSON {
        guard let account = selected else { throw KretaError.noAccount }
        let url = admin ? api.adminURL(path) : api.schoolURL(account.account.institutionCode, path)
        let token = try await ensureToken(account.account.id)
        do { return try await api.get(url, token: token) } catch KretaError.authentication {
            return try await api.get(url, token: try await ensureToken(account.account.id, force: true))
        }
    }

    private func changeSelected(_ method: String, _ path: String, body: [String: Any]?, form: Bool = false) async throws {
        guard let account = selected else { throw KretaError.noAccount }
        let url = api.schoolURL(account.account.institutionCode, path)
        let token = try await ensureToken(account.account.id)
        do { try await api.change(method, url, token: token, body: body, form: form) } catch KretaError.authentication {
            try await api.change(method, url, token: try await ensureToken(account.account.id, force: true), body: body, form: form)
        }
    }

    // MARK: On-demand reads & mutations

    func timetable(from: String, to: String) async throws -> JSON {
        guard let a = Day.date(from), let b = Day.date(to),
              (0...42).contains(Calendar.budapest.dateComponents([.day], from: a, to: b).day ?? -1)
        else { throw KretaError.invalid("dátumtartomány") }
        return try await getSelected("/ellenorzo/v3/sajat/OrarendElemek?datumTol=\(from)&datumIg=\(to)")
    }

    func messageDetail(_ id: String) async throws -> JSON {
        let id = try KretaAPI.validID(id)
        do {
            let value = try await getSelected("/api/v1/kommunikacio/postaladaelemek/\(id)", admin: true)
            let i = try selectedIndex()
            state.accounts[i].cache.messageDetails[id] = value
            try save()
            return value
        } catch KretaError.network {
            if let cached = selected?.cache.messageDetails[id] { return cached }
            throw KretaError.network
        }
    }

    func consultingHour(_ id: String) async throws -> JSON {
        try await getSelected("/ellenorzo/v3/sajat/Fogadoorak/\(try KretaAPI.validID(id))")
    }

    func lepPermission(eventID: String, permitted: Bool) async throws {
        _ = try KretaAPI.validID(eventID)
        try await changeSelected("POST", "/ellenorzo/v3/Lep/Eloadasok/GondviseloEngedelyezes",
                                 body: ["eventId": eventID, "isPermitted": permitted ? "true" : "false"])
    }

    func updateContact(email: String, phone: String) async throws {
        guard email.count <= 254, phone.count <= 64 else { throw KretaError.invalid("elérhetőség") }
        try await changeSelected("POST", "/ellenorzo/v3/sajat/Elerhetoseg", body: ["email": email, "telefonszam": phone], form: true)
    }

    func updateBank(_ bank: BankAccountUpdate) async throws {
        let fields = [bank.accountNumber, bank.ownerName, bank.bankName].map { $0.trimmingCharacters(in: .whitespaces) }
        guard !fields.contains(where: \.isEmpty), bank.accountNumber.count <= 64, bank.ownerName.count <= 200, bank.bankName.count <= 200
        else { throw KretaError.invalid("bankszámla") }
        try await checkBankAccess()
        try await changeSelected("POST", "/ellenorzo/v3/sajat/Bankszamla", body: [
            "BankszamlaSzam": bank.accountNumber, "BankszamlaTulajdonosNeve": bank.ownerName,
            "BankszamlaTulajdonosTipusId": bank.ownerTypeID, "SzamlavezetoBank": bank.bankName,
        ])
    }

    func deleteBank() async throws {
        try await checkBankAccess()
        try await changeSelected("DELETE", "/ellenorzo/v3/sajat/Bankszamla", body: nil)
    }

    private func checkBankAccess() async throws {
        let student = try await getSelected("/ellenorzo/v3/sajat/TanuloAdatlap")
        if student["Bankszamla"]["IsReadOnly"].bool == true { throw KretaError.http(403) }
    }
}

extension String {
    /// Case- and accent-insensitive key ("ÁRVÍZTŰRŐ" → "arvizturo").
    var searchKey: String { folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "hu_HU")) }
}
