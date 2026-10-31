import Foundation

// Sunucudaki içerik biçimi (fizyoloji deposu `npm run icerik` çıktısı; web sürümüyle aynı).
struct Plan: Codable { var dersler: [Ders] }
struct Ders: Codable, Identifiable, Hashable {
    var id: String
    var baslik: String
    var kaynak: String?
    var bolumler: [Bolum]
}
struct Bolum: Codable, Identifiable, Hashable {
    var no: Int
    var baslik: String
    var partlar: [PartOzet]
    var id: Int { no }
}
struct PartOzet: Codable, Identifiable, Hashable {
    var no: Int
    var baslik: String
    var kitap: String?
    var id: String
    var hazir: Bool
}
struct Part: Codable {
    var id: String
    var no: Int
    var baslik: String
    var kitap: String?
    var giris: String?
    var bolumler: [PartBolum]
}
struct PartBolum: Codable {
    var id: String
    var baslik: String
    var kisa: String?
    var html: String
}

// İlerleme (web sürümüyle aynı biçim; sunucuda /sync/ilerleme)
struct Ilerleme: Codable, Equatable {
    var sayfa: Int?          // bölüm (section) sırası
    var ziyaret: [Int]?
    var durum: String?       // "yarim" | "bitti"
    var guncelleme: Double?  // ms
}

// Bir part'ın kullanıcı verisi: sayfa çizimleri, yapışkan notlar, eklenen boş sayfalar.
// Tek dosya olarak saklanır; kayıt onayı (Kaydet/Vazgeç) bu dosyanın taslak kopyası üzerinden işler.
struct PartKaydi: Codable, Equatable {
    var cizimler: [String: Data] = [:]      // sayfa anahtarı → PKDrawing.dataRepresentation()
    var notlar: [YapiskanNot] = []
    var ekSayfalar: [EkSayfa] = []
    var zaman: Double = 0                   // son kayıt (ms), senkronda son yazan kazanır
}
struct YapiskanNot: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var sayfa: String          // sayfa anahtarı
    var x: Double              // sayfa üzerinde konum (pt, sol üst köşe başlangıç)
    var y: Double
    var renk: String = "sari"
    var yazi: String = ""
    var cizim: Data?           // notun içine kalemle yazılan
    var zaman: Double = Date().timeIntervalSince1970 * 1000
}
struct EkSayfa: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var sonra: String          // hangi sayfanın ardından gelir (sayfa anahtarı)
    var cizgili: Bool = true
}

// PDF içindeki her sayfanın anlamı. İçerik sayfası "b<i>", cevap sayfası "c<i>", eklenen sayfa "e<id>".
struct SayfaBilgi: Codable, Hashable {
    var anahtar: String
    var baslik: String
    var bolumSira: Int?        // web uyumlu ilerleme için bölüm sırası
    var atiflar: [Atif]?       // sayfadaki "Şekil 1.3" / "Tablo 1.1" gibi dokunulur atıflar (sayfa üstünden px)
    var hedefler: [String: Double]?   // bu sayfadaki şekil/tablolar: ad → üstten uzaklık (px)
}
struct Atif: Codable, Hashable {
    var ad: String
    var x: Double, y: Double, w: Double, h: Double
}

enum Zaman { static var simdi: Double { Date().timeIntervalSince1970 * 1000 } }
