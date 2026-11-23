import Foundation
import CryptoKit

var failures = 0
func check(_ cond: Bool, _ msg: String) { if !cond { failures += 1; print("FAIL:", msg) } }

// PKCE + Firka parameters
let p = try PendingLogin(), q = try PendingLogin()
check(p.verifier != q.verifier, "unique verifiers")
let login = URLComponents(url: p.url, resolvingAgainstBaseURL: false)!
let ret = login.queryItems!.first { $0.name == "ReturnUrl" }!.value!
let cb = URLComponents(string: "https://idp.e-kreta.hu\(ret)")!
let items = Dictionary(uniqueKeysWithValues: cb.queryItems!.map { ($0.name, $0.value!) })
check(items["redirect_uri"] == OAuth.redirectURI, "redirect_uri")
check(items["client_id"] == OAuth.clientID, "client_id")
check(items["code_challenge"] == Data(SHA256.hash(data: Data(p.verifier.utf8))).base64URL, "S256 challenge")
check(items["scope"] == OAuth.scopes, "scope round-trips")

// Callback validation
let good = URL(string: "\(OAuth.redirectURI)?code=synthetic&state=\(p.state)")!
check((try? p.code(from: good)) == "synthetic", "accepts correct callback")
for bad in [
    good.absoluteString.replacingOccurrences(of: "mobil.e-kreta.hu", with: "evil.example"),
    good.absoluteString.replacingOccurrences(of: p.state, with: "wrong"),
    good.absoluteString + "&state=\(p.state)",
    good.absoluteString.replacingOccurrences(of: "https:", with: "http:"),
    good.absoluteString + "#fragment",
    good.absoluteString + "&error=x",
] { check((try? p.code(from: URL(string: bad)!)) == nil, "rejects \(bad)") }

// Institution codes cannot escape *.e-kreta.hu
for bad in ["", "../evil", "x.evil", "x:443", "x@evil", "-x", "x-", "árvíz"] {
    check((try? OAuth.validateInstitution(bad)) == nil, "rejects institution \(bad)")
}
check((try? OAuth.validateInstitution(" SCHOOL-123 ")) == "school-123", "normalizes institution")

// Diff semantics
let prefs = SyncPreferences(categories: Set(NotificationCategory.allCases), mutedSubjects: [], privateGrades: false)
func j(_ s: String) -> JSON { try! JSON.parse(Data(s.utf8)) }
var cache = AccountCache()
check(diff(cache: &cache, key: "grades", value: j(#"[{"Uid":"1","SzamErtek":4}]"#), accountID: "a", accountName: "S", prefs: prefs, range: nil) == nil, "first sync silent")
let changed = j(#"[{"Uid":"1","SzamErtek":5},{"Uid":"2","SzamErtek":3}]"#)
var priv = prefs; priv.privateGrades = true
let n = diff(cache: &cache, key: "grades", value: changed, accountID: "a", accountName: "Student", prefs: priv, range: nil)
check(n != nil && !(n!.body.contains("Student")), "change notifies, private hides name")
check(diff(cache: &cache, key: "grades", value: changed, accountID: "a", accountName: "S", prefs: prefs, range: nil) == nil, "no repeat")
let restored = try JSONDecoder.store.decode(AccountCache.self, from: JSONEncoder.store.encode(cache))
var r2 = restored
check(diff(cache: &r2, key: "grades", value: changed, accountID: "a", accountName: "S", prefs: prefs, range: nil) == nil, "baseline persists")

var tt = AccountCache()
let lesson = j(#"{"Uid":"a","KezdetIdopont":"2099-10-10T08:00:00","Elmaradt":false}"#)
let newWeek = j(#"{"Uid":"b","KezdetIdopont":"2099-10-20T08:00:00"}"#)
_ = diff(cache: &tt, key: "timetable", value: .array([lesson]), accountID: "a", accountName: "S", prefs: prefs, range: "2099-10-01"..."2099-10-15")
tt.data["timetable"] = .array([lesson])
check(diff(cache: &tt, key: "timetable", value: .array([lesson, newWeek]), accountID: "a", accountName: "S", prefs: prefs, range: "2099-10-01"..."2099-10-25") == nil, "new week silent")
let canceled = j(#"{"Uid":"a","KezdetIdopont":"2099-10-10T08:00:00","Elmaradt":true}"#)
check(diff(cache: &tt, key: "timetable", value: .array([canceled, newWeek]), accountID: "a", accountName: "S", prefs: prefs, range: "2099-10-01"..."2099-10-25") != nil, "cancellation notifies")

var mail = AccountCache()
_ = diff(cache: &mail, key: "messagesInbox", value: j(#"[{"azonosito":1,"isElolvasva":false}]"#), accountID: "a", accountName: "S", prefs: prefs, range: nil)
check(diff(cache: &mail, key: "messagesInbox", value: j(#"[{"azonosito":1,"isElolvasva":true}]"#), accountID: "a", accountName: "S", prefs: prefs, range: nil) == nil, "read flag silent")
check(diff(cache: &mail, key: "messagesInbox", value: j(#"[{"azonosito":1,"isElolvasva":true},{"azonosito":2,"isElolvasva":false}]"#), accountID: "a", accountName: "S", prefs: prefs, range: nil) != nil, "new mail notifies")

var muted = AccountCache()
var mprefs = prefs; mprefs.mutedSubjects = ["Matematika"]
_ = diff(cache: &muted, key: "grades", value: .array([]), accountID: "a", accountName: "S", prefs: mprefs, range: nil)
let next = j(#"[{"Uid":"g1","Tantargy":{"Nev":"Matematika"},"SzamErtek":5}]"#)
check(diff(cache: &muted, key: "grades", value: next, accountID: "a", accountName: "S", prefs: mprefs, range: nil) == nil, "muted subject silent")
check(diff(cache: &muted, key: "grades", value: next, accountID: "a", accountName: "S", prefs: prefs, range: nil) == nil, "baseline advanced while muted")

// Normalizers & calendar
let g = Grade.parse(j(#"[{"Uid":"x","Tantargy":{"Nev":"Mat"},"SzamErtek":5,"SulySzazalekErteke":200,"KeszitesDatuma":"2026-10-01T00:00:00Z","Tema":"jegy_12"},{"Uid":"y","Tantargy":{"Nev":"Mat"},"SzamErtek":2,"KeszitesDatuma":"2026-10-02T10:00:00"}]"#))
check(g.count == 2 && g[0].id == "y" && g[1].topic.isEmpty, "grade parse/sort/jegy_ code hidden")
check(abs((g.average ?? 0) - 4.0) < 1e-9, "weighted average (5*200+2*100)/300 = 4")
check(estimatedGrade(4.5, thresholds: [1.5, 2.5, 3.5, 4.5]) == 5 && estimatedGrade(4.49, thresholds: [1.5, 2.5, 3.5, 4.5]) == 4, "rounding thresholds")
check(Day.of("2026-03-29T23:30:00Z") == "2026-03-30", "UTC timestamp → Budapest day across DST")
check(Day.weekday("2026-11-14") == 6 && Day.monday(of: "2026-11-15") == "2026-11-09", "weekday/monday")
check(SchoolCalendar.easter(2027) == "2027-03-28", "easter 2027")
let uids = studyTaskUIDs(j(#"[{"IsAktiv":false,"Tipus":"Osztaly","OktatasNevelesiFeladat":{"Uid":"old"}},{"Tipus":"Csoport","OktatasNevelesiFeladat":{"Uid":"grp"}},{"Tipus":"Osztaly","OktatasNevelesiFeladat":{"Uid":"cls"}}]"#))
check(uids == ["cls", "grp", "old"], "study task ordering \(uids)")
check(classAverageURLs(base: "https://x/a", uid: "1,2").count == 3, "class average query forms")
check(JSON.stripHTML("<p>Szia&nbsp;<b>Alex</b></p><script>x</script>") == "Szia Alex\nx", "html stripped: \(JSON.stripHTML("<p>Szia&nbsp;<b>Alex</b></p><script>x</script>").debugDescription)")
check(j("true") == .bool(true) && j("1") == .number(1), "bool vs number decoding")

check(Format.time("2026-11-16T07:15:00Z") == "08:15", "UTC lesson time shown in Budapest time: \(Format.time("2026-11-16T07:15:00Z"))")
check(Format.time("2026-11-16T07:15:00") == "07:15", "unzoned lesson time kept")
check(Format.time("2026-07-16T07:15:00Z") == "09:15", "summer time offset")

// Announced tests match by school day and subject, never by an invented period.
let testLesson = Lesson.parse(j(#"[{"Uid":"lesson-test","Tantargy":{"Nev":"Történelem"},"KezdetIdopont":"2026-11-16T08:15:00","VegIdopont":"2026-11-16T09:00:00","Oraszam":1}]"#))[0]
var announced = AnnouncedTest(id: "test", subject: "  TORTENELEM  ", topic: "Források", date: "2026-11-16", teacher: "", type: "")
check(announced.matches(testLesson), "matches normalized subject on the same day")
announced.date = "2026-11-17"
check(!announced.matches(testLesson), "does not attach another day's test")
announced.date = ""
check(!announced.matches(testLesson), "undated test does not attach to a lesson")
announced.date = "2026-11-16"; announced.subject = "Matematika"
check(!announced.matches(testLesson), "does not attach another subject's test")
var identifiedLesson = testLesson; identifiedLesson.subjectID = "subject-1"
announced.subjectID = "subject-1"
check(announced.matches(identifiedLesson), "subject IDs match even with different display names")
announced.subjectID = "subject-2"; announced.subject = testLesson.subject
check(!announced.matches(identifiedLesson), "different subject IDs override identical names")
let parsedTest = AnnouncedTest.parse(j(#"[{"Uid":"test-1","Tantargy":{"Uid":"subject-1","Nev":"Történelem"},"Datum":"2026-11-16","Temaja":"Források"}]"#))[0]
check(parsedTest.subjectID == "subject-1" && parsedTest.matches(identifiedLesson), "parses test subject ID for timetable association")

// Precomputed parsing (fast paths replacing regexes and per-call formatters).
check(Day.of("2026-11-16") == "2026-11-16" && Day.of("2026-11-16T08:15") == "2026-11-16" && Day.of("2026-11-16T08:15:00.123") == "2026-11-16", "local day forms")
check(Day.of("2026-11-16T23:30:00.500Z") == "2026-11-17", "fractional UTC timestamp → Budapest day")
check(Day.of("2026-11-16T08:15:00+01:00") == "2026-11-16" && Day.of("nonsense").isEmpty && Day.of("2026-1-16").isEmpty, "zoned/invalid day forms")
check(!Day.isLocalTimestamp("2026-11-16T08:15:00Z") && !Day.isLocalTimestamp("2026-11-16 08:15") && Day.isLocalTimestamp("2026-11-16T08:15"), "local timestamp detection")
check(Day.timestamp("2026-11-16T08:15") == Day.timestamp("2026-11-16T08:15:00") && Day.timestamp("2026-11-16T07:15:00Z") == Day.timestamp("2026-11-16T08:15:00"), "timestamp forms agree")
check(testLesson.timeRange == "08:15–09:00" && testLesson.startDate != nil && testLesson.endDate != nil, "lesson times parsed once")
check(testLesson.isActive(at: Day.timestamp("2026-11-16T08:30:00")!) && !testLesson.isActive(at: Day.timestamp("2026-11-16T09:00:00")!), "lesson active window")
let live = LiveStatus.compute(LiveStatus.timeline([testLesson]), now: Day.timestamp("2026-11-16T08:00:00")!)
check(live.kind == .upcoming && live.end == testLesson.startDate, "live status from prebuilt timeline")
let halfYear = Grade.parse(j(#"[{"Uid":"h","Tantargy":{"Nev":"Mat"},"SzamErtek":4,"Tipus":{"Nev":"Félévi értékelés"}},{"Uid":"m","Tantargy":{"Nev":"Mat"},"SzamErtek":3,"Jelleg":"Ertekeles"}]"#))
check(halfYear.filter(\.isNumeric).map(\.id) == ["m"], "semester marks don't count toward averages")
check(Format.day("2026-11-16") == Format.day("2026-11-16") && Format.day("") == "Nincs megadva" && Format.weekday("2026-11-16") == "Hétfő", "cached day labels")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
