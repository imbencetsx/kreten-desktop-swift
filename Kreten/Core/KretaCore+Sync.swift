import Foundation

private let prefix = "/ellenorzo/v3/sajat"

extension KretaCore {
    struct RefreshOutcome: Sendable {
        var snapshot: Snapshot
        var notifications: [AppNotification]
    }

    /// Polls every saved account without changing the selected account.
    func refreshAll(_ prefs: SyncPreferences) async -> RefreshOutcome {
        var notifications: [AppNotification] = []
        for id in state.accounts.map(\.account.id) {
            notifications += (try? await refreshAccount(id, prefs)) ?? []
        }
        return RefreshOutcome(snapshot: snapshot(), notifications: notifications)
    }

    private func refreshAccount(_ id: String, _ prefs: SyncPreferences) async throws -> [AppNotification] {
        let isSelected = state.activeAccountID == id
        let token: String
        do {
            token = try await ensureToken(id)
        } catch {
            let i = try index(of: id)
            state.accounts[i].cache.errors["connection"] = error.localizedDescription
            if isSelected { offline = true }
            try save()
            return []
        }
        let institution = state.accounts[try index(of: id)].account.institutionCode
        let plan = Self.requests(institution: institution, api: api)
        let api = self.api

        var results: [String: Result<JSON, KretaError>] = await withTaskGroup(of: (String, Result<JSON, KretaError>).self) { group in
            var out: [String: Result<JSON, KretaError>] = [:]
            var pendingRequests = plan.requests[...]
            func next() -> Bool {
                guard let (key, url) = pendingRequests.popFirst() else { return false }
                group.addTask { (key, await Self.fetch(api, url, token)) }
                return true
            }
            for _ in 0..<4 { _ = next() } // at most four requests in flight
            while let (key, result) = await group.next() {
                out[key] = result
                _ = next()
            }
            return out
        }

        if results.values.contains(where: { if case .failure(.authentication) = $0 { true } else { false } }),
           let fresh = try? await ensureToken(id, force: true) {
            for (key, url) in plan.requests {
                if case .failure(.authentication) = results[key] { results[key] = await Self.fetch(api, url, fresh) }
            }
        }

        // Class averages need the groups' study-task UIDs, so they run after the batch.
        if case .success(let groups) = results["groups"] {
            let visible = classAveragesVisible(["student", "capabilities"].compactMap { try? results[$0]?.get() })
            if let r = await fetchClassAverages(id, institution: institution, groups: groups, visible: visible) {
                results["classAverages"] = r
            }
        }

        // Merge the school-year query with the bounded chunks, de-duplicated by ID.
        var homework: [JSON] = []
        var homeworkFailure: KretaError?
        for key in results.keys.filter({ $0.hasPrefix("homework") }).sorted() {
            switch results.removeValue(forKey: key)! {
            case .success(.array(let items)): homework += items
            case .success: homeworkFailure = homeworkFailure ?? .response
            case .failure(let e): homeworkFailure = homeworkFailure ?? e
            }
        }
        var seen = Set<String>()
        homework = homework.filter { $0.itemID.map { seen.insert($0).inserted } ?? true }
        results["homework"] = !homework.isEmpty || homeworkFailure == nil ? .success(.array(homework)) : .failure(homeworkFailure!)

        let i = try index(of: id)
        var account = state.accounts[i]
        var notifications: [AppNotification] = []
        var success = 0
        account.cache.errors.removeAll()
        for (key, result) in results.sorted(by: { $0.key < $1.key }) {
            switch result.flatMap({ v in Result { try validateBucket(key, v) }.mapError { $0 as? KretaError ?? .response } }) {
            case .success(let value):
                success += 1
                if let n = diff(cache: &account.cache, key: key, value: value, accountID: id, accountName: account.account.name,
                                prefs: prefs, range: key == "timetable" ? plan.range : nil) {
                    notifications.append(n)
                }
                if key == "student" {
                    if !value["Nev"].text.isEmpty { account.account.name = value["Nev"].text }
                    let school = value["IntezmenyNev"].isNull ? value["Intezmeny"]["TeljesNev"].text : value["IntezmenyNev"].text
                    if !school.isEmpty { account.account.institutionName = school }
                }
                account.cache.data[key] = value
            case .failure(.http(403)) where key == "consultations" || key == "guardian":
                // Guardian-only endpoints answer 403 for student accounts; that is expected.
                account.cache.data[key] = key == "consultations" ? .array([]) : .null
            case .failure(let error):
                account.cache.errors[key] = error.localizedDescription
            }
        }
        if success > 0 { account.cache.lastSyncedAt = Date() }
        let j = try index(of: id)
        state.accounts[j] = account
        if state.activeAccountID == id { offline = success == 0 }
        state.notifications.insert(contentsOf: notifications, at: 0)
        state.notifications = Array(state.notifications.prefix(100))
        try save()
        return notifications
    }

    private static func fetch(_ api: KretaAPI, _ url: String, _ token: String) async -> Result<JSON, KretaError> {
        do { return .success(try await api.get(url, token: token)) }
        catch { return .failure(error as? KretaError ?? .network) }
    }

    /// `nil` when KRÉTA refuses every query form: keep the old cache, show no error.
    private func fetchClassAverages(_ id: String, institution: String, groups: JSON, visible: Bool?) async -> Result<JSON, KretaError>? {
        if visible == false { return .success(.array([])) }
        let uids = studyTaskUIDs(groups)
        if uids.isEmpty { return .success(.array([])) }
        let base = api.schoolURL(institution, "\(prefix)/Ertekelesek/Atlagok/OsztalyAtlagok")
        var rows: [JSON] = []
        var anySuccess = false
        var hardFailure: KretaError?
        outer: for uid in uids {
            for url in classAverageURLs(base: base, uid: uid) {
                guard let i = try? index(of: id) else { return nil }
                switch await Self.fetch(api, url, state.accounts[i].tokens.accessToken) {
                case .success(.array(let items)):
                    anySuccess = true
                    rows += items
                    continue outer
                case .success, .failure(.http), .failure(.response):
                    continue // wrong query form: try the next one
                case .failure(let e):
                    hardFailure = e
                    break outer
                }
            }
        }
        if anySuccess {
            var seen = Set<String>()
            rows = rows.filter { r in
                let k = r["Tantargy"]["Uid"].isNull ? r["Uid"] : r["Tantargy"]["Uid"]
                return k.isNull || seen.insert(k.text).inserted
            }
            return .success(.array(rows))
        }
        return hardFailure.map { .failure($0) }
    }

    fileprivate static func requests(institution: String, api: KretaAPI) -> (requests: [(String, String)], range: ClosedRange<String>) {
        let today = Day.today
        let monday = Day.monday(of: today)
        let ttFrom = Day.add(monday, -7), ttTo = Day.add(monday, 20)
        let schoolStart = "\(Day.schoolYear(of: today))-09-01"
        var r: [(String, String)] = []
        for (key, route) in [("student", "TanuloAdatlap"), ("grades", "Ertekelesek"), ("absences", "Mulasztasok"),
                             ("groups", "OsztalyCsoportok"), ("schoolYear", "Intezmenyek/TanevRendjeElemek"),
                             ("consultations", "Fogadoorak"), ("guardian", "GondviseloAdatlap"), ("capabilities", "Intezmenyek")] {
            r.append((key, api.schoolURL(institution, "\(prefix)/\(route)")))
        }
        r.append(("notices", api.schoolURL(institution, "\(prefix)/FaliujsagElemek?datumTol=\(schoolStart)")))
        r.append(("notes", api.schoolURL(institution, "\(prefix)/Feljegyzesek?datumTol=\(schoolStart)")))
        r.append(("timetable", api.schoolURL(institution, "\(prefix)/OrarendElemek?datumTol=\(ttFrom)&datumIg=\(ttTo)")))
        r.append(("tests", api.schoolURL(institution, "\(prefix)/BejelentettSzamonkeresek?datumTol=\(schoolStart)")))
        r.append(("lep", api.schoolURL(institution, "/ellenorzo/v3/Lep/Eloadasok")))
        r.append(("dktSubjects", api.schoolURL(institution, "/dktapi/intezmenyek/munkaterek/tanulok")))
        for (key, folder) in [("messagesInbox", "beerkezett"), ("messagesSent", "elkuldott"), ("messagesDeleted", "torolt")] {
            r.append((key, api.adminURL("/api/v1/kommunikacio/postaladaelemek/\(folder)")))
        }
        // Full school-year homework, plus ≤21-day chunks for instances that require a bounded window.
        r.append(("homeworkSchoolYear", api.schoolURL(institution, "\(prefix)/HaziFeladatok?datumTol=\(schoolStart)")))
        var from = Day.add(today, -30)
        let end = Day.add(today, 30)
        var chunk = 0
        while from <= end {
            let to = min(Day.add(from, 21), end)
            r.append(("homeworkChunk\(chunk)", api.schoolURL(institution, "\(prefix)/HaziFeladatok?datumTol=\(from)&datumIg=\(to)")))
            if to == end { break }
            from = to
            chunk += 1
        }
        return (r, ttFrom...ttTo)
    }
}


/// Validates the shape KRÉTA returned for a bucket.
func validateBucket(_ key: String, _ value: JSON) throws -> JSON {
    let object = ["student", "guardian", "capabilities"].contains(key)
    if object ? value.isObject : (value.array?.allSatisfy(\.isObject) ?? false) { return value }
    throw KretaError.response
}

/// `IsOsztalyAtlagMegjeleniteseEllenorzoben` from the student profile or institution.
func classAveragesVisible(_ sources: [JSON]) -> Bool? {
    for v in sources {
        if let b = v["Intezmeny"]["TestreszabasBeallitasok"]["IsOsztalyAtlagMegjeleniteseEllenorzoben"].bool
            ?? v["TestreszabasBeallitasok"]["IsOsztalyAtlagMegjeleniteseEllenorzoben"].bool { return b }
    }
    return nil
}

/// Unique study-task UIDs, the student's active class first.
func studyTaskUIDs(_ groups: JSON) -> [String] {
    func rank(_ g: JSON) -> Int { (g["IsAktiv"].bool == false ? 2 : 0) + (g["Tipus"].text != "Osztaly" ? 1 : 0) }
    var seen = Set<String>()
    return groups.rows.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
        .map { $0.element["OktatasNevelesiFeladat"]["Uid"].text }
        .filter { !$0.isEmpty && seen.insert($0).inserted }
}

/// Firka sends the UID truncated at the first comma (twice); older clients send it whole.
func classAverageURLs(base: String, uid: String) -> [String] {
    let short = String(uid.split(separator: ",", omittingEmptySubsequences: false).first ?? "")
    var forms: [[String]] = []
    if !short.isEmpty { forms += [[short], [short, short]] }
    if uid != short { forms.append([uid]) }
    return forms.compactMap { values in
        var c = URLComponents(string: base)
        c?.queryItems = values.map { URLQueryItem(name: "oktatasiNevelesiFeladatUid", value: $0) }
        return c?.url?.absoluteString
    }
}

func lessonDay(_ row: JSON) -> String? {
    let s = row["KezdetIdopont", "Datum"].text
    return s.count >= 10 ? String(s.prefix(10)) : nil
}

/// Updates the per-bucket change baseline and returns a notification when the
/// user should hear about it. The first sync is always silent.
func diff(cache: inout AccountCache, key: String, value: JSON, accountID: String, accountName: String,
          prefs: SyncPreferences, range: ClosedRange<String>?) -> AppNotification? {
    guard let category = NotificationCategory(rawValue: key), let rows = value.array else { return nil }
    let old = cache.fingerprints[key]
    var fingerprints: [String: String] = [:]
    var count = 0
    let today = Day.today
    for row in rows {
        guard let id = row.itemID else { continue }
        let fp = row.canonicalData.sha256Hex
        if let old {
            let changed = old[id].map { $0 != fp } ?? false
            let new = old[id] == nil
            let day = lessonDay(row)
            let future = day.map { $0 >= today } ?? false
            let insidePrevious = day.flatMap { d in cache.timetableRange.map { $0.contains(d) } } ?? false
            let notify: Bool = switch category {
            case .timetable: future && (changed || (new && insidePrevious)) // rolling into a new week is silent
            case .messagesInbox: new // read/unread flips are not new mail
            default: changed || new
            }
            let subject = row["Tantargy"]["Nev"].isNull ? row["TantargyNeve"].text : row["Tantargy"]["Nev"].text
            let muted = [.grades, .homework, .tests].contains(category) && prefs.mutedSubjects.contains(subject)
            if notify && !muted { count += 1 }
        }
        fingerprints[id] = fp
    }
    if category == .timetable {
        if let range, let previous = cache.data[key]?.array {
            for p in previous {
                if let id = p.itemID, fingerprints[id] == nil, let d = lessonDay(p), d >= today, range.contains(d) { count += 1 }
            }
        }
        cache.timetableRange = range
    }
    cache.fingerprints[key] = fingerprints
    guard count > 0, prefs.categories.contains(category) else { return nil }
    return AppNotification(
        id: OAuth.randomToken(), kind: key, title: category.title,
        body: prefs.privateGrades && category == .grades
            ? "Új értékelés érkezett. Nyisd meg a KRETÉN-t."
            : "\(accountName) · \(count) új vagy módosult elem",
        createdAt: Date(), accountID: accountID)
}
