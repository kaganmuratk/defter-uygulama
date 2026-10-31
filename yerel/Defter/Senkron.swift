import Foundation
import PencilKit
import UIKit

// Cihazlar arası eşitleme, sunucudaki MEVCUT uçlarla (sunucuda değişiklik gerektirmez):
// - İlerleme: /sync/ilerleme (web sürümüyle aynı biçim)
// - Part kaydı: /sync/cizim/<partId>#yerel içinde tek öğe { id: "yerel", zaman, veri: base64(PartKaydi) };
//   sunucu öğeleri kimlikle birleştirir, gelen kazanır → dosya başına son yazan kazanır.
// - Web sürümünde çizilen notlar (/sync/cizim/<partId>#<bölüm>) ilk açılışta PencilKit çizgisine taşınır.
@MainActor
final class Senkron: ObservableObject {
    static let ortak = Senkron()
    @Published var durum = "bekliyor"
    private var zamanlayici: Task<Void, Never>?
    private var calisiyor = false
    private var kirliPartlar: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "kirliPartlar") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "kirliPartlar") }
    }
    private var ilerlemeKirli: Bool {
        get { UserDefaults.standard.bool(forKey: "ilerlemeKirli") }
        set { UserDefaults.standard.set(newValue, forKey: "ilerlemeKirli") }
    }
    var acikPart: String?   // açık okuyucudaki part: taslağı varken sunucudan gelen sürüm üzerine yazılmaz

    func planla() {
        ilerlemeKirli = true
        zamanla()
    }
    func partKaydedildi(_ id: String) { if id.hasPrefix("k-") { return }; kirliPartlar.insert(id); zamanla() }
    private func zamanla() {
        zamanlayici?.cancel()
        zamanlayici = Task { try? await Task.sleep(nanoseconds: 2_500_000_000); if !Task.isCancelled { await hepsi() } }
    }

    func hepsi() async {
        if Ayar.ornek || calisiyor || Ayar.anahtar.isEmpty { return }
        calisiyor = true; defer { calisiyor = false }
        let icerik = IcerikYonetici.ortak
        do {
            if ilerlemeKirli {
                let govde = try JSONEncoder().encode(icerik.ilerleme.filter { !$0.key.hasPrefix("k-") })   // kendi kitaplar yalnız cihazda
                let d = try await Api.gonder("/sync/ilerleme", govde: govde)
                if let u = try? JSONDecoder().decode([String: Ilerleme].self, from: d) { icerik.ilerlemeBirlestir(u) }
                ilerlemeKirli = false
            }
            for id in kirliPartlar {
                let kayit = Depo.partKaydi(id)
                let oge: [String: Any] = ["id": "yerel", "zaman": kayit.zaman, "veri": (try JSONEncoder().encode(kayit)).base64EncodedString()]
                let govde = try JSONSerialization.data(withJSONObject: ["kaydedilen": [oge], "silinen": []])
                _ = try await Api.gonder("/sync/cizim/" + (id + "#yerel").addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_")))!, govde: govde)
                kirliPartlar.remove(id)
            }
            let d = try await Api.veri("/sync")
            guard let kok = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
            if let il = kok["ilerleme"], let ilVeri = try? JSONSerialization.data(withJSONObject: il),
               let u = try? JSONDecoder().decode([String: Ilerleme].self, from: ilVeri) { icerik.ilerlemeBirlestir(u) }
            let cizim = kok["cizim"] as? [String: Any] ?? [:]
            // Diğer cihazdan gelen yerel kayıtlar
            for (anahtar, deger) in cizim where anahtar.hasSuffix("#yerel") {
                let partId = String(anahtar.dropLast("#yerel".count))
                guard partId != acikPart, !kirliPartlar.contains(partId),
                      let liste = (deger as? [String: Any])?["kaydedilen"] as? [[String: Any]],
                      let oge = liste.first(where: { ($0["id"] as? String) == "yerel" }),
                      let b64 = oge["veri"] as? String, let veri = Data(base64Encoded: b64),
                      let uzak = try? JSONDecoder().decode(PartKaydi.self, from: veri) else { continue }
                if uzak.zaman > Depo.partKaydi(partId).zaman { Depo.yaz(uzak, Depo.kayitURL(partId)) }
            }
            webNotlariniTasi(cizim)
            durum = "eşitlendi"
        } catch {
            durum = "sunucuya ulaşılamadı"
            Tani.yaz("senkron", error.localizedDescription)
        }
    }

    // Web sürümünün çizgileri: kâğıt pikseli (800 px genişlik), [x, y, basınç]. PDF sayfasında kâğıt (48, 44) pt'den başlar.
    private func webNotlariniTasi(_ cizim: [String: Any]) {
        var gruplar: [String: [(Int, [[String: Any]], Set<String>)]] = [:]
        for (anahtar, deger) in cizim where !anahtar.hasSuffix("#yerel") {
            let parca = anahtar.split(separator: "#")
            guard parca.count == 2, let sira = Int(parca[1]), let d = deger as? [String: Any] else { continue }
            let partId = String(parca[0])
            if UserDefaults.standard.bool(forKey: "goc:" + partId) { continue }
            let silinen = Set((d["silinen"] as? [String]) ?? [])
            gruplar[partId, default: []].append((sira, (d["kaydedilen"] as? [[String: Any]]) ?? [], silinen))
        }
        for (partId, sayfalar) in gruplar {
            var kayit = Depo.partKaydi(partId)
            var tasinan = 0
            for (sira, cizgiler, silinen) in sayfalar {
                var mevcut = (kayit.cizimler["b\(sira)"]).flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
                for c in cizgiler {
                    guard (c["k"] as? Int) == 3, let id = c["id"] as? String, !silinen.contains(id),
                          let noktalar = c["noktalar"] as? [[Double]], noktalar.count > 1 else { continue }
                    let fos = (c["arac"] as? String) == "fosforlu"
                    let kalinlik = (c["kalinlik"] as? Double) ?? 3
                    let renk = Self.webRengi(c["renk"] as? String ?? "", fosforlu: fos)
                    let gen = fos ? kalinlik : kalinlik * 2
                    let pts = noktalar.enumerated().map { i, p in
                        PKStrokePoint(location: CGPoint(x: p[0] + PdfUretici.solPay, y: p[1] + PdfUretici.ustPay),
                                      timeOffset: Double(i) * 0.008, size: CGSize(width: gen, height: gen),
                                      opacity: 1, force: CGFloat(p.count > 2 ? max(0.2, p[2]) : 0.5), azimuth: 0, altitude: .pi / 2)
                    }
                    let yol = PKStrokePath(controlPoints: pts, creationDate: Date())
                    mevcut.strokes.append(PKStroke(ink: PKInk(fos ? .marker : .pen, color: renk), path: yol))
                    tasinan += 1
                }
                if !mevcut.strokes.isEmpty { kayit.cizimler["b\(sira)"] = mevcut.dataRepresentation() }
            }
            if tasinan > 0 {
                kayit.zaman = Zaman.simdi
                Depo.yaz(kayit, Depo.kayitURL(partId))
                kirliPartlar.insert(partId)
                Tani.yaz("web notları taşındı", "\(partId): \(tasinan) çizgi")
            }
            UserDefaults.standard.set(true, forKey: "goc:" + partId)
        }
    }

    static func webRengi(_ ad: String, fosforlu: Bool) -> UIColor {
        let tablo: [String: String] = fosforlu
            ? ["sarı": "f3d44a", "yeşil": "8fd694", "pembe": "f4a6c0", "turuncu": "f9a825", "mavi": "74c0fc"]
            : ["mürekkep": "15151c", "lacivert": "1c7ed6", "yeşil": "2f9e44", "turuncu": "e8590c", "bordo": "c2255c", "mor": "6741d9"]
        return UIColor(onaltilik: tablo[ad] ?? (fosforlu ? "f3d44a" : "15151c"))
    }
}

extension UIColor {
    convenience init(onaltilik: String, alfa: CGFloat = 1) {
        var v: UInt64 = 0
        Scanner(string: onaltilik.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        self.init(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: alfa)
    }
}
