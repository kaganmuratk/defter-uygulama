import Foundation
import SwiftUI

enum ApiHatasi: Error { case yetkisiz, sunucu(Int), cevrimdisi }

enum Api {
    static func url(_ yol: String) -> URL? {
        var c = URLComponents(string: Ayar.sunucu + yol)
        var q = c?.queryItems ?? []
        q.append(URLQueryItem(name: "k", value: Ayar.anahtar))
        c?.queryItems = q
        return c?.url
    }
    static func veri(_ yol: String, zamanAsimi: TimeInterval = 15) async throws -> Data {
        guard let u = url(yol) else { throw ApiHatasi.sunucu(0) }
        var r = URLRequest(url: u, timeoutInterval: zamanAsimi)
        r.cachePolicy = .reloadIgnoringLocalCacheData
        let (d, cevap) = try await URLSession.shared.data(for: r)
        let kod = (cevap as? HTTPURLResponse)?.statusCode ?? 0
        if kod == 401 { throw ApiHatasi.yetkisiz }
        guard (200..<300).contains(kod) else { throw ApiHatasi.sunucu(kod) }
        return d
    }
    static func gonder(_ yol: String, yontem: String = "PUT", govde: Data) async throws -> Data {
        guard let u = url(yol) else { throw ApiHatasi.sunucu(0) }
        var r = URLRequest(url: u, timeoutInterval: 30)
        r.httpMethod = yontem
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.httpBody = govde
        let (d, cevap) = try await URLSession.shared.data(for: r)
        let kod = (cevap as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(kod) else { throw ApiHatasi.sunucu(kod) }
        return d
    }
}

// Kitap içeriği: önce cihazdaki kopya, internet olunca arka planda tamamı indirilir (internetsiz çalışma).
@MainActor
final class IcerikYonetici: ObservableObject {
    static let ortak = IcerikYonetici()
    @Published var plan: Plan?
    @Published var kendi: [Ders] = []            // kullanıcının kendi kitapları (Kendi.swift)
    @Published var ilerleme: [String: Ilerleme] = [:]
    @Published var indirme: String = ""          // Ayarlar'da gösterilen çevrimdışı kopya durumu
    @Published var anahtarGerekli = false
    @Published var hata: String?
    private var calisiyor = false

    init() {
        if Ayar.ornek { plan = Ornek.plan; anahtarGerekli = false; return }
        kendi = Depo.oku([Ders].self, KendiDepo.kitapURL) ?? []
        plan = Depo.oku(Plan.self, Depo.icerik.appendingPathComponent("plan.json"))
        ilerleme = Depo.oku([String: Ilerleme].self, Depo.kok.appendingPathComponent("ilerleme.json")) ?? [:]
        anahtarGerekli = Ayar.anahtar.isEmpty
    }

    func part(_ id: String) -> Part? {
        if let o = ozetBul(id), id.hasPrefix("k-") { return KendiDepo.part(id, no: o.no, baslik: o.baslik) }
        if Ayar.ornek { return Ornek.part(id) }
        return Depo.oku(Part.self, Depo.icerik.appendingPathComponent(id + ".json"))
    }

    func ozetBul(_ id: String) -> PartOzet? { dersler.flatMap { $0.bolumler.flatMap { $0.partlar } }.first { $0.id == id } }

    // Plan + bütün partlar + görseller. Var olan kopya hemen kullanılır; ağ hatası içeriği bozmaz.
    func indir() async {
        if Ayar.ornek || calisiyor || Ayar.anahtar.isEmpty { return }
        calisiyor = true; defer { calisiyor = false }
        do {
            let planVeri = try await Api.veri("/icerik/plan.json")
            let yeni = try JSONDecoder().decode(Plan.self, from: planVeri)
            try planVeri.write(to: Depo.icerik.appendingPathComponent("plan.json"), options: .atomic)
            plan = yeni; hata = nil; anahtarGerekli = false
            let partlar = yeni.dersler.flatMap { $0.bolumler.flatMap { $0.partlar } }.filter { $0.hazir }
            var hazirPart = 0, gorsel = 0, gorselToplam = 0
            for p in partlar {
                guard let d = try? await Api.veri("/icerik/\(p.id).json"), let part = try? JSONDecoder().decode(Part.self, from: d) else { continue }
                try? d.write(to: Depo.icerik.appendingPathComponent(p.id + ".json"), options: .atomic)
                hazirPart += 1
                for yol in Self.gorselYollari(part) {
                    gorselToplam += 1
                    let hedef = Depo.icerik.appendingPathComponent(yol)
                    if FileManager.default.fileExists(atPath: hedef.path) { gorsel += 1; continue }
                    if let g = try? await Api.veri("/icerik/" + yol, zamanAsimi: 30) {
                        try? FileManager.default.createDirectory(at: hedef.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? g.write(to: hedef, options: .atomic); gorsel += 1
                    }
                }
            }
            indirme = "\(hazirPart)/\(partlar.count) part, \(gorsel)/\(gorselToplam) görsel cihazda"
            UserDefaults.standard.set(indirme, forKey: "indirme")
            // Part'lar açılışta takılmasın diye PDF'ler arka planda önceden hazırlanır
            let hazirlanacak = partlar.compactMap { part($0.id) }
            Task(priority: .utility) { await PdfUretici.ortak.hepsiniHazirla(hazirlanacak) }
        } catch ApiHatasi.yetkisiz {
            anahtarGerekli = true; hata = "Anahtar kabul edilmedi."
        } catch {
            Tani.yaz("içerik indirme", error.localizedDescription)
            if plan == nil { hata = "İçerik indirilemedi. İnternet bağlantısını kontrol edin." }
        }
        indirme = UserDefaults.standard.string(forKey: "indirme") ?? indirme
    }

    static func gorselYollari(_ p: Part) -> [String] {
        let html = ([p.giris ?? ""] + p.bolumler.map { $0.html }).joined()
        guard let re = try? NSRegularExpression(pattern: #"src="icerik/(gorseller/[^"]+)""#) else { return [] }
        return re.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap {
            Range($0.range(at: 1), in: html).map { String(html[$0]) }
        }
    }

    // İlerleme: cihaza yaz, senkron kuyruğuna ekle
    func ilerlemeYaz(_ partId: String, _ degistir: (inout Ilerleme) -> Void) {
        var i = ilerleme[partId] ?? Ilerleme()
        degistir(&i)
        i.guncelleme = Zaman.simdi
        ilerleme[partId] = i
        if !Ayar.ornek { Depo.yaz(ilerleme, Depo.kok.appendingPathComponent("ilerleme.json")) }
        Senkron.ortak.planla()
    }
    func ilerlemeBirlestir(_ uzak: [String: Ilerleme]) {
        var degisti = false
        for (id, v) in uzak where (v.guncelleme ?? 0) > (ilerleme[id]?.guncelleme ?? 0) { ilerleme[id] = v; degisti = true }
        if degisti { Depo.yaz(ilerleme, Depo.kok.appendingPathComponent("ilerleme.json")) }
    }
}
