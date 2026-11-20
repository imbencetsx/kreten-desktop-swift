import Foundation

/// Clearly-labeled sample data for trying the app without a KRÉTA account.
enum Demo {
    static func snapshot() -> Snapshot {
        let today = Day.today
        let day = { (offset: Int) in Day.add(today, offset) }
        let subjects = ["Matematika", "Magyar irodalom", "Történelem", "Angol nyelv", "Digitális kultúra", "Biológia", "Testnevelés"]
        let teachers = ["Kovács Anna", "Szabó Eszter", "Nagy Péter", "Tóth Júlia", "Varga Dániel", "Kiss Éva", "Farkas Gábor"]
        let topics = ["Másodfokú egyenletek", "A romantika irodalma", "A reformkor", "Unit 4 · Our changing world", "Algoritmusok", "A sejt felépítése", "Atlétika"]
        let marks = [5, 4, 5, 5, 4, 3, 5, 4, 5, 2, 4, 5]
        let monday = Day.monday(of: today)

        let grades: [[String: Any]] = (0..<40).map { i in
            ["Uid": "grade-\(i)", "Tantargy": ["Nev": subjects[i % 7]], "SzamErtek": marks[i % marks.count],
             "SulySzazalekErteke": i % 4 == 0 ? 200 : 100, "KeszitesDatuma": day(-i * 3), "Tema": topics[i % 7],
             "ErtekeloTanarNeve": teachers[i % 7], "Mod": ["Leiras": i % 4 == 0 ? "Témazáró dolgozat" : "Órai munka"],
             "Tipus": ["Nev": "evkozi_jegy_ertekeles"]]
        }
        var timetable: [[String: Any]] = []
        for week in [-7, 0, 7] {
            for di in 0..<5 {
                let d = Day.add(monday, week + di)
                for i in 0..<(6 - di % 2) {
                    let n = (i + di) % 7
                    let h = String(format: "%02d", 8 + i)
                    var lesson: [String: Any] = [
                        "Uid": "lesson-\(d)-\(i)", "Datum": d, "Tantargy": ["Nev": subjects[n]],
                        "KezdetIdopont": "\(d)T\(h):00:00", "VegIdopont": "\(d)T\(h):45:00", "Oraszam": i + 1,
                        "TanarNeve": teachers[n], "TeremNeve": "\(101 + n * 11)",
                        "Tema": i % 2 == 0 ? "Gyakorlás és feladatmegoldás" : "Új ismeretek feldolgozása",
                        "Allapot": ["Nev": "Tervezett"],
                    ]
                    if week == 0 && di == 2 && i == 3 { lesson["Allapot"] = ["Nev": "Elmaradt"] }
                    if week == 0 && di == 1 && i == 2 { lesson["HelyettesTanarNeve"] = "Molnár Bence" }
                    timetable.append(lesson)
                }
            }
        }
        var calendar: [[String: Any]] = []
        let est = SchoolCalendar.estimated(Day.schoolYear(of: today))
        calendar.append(["Datum": est.first, "Naptipus": ["Nev": "ElsoTanitasiNap", "Leiras": "Első tanítási nap"]])
        calendar.append(["Datum": est.last, "Naptipus": ["Nev": "UtolsoTanitasiNap", "Leiras": "Utolsó tanítási nap"]])
        for b in est.breaks {
            var d = b.start
            while d <= b.end {
                if !Day.isWeekend(d) { calendar.append(["Datum": d, "Naptipus": ["Nev": "TanitasiSzunet", "Leiras": "Tanítási szünet"]]) }
                d = Day.add(d, 1)
            }
        }

        let data: [String: Any] = [
            "student": [
                "Nev": "Minta Alex", "IntezmenyNev": "Minta Gimnázium", "IntezmenyAzonosito": "demo",
                "EmailCim": "alex@example.invalid", "Osztaly": "11. B",
                "Gondviselok": [["Nev": "Minta Andrea", "EmailCim": "andrea@example.invalid"]],
            ],
            "grades": grades,
            "timetable": timetable,
            "homework": [
                ["Uid": "hw-1", "Tantargy": ["Nev": "Matematika"], "Szoveg": "Másodfokú egyenletek: tankönyv 84. oldal, 3–6. feladat. A megoldások menetét is írd le!", "HataridoDatuma": day(1), "RogzitoTanarNeve": teachers[0]],
                ["Uid": "hw-2", "Tantargy": ["Nev": "Angol nyelv"], "Szoveg": "Workbook, Unit 4: exercises 2–5. Prepare a short presentation about your favourite place.", "HataridoDatuma": day(2), "RogzitoTanarNeve": teachers[3]],
                ["Uid": "hw-3", "Tantargy": ["Nev": "Magyar irodalom"], "Szoveg": "Olvasd el a kijelölt verset, és gyűjtsd ki a költői képeket.", "HataridoDatuma": day(3), "RogzitoTanarNeve": teachers[1]],
            ],
            "tests": [
                ["Uid": "test-1", "Tantargy": ["Nev": "Történelem"], "Temaja": "A reformkor és az 1848-as forradalom", "Datum": day(2), "RogzitoTanarNeve": teachers[2], "Modja": ["Leiras": "Témazáró dolgozat"]],
                ["Uid": "test-2", "Tantargy": ["Nev": "Biológia"], "Temaja": "Sejtek és szövetek", "Datum": day(5), "RogzitoTanarNeve": teachers[5], "Modja": ["Leiras": "Röpdolgozat"]],
            ],
            "absences": (0..<4).map { i in
                ["Uid": "abs-\(i)", "Tantargy": ["Nev": subjects[i]], "Datum": day(-8), "IgazolasAllapota": i == 3 ? "Igazolando" : "Igazolt", "Tipus": ["Leiras": "Hiányzás"], "Ora": ["Oraszam": i + 1]]
            },
            "messagesInbox": [
                ["azonosito": "m-1", "elolvasva": false, "uzenet": ["targy": "Őszi osztálykirándulás – tudnivalók", "feladoNev": "Kovács Anna", "kuldesDatum": day(-1),
                                                                    "szoveg": "Kedves Diákok!\n\nA pénteki kirándulásra 7:45-kor találkozunk az iskola főbejáratánál. Hozzatok kényelmes cipőt, innivalót és esőkabátot.\n\nSzép hetet kívánok!\nKovács Anna"]],
                ["azonosito": "m-2", "elolvasva": true, "uzenet": ["targy": "Könyvtári nyitvatartás", "feladoNev": "Iskolai könyvtár", "kuldesDatum": day(-3),
                                                                   "szoveg": "A könyvtár hétfőtől csütörtökig 8 és 16 óra között vár mindenkit. Pénteken 14 óráig vagyunk nyitva."]],
            ],
            "messagesSent": [] as [Any], "messagesDeleted": [] as [Any],
            "notices": [["Uid": "notice-1", "Cim": "Diáknap a jövő héten", "RogzitoNeve": "Diákönkormányzat", "TartalomText": "Sport, közös programok és sok-sok élmény. A részletes program hamarosan érkezik!", "ErvenyessegKezdete": day(-2)]],
            "notes": [
                ["Uid": "note-1", "Cim": "Házi feladat hiány", "KeszitoTanarNeve": teachers[0], "Datum": day(-1), "Tipus": ["Nev": "HaziFeladatHiany", "Leiras": "Házi feladat hiány"], "Tartalom": "A kijelölt feladatgyűjteményi gyakorlatok (42–45. feladat) nem készültek el az órára."],
                ["Uid": "note-2", "Cim": "Dicséret", "KeszitoTanarNeve": teachers[1], "Datum": day(-3), "Tipus": ["Nev": "Dicseret", "Leiras": "Szaktanári dicséret"], "Tartalom": "Kiemelkedő órai aktivitásért és a versenyfeladatok önálló megoldásáért szaktanári dicséretben részesül."],
                ["Uid": "note-3", "Cim": "Figyelmeztetés", "KeszitoTanarNeve": teachers[2], "Datum": day(-5), "Tipus": ["Nev": "Figyelmeztetes", "Leiras": "Szaktanári figyelmeztetés"], "Tartalom": "Felszerelés hiánya miatt szaktanári figyelmeztetésben részesül."],
            ],
            "consultations": [["TanarNeve": teachers[0], "KezdetIdopont": "\(day(7))T16:00:00", "VegIdopont": "\(day(7))T17:00:00", "TeremNeve": "101"]],
            "lep": [["eloadasId": "lep-1", "eloadasCim": "Egy este a színházban", "helyszin": "Városi Színház", "datum": day(14), "leiras": "Közös színházi előadás a Lázár Ervin Program keretében.", "idotartam": 90, "engedelyezve": true, "engedelyezheto": true]],
            "classAverages": subjects.enumerated().map { i, s in
                ["Uid": "ca-\(i)", "Tantargy": ["Nev": s], "TanuloAtlag": [4.62, 4.1, 4.35, 4.8, 4.55, 3.9, 5.0][i], "OsztalyCsoportAtlag": [3.85, 4.02, 3.7, 4.1, 4.3, 3.95, 4.7][i]]
            },
            "schoolYear": calendar,
        ]
        let json = (try? JSONSerialization.data(withJSONObject: data)).flatMap { try? JSON.parse($0) } ?? .null
        var cache: [String: JSON] = [:]
        if case .object(let o) = json { cache = o }
        return Snapshot(
            accounts: [Account(id: "demo", name: "Minta Alex", institutionCode: "demo", institutionName: "Minta Gimnázium · bemutató", username: "demo")],
            activeAccountID: "demo", data: cache, lastSyncedAt: Date(), offline: false,
            notifications: [AppNotification(id: "n1", kind: "grades", title: "Új vagy módosult értékelés", body: "Minta Alex · 1 új vagy módosult elem", createdAt: Date().addingTimeInterval(-1800), accountID: "demo")])
    }
}
