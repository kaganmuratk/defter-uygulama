import Foundation

// Cihazdaki dosyalar: Application Support/Defter/{icerik, kayit, taslak}. Her yazım atomik.
enum Depo {
    static let kok: URL = {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Defter", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    static func klasor(_ ad: String) -> URL {
        let u = kok.appendingPathComponent(ad, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var icerik: URL { klasor("icerik") }
    static var gorseller: URL { klasor("icerik/gorseller") }
    static var pdfler: URL { klasor("pdf") }
    static var kayit: URL { klasor("kayit") }
    static var taslak: URL { klasor("taslak") }

    static func oku<T: Decodable>(_ tur: T.Type, _ url: URL) -> T? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    @discardableResult
    static func yaz<T: Encodable>(_ deger: T, _ url: URL) -> Bool {
        do { try JSONEncoder().encode(deger).write(to: url, options: .atomic); return true }
        catch { Tani.yaz("dosya yazılamadı", url.lastPathComponent + ": " + error.localizedDescription); return false }
    }

    // Part kaydı ve taslağı
    static func kayitURL(_ partId: String) -> URL { kayit.appendingPathComponent(partId + ".json") }
    static func taslakURL(_ partId: String) -> URL { taslak.appendingPathComponent(partId + ".json") }
    static func partKaydi(_ partId: String) -> PartKaydi { oku(PartKaydi.self, kayitURL(partId)) ?? PartKaydi() }
}

// Basit ayarlar (UserDefaults)
enum Ayar {
    static let varsayilanSunucu = "https://defter-api.revela-site.workers.dev"
    static var anahtar: String {
        get { UserDefaults.standard.string(forKey: "anahtar") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "anahtar") }
    }
    static var sunucu: String { UserDefaults.standard.string(forKey: "sunucu") ?? varsayilanSunucu }
    static var ornek: Bool { ProcessInfo.processInfo.arguments.contains("-ornek") }   // UI testleri: örnek içerik, sunucu yok
}

// Tanı kaydı: cihazda olan hataları sonradan görmek için (Ayarlar → Tanı kaydı)
enum Tani {
    static func yaz(_ olay: String, _ ayrinti: String = "") {
        var k = UserDefaults.standard.stringArray(forKey: "tani") ?? []
        let f = DateFormatter(); f.dateFormat = "dd.MM HH:mm:ss"
        k.append("\(f.string(from: Date()))  \(olay)  \(ayrinti)")
        UserDefaults.standard.set(Array(k.suffix(60)), forKey: "tani")
    }
    static var kayitlar: [String] { (UserDefaults.standard.stringArray(forKey: "tani") ?? []).reversed() }
    static func temizle() { UserDefaults.standard.removeObject(forKey: "tani") }
}
