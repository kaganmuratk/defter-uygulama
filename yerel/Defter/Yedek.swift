import Foundation
import SwiftUI

// Yedek: kullanıcının seçtiği klasöre (iCloud Drive içinde olması önerilir) kendi kitaplar, notlar/çizimler, taslaklar ve konumlar
// kopyalanır; gerekirse oradan geri yüklenir. Hazır kitapların içeriği (icerik/, pdf/) yedeklenmez, internetten yeniden iner.
// Yedekte hiçbir şey silinmez: cihazdan silinen kitabın dosyaları yedekte kalır (güvenlik önceliklidir).

enum YedekMantik {
    static let klasorAdi = "Defter-Yedek"
    /// Kök klasöre göre yedeklenen yollar (klasör ya da dosya)
    static let ogeler = ["kayit", "taslak", "kendi", "kendi.json", "kendi-partlar.json", "ilerleme.json", "konum.json"]

    /// Yedeklerken: kaynaktaki dosya hedefte yoksa ya da boyut/zaman farklıysa kopyalanır; sonra hedefin değişiklik zamanı kaynakla eşitlenir
    /// Geri yüklerken (sadeceYeniyse): hedefte yoksa ya da kaynak daha yeniyse kopyalanır; cihazdaki yeni iş asla ezilmez
    static func dosyaKopyala(_ k: URL, _ h: URL, sadeceYeniyse: Bool) throws -> Bool {
        let fm = FileManager.default
        let kb = try fm.attributesOfItem(atPath: k.path)
        let km = (kb[.modificationDate] as? Date) ?? Date()
        let ks = (kb[.size] as? NSNumber)?.int64Value ?? -1
        if let hb = try? fm.attributesOfItem(atPath: h.path) {
            let hm = (hb[.modificationDate] as? Date) ?? .distantPast
            let hs = (hb[.size] as? NSNumber)?.int64Value ?? -2
            if sadeceYeniyse {
                if km.timeIntervalSince(hm) <= 1 { return false }
            } else if hs == ks && abs(km.timeIntervalSince(hm)) <= 1 { return false }
        }
        try fm.createDirectory(at: h.deletingLastPathComponent(), withIntermediateDirectories: true)
        let gecici = h.deletingLastPathComponent().appendingPathComponent(".yedek-" + UUID().uuidString)
        try fm.copyItem(at: k, to: gecici)
        if fm.fileExists(atPath: h.path) { _ = try fm.replaceItemAt(h, withItemAt: gecici) } else { try fm.moveItem(at: gecici, to: h) }
        try? fm.setAttributes([.modificationDate: km], ofItemAtPath: h.path)
        return true
    }

    /// Bir klasörü ya da dosyayı özyinelemeli kopyalar; kopyalanan dosya sayısını döndürür
    static func agacKopyala(_ k: URL, _ h: URL, sadeceYeniyse: Bool) throws -> Int {
        let fm = FileManager.default
        var klasorMu: ObjCBool = false
        guard fm.fileExists(atPath: k.path, isDirectory: &klasorMu) else { return 0 }
        if !klasorMu.boolValue { return try dosyaKopyala(k, h, sadeceYeniyse: sadeceYeniyse) ? 1 : 0 }
        var sayi = 0
        try fm.createDirectory(at: h, withIntermediateDirectories: true)
        for ad in try fm.contentsOfDirectory(atPath: k.path) where !ad.hasPrefix(".") {
            sayi += try agacKopyala(k.appendingPathComponent(ad), h.appendingPathComponent(ad), sadeceYeniyse: sadeceYeniyse)
        }
        return sayi
    }

    /// kok → yedekKlasoru/Defter-Yedek/...
    static func yedekle(kok: URL, hedefKlasor: URL) throws -> Int {
        let yedek = hedefKlasor.appendingPathComponent(klasorAdi, isDirectory: true)
        try FileManager.default.createDirectory(at: yedek, withIntermediateDirectories: true)
        var sayi = 0
        for o in ogeler { sayi += try agacKopyala(kok.appendingPathComponent(o), yedek.appendingPathComponent(o), sadeceYeniyse: false) }
        return sayi
    }

    /// yedekKlasoru/Defter-Yedek/... → kok. Listeler birleştirilir (cihazdaki yeni iş korunur), dosyalar yalnız yeniyse üzerine yazılır
    static func geriYukle(kok: URL, yedekKlasoru: URL) throws -> Int {
        let yedek = yedekKlasoru.appendingPathComponent(klasorAdi, isDirectory: true)
        guard FileManager.default.fileExists(atPath: yedek.path) else { throw YedekHatasi.yedekYok }
        var sayi = 0
        for o in ogeler where !o.hasSuffix(".json") || o.hasPrefix("kayit") {
            sayi += try agacKopyala(yedek.appendingPathComponent(o), kok.appendingPathComponent(o), sadeceYeniyse: true)
        }
        sayi += try birlestir([Ders].self, "kendi.json", yedek, kok) { yerel, yedekte in
            yerel + yedekte.filter { y in !yerel.contains { $0.id == y.id } }
        }
        sayi += try birlestir([String: KendiParca].self, "kendi-partlar.json", yedek, kok) { yerel, yedekte in
            yedekte.merging(yerel) { _, y in y }
        }
        sayi += try birlestir([String: Konum.Kayit].self, "konum.json", yedek, kok) { yerel, yedekte in
            yedekte.merging(yerel) { _, y in y }
        }
        sayi += try birlestir([String: Ilerleme].self, "ilerleme.json", yedek, kok) { yerel, yedekte in
            var s = yerel
            for (id, v) in yedekte where (v.guncelleme ?? 0) > (s[id]?.guncelleme ?? 0) { s[id] = v }
            return s
        }
        return sayi
    }

    private static func birlestir<T: Codable>(_ tur: T.Type, _ ad: String, _ yedek: URL, _ kok: URL, _ f: (T, T) -> T) throws -> Int {
        let ky = yedek.appendingPathComponent(ad), kh = kok.appendingPathComponent(ad)
        guard let veri = try? Data(contentsOf: ky), let yedekte = try? JSONDecoder().decode(T.self, from: veri) else { return 0 }
        let yerel = (try? Data(contentsOf: kh)).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
        let sonuc = yerel.map { f($0, yedekte) } ?? yedekte
        try JSONEncoder().encode(sonuc).write(to: kh, options: .atomic)
        return 1
    }
}

enum YedekHatasi: Error, LocalizedError {
    case yedekYok, klasorYok
    var errorDescription: String? {
        switch self {
        case .yedekYok: return "Bu klasörde Defter yedeği bulunamadı."
        case .klasorYok: return "Önce bir yedek klasörü seç."
        }
    }
}

@MainActor
final class Yedek: ObservableObject {
    static let ortak = Yedek()
    @Published var durum = ""                // Ayarlar'da gösterilen son durum
    @Published var klasorAdi = ""            // seçilen klasörün adı
    @Published var bulutta: Bool?            // klasör iCloud Drive'da mı (bilinmiyorsa nil)
    @Published var calisiyor = false
    @Published var klasorVar = false
    private var gecikme: Task<Void, Never>?
    private let yerKey = "yedekKlasorYer"
    private let sonKey = "yedekSon"

    init() {
        klasorVar = UserDefaults.standard.data(forKey: yerKey) != nil
        if let son = UserDefaults.standard.object(forKey: sonKey) as? Date { durum = "Son yedek: " + Self.zamanYazisi(son) }
        if let u = klasor() { bilgiYenile(u) }
    }

    private static func zamanYazisi(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d MMM HH:mm"; f.locale = Locale(identifier: "tr_TR")
        return f.string(from: d)
    }

    private func klasor() -> URL? {
        guard let veri = UserDefaults.standard.data(forKey: yerKey) else { return nil }
        var eski = false
        guard let u = try? URL(resolvingBookmarkData: veri, options: [], relativeTo: nil, bookmarkDataIsStale: &eski) else { return nil }
        if eski, let yeni = try? u.bookmarkData() { UserDefaults.standard.set(yeni, forKey: yerKey) }
        return u
    }
    private func bilgiYenile(_ u: URL) {
        klasorAdi = u.lastPathComponent
        let erisim = u.startAccessingSecurityScopedResource()
        defer { if erisim { u.stopAccessingSecurityScopedResource() } }
        let ubik = (try? u.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem
        bulutta = (ubik == true || u.path.contains("com~apple~CloudDocs") || u.path.contains("Mobile Documents")) ? true : false
    }

    func klasorSec(_ sonuc: Result<URL, Error>) {
        guard case .success(let u) = sonuc else { return }
        let erisim = u.startAccessingSecurityScopedResource()
        defer { if erisim { u.stopAccessingSecurityScopedResource() } }
        guard let veri = try? u.bookmarkData() else { durum = "Klasör kaydedilemedi."; return }
        UserDefaults.standard.set(veri, forKey: yerKey)
        klasorVar = true
        bilgiYenile(u)
        simdi()
    }

    /// Kısa bir bekleyişten sonra yedekler (art arda kayıtlar tek yedekte toplanır)
    func planla() {
        guard klasorVar, !Ayar.ornek else { return }
        gecikme?.cancel()
        gecikme = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            if !Task.isCancelled { self?.simdi() }
        }
    }

    func simdi() {
        guard !Ayar.ornek, !calisiyor else { return }
        guard let hedef = klasor() else { durum = YedekHatasi.klasorYok.localizedDescription; return }
        calisiyor = true; durum = "Yedekleniyor…"
        let kok = Depo.kok
        Task {
            let sonuc: Result<Int, Error> = await Task.detached(priority: .utility) {
                let erisim = hedef.startAccessingSecurityScopedResource()
                defer { if erisim { hedef.stopAccessingSecurityScopedResource() } }
                return Result { try YedekMantik.yedekle(kok: kok, hedefKlasor: hedef) }
            }.value
            calisiyor = false
            switch sonuc {
            case .success(let n):
                UserDefaults.standard.set(Date(), forKey: sonKey)
                durum = "Son yedek: " + Self.zamanYazisi(Date()) + (n > 0 ? " (\(n) dosya)" : " (değişiklik yok)")
            case .failure(let e):
                durum = "Yedek alınamadı: " + e.localizedDescription
                Tani.yaz("yedek", e.localizedDescription)
            }
        }
    }

    func geriYukle() {
        guard !Ayar.ornek, !calisiyor else { return }
        guard let kaynak = klasor() else { durum = YedekHatasi.klasorYok.localizedDescription; return }
        calisiyor = true; durum = "Geri yükleniyor…"
        let kok = Depo.kok
        Task {
            let sonuc: Result<Int, Error> = await Task.detached(priority: .userInitiated) {
                let erisim = kaynak.startAccessingSecurityScopedResource()
                defer { if erisim { kaynak.stopAccessingSecurityScopedResource() } }
                return Result { try YedekMantik.geriYukle(kok: kok, yedekKlasoru: kaynak) }
            }.value
            calisiyor = false
            switch sonuc {
            case .success(let n):
                Konum.yenile()
                IcerikYonetici.ortak.diskeYenidenOku()
                durum = "Geri yüklendi (\(n) dosya). Kitaplar ve notlar kitaplıkta görünür."
            case .failure(let e):
                durum = "Geri yüklenemedi: " + e.localizedDescription
                Tani.yaz("geri yükleme", e.localizedDescription)
            }
        }
    }
}

extension IcerikYonetici {
    /// Geri yüklemeden sonra bellekteki listeleri diskten yeniler
    func diskeYenidenOku() {
        kendi = Depo.oku([Ders].self, KendiDepo.kitapURL) ?? kendi
        ilerleme = Depo.oku([String: Ilerleme].self, Depo.kok.appendingPathComponent("ilerleme.json")) ?? ilerleme
    }
}

// Yedek mantığının kendi kendine sınavı (CI'da -yedekTesti ile açılır): geçici klasörlerde yedekle, sil, geri yükle, karşılaştır
enum YedekSinavi {
    static func calistir() -> String {
        let fm = FileManager.default
        let temel = fm.temporaryDirectory.appendingPathComponent("yedek-sinav-" + UUID().uuidString)
        defer { try? fm.removeItem(at: temel) }
        do {
            let a = temel.appendingPathComponent("A"), bulut = temel.appendingPathComponent("Bulut"), c = temel.appendingPathComponent("C")
            for d in [a, bulut, c] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
            try fm.createDirectory(at: a.appendingPathComponent("kayit"), withIntermediateDirectories: true)
            try fm.createDirectory(at: a.appendingPathComponent("kendi"), withIntermediateDirectories: true)
            let kayit = Data("{\"cizimler\":{\"b0\":\"AAEC\"},\"notlar\":[],\"ekSayfalar\":[],\"zaman\":1}".utf8)
            let pdf = Data((0..<4096).map { UInt8($0 % 251) })
            let kitaplar = [Ders(id: "k-aaaa1111", baslik: "Kimya", kaynak: nil, bolumler: [Bolum(no: 1, baslik: "Kimya", partlar: [PartOzet(no: 1, baslik: "Kimya", kitap: nil, id: "k-aaaa1111", hazir: true)])])]
            try kayit.write(to: a.appendingPathComponent("kayit/k-aaaa1111.json"))
            try pdf.write(to: a.appendingPathComponent("kendi/k-aaaa1111.pdf"))
            try JSONEncoder().encode(kitaplar).write(to: a.appendingPathComponent("kendi.json"))
            try JSONEncoder().encode(["k-aaaa1111": KendiParca(desen: "kareli", pdf: true, sayfa: 3)]).write(to: a.appendingPathComponent("kendi-partlar.json"))
            try JSONEncoder().encode(["k-aaaa1111": Konum.Kayit(son: "b2", kaldim: nil)]).write(to: a.appendingPathComponent("konum.json"))

            let n1 = try YedekMantik.yedekle(kok: a, hedefKlasor: bulut)
            guard n1 == 5 else { return "HATA: ilk yedekte \(n1) dosya (5 beklenir)" }
            let n2 = try YedekMantik.yedekle(kok: a, hedefKlasor: bulut)
            guard n2 == 0 else { return "HATA: değişiklik yokken \(n2) dosya kopyalandı" }
            // cihaz "silindi": C boş, oraya geri yükle
            _ = try YedekMantik.geriYukle(kok: c, yedekKlasoru: bulut)
            guard try Data(contentsOf: c.appendingPathComponent("kayit/k-aaaa1111.json")) == kayit else { return "HATA: not kaydı farklı" }
            guard try Data(contentsOf: c.appendingPathComponent("kendi/k-aaaa1111.pdf")) == pdf else { return "HATA: PDF farklı" }
            let geri = try JSONDecoder().decode([Ders].self, from: Data(contentsOf: c.appendingPathComponent("kendi.json")))
            guard geri.first?.id == "k-aaaa1111", geri.first?.baslik == "Kimya" else { return "HATA: kitap listesi farklı" }
            let kp = try JSONDecoder().decode([String: KendiParca].self, from: Data(contentsOf: c.appendingPathComponent("kendi-partlar.json")))
            guard kp["k-aaaa1111"]?.sayfa == 3, kp["k-aaaa1111"]?.pdf == true else { return "HATA: part bilgisi farklı" }
            // cihazda yeni yazılmış not, eski yedekle ezilmemeli
            let yeniKayit = Data("{\"cizimler\":{\"b0\":\"AAEC\",\"b1\":\"BBBB\"},\"notlar\":[],\"ekSayfalar\":[],\"zaman\":2}".utf8)
            try yeniKayit.write(to: c.appendingPathComponent("kayit/k-aaaa1111.json"))
            _ = try YedekMantik.geriYukle(kok: c, yedekKlasoru: bulut)
            guard try Data(contentsOf: c.appendingPathComponent("kayit/k-aaaa1111.json")) == yeniKayit else { return "HATA: cihazdaki yeni not eski yedekle ezildi" }
            // cihazda başka bir kitap varsa geri yükleme onu silmemeli
            var yerelKitaplar = geri
            yerelKitaplar.append(Ders(id: "k-bbbb2222", baslik: "Fizik", kaynak: nil, bolumler: []))
            try JSONEncoder().encode(yerelKitaplar).write(to: c.appendingPathComponent("kendi.json"))
            _ = try YedekMantik.geriYukle(kok: c, yedekKlasoru: bulut)
            let son = try JSONDecoder().decode([Ders].self, from: Data(contentsOf: c.appendingPathComponent("kendi.json")))
            guard son.count == 2 else { return "HATA: birleştirme sonrası \(son.count) kitap (2 beklenir)" }
            return "YEDEK-TEST: TAMAM"
        } catch { return "HATA: " + error.localizedDescription }
    }
}

struct YedekSinavEkrani: View {
    @State private var sonuc = "çalışıyor…"
    var body: some View {
        Text(sonuc).font(.title.bold()).padding().accessibilityIdentifier("yedek-sonuc")
            .task { sonuc = YedekSinavi.calistir() }
    }
}
