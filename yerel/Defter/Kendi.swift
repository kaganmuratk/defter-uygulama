import SwiftUI
import PDFKit
import PencilKit
import UniformTypeIdentifiers

// Kendi kitapların: kitap → bölüm → part, hazır kitaplarla aynı ekranlar. Part = boş sayfa (çizgili, kareli, noktalı, düz)
// ya da içe aktarılan PDF; üstüne kalemle yazılır/çizilir, yapışkan not eklenir. Kimlikleri "k-" ile başlar, yalnız cihazda durur.

struct KendiParca: Codable, Equatable {
    var desen: String = "cizgili"   // boş part'ın sayfa deseni
    var pdf = false                 // içe aktarılan PDF mi (kendi/<id>.pdf)
    var sayfa = 1
}

enum KendiDepo {
    static var klasor: URL { Depo.klasor("kendi") }
    static var metaURL: URL { Depo.kok.appendingPathComponent("kendi-partlar.json") }
    static var kitapURL: URL { Depo.kok.appendingPathComponent("kendi.json") }
    static func pdfURL(_ id: String) -> URL { klasor.appendingPathComponent(id + ".pdf") }
    static var meta: [String: KendiParca] {
        get { Depo.oku([String: KendiParca].self, metaURL) ?? [:] }
        set { Depo.yaz(newValue, metaURL) }
    }
    static func yeniId() -> String { "k-" + UUID().uuidString.prefix(8).lowercased() }

    // Okuyucunun beklediği Part: her sayfa bir "bölüm" sayılır (son sayfada "Bitti olarak işaretle" çıkar)
    static func part(_ id: String, no: Int, baslik: String) -> Part {
        let n = max(1, meta[id]?.sayfa ?? 1)
        return Part(id: id, no: no, baslik: baslik, kitap: nil, giris: nil,
                    bolumler: (0..<n).map { PartBolum(id: "s\($0)", baslik: "Sayfa \($0 + 1)", kisa: nil, html: "") })
    }

    @MainActor static func belge(_ part: Part) -> (PDFDocument, [SayfaBilgi])? {
        guard let m = meta[part.id] else { return nil }
        let doc: PDFDocument
        if m.pdf {
            guard let d = PDFDocument(url: pdfURL(part.id)) else { return nil }
            doc = d
        } else {
            doc = PDFDocument()
            let desen = BosSayfa.Desen(rawValue: m.desen) ?? .cizgili
            for _ in 0..<max(1, m.sayfa) { doc.insert(BosSayfa(desen: desen), at: doc.pageCount) }
        }
        let bilgi = (0..<doc.pageCount).map { SayfaBilgi(anahtar: "b\($0)", baslik: "Sayfa \($0 + 1)", bolumSira: $0) }
        return (doc, bilgi)
    }

    static func temizle(_ id: String) {
        var m = meta; m[id] = nil; meta = m
        for u in [pdfURL(id), Depo.kayitURL(id), Depo.taslakURL(id)] { try? FileManager.default.removeItem(at: u) }
    }
}

extension IcerikYonetici {
    var dersler: [Ders] { (plan?.dersler ?? []) + kendi }

    func kendiKaydet() { if !Ayar.ornek { Depo.yaz(kendi, KendiDepo.kitapURL) } }
    private func degistir(_ dersId: String, _ f: (inout Ders) -> Void) {
        guard let i = kendi.firstIndex(where: { $0.id == dersId }) else { return }
        f(&kendi[i]); kendiKaydet()
    }

    func kitapEkle(_ ad: String) {
        kendi.append(Ders(id: KendiDepo.yeniId(), baslik: ad, kaynak: nil, bolumler: [])); kendiKaydet()
    }
    func kitapAdi(_ id: String, _ ad: String) { degistir(id) { $0.baslik = ad } }
    func kitapSil(_ id: String) {
        kendi.first { $0.id == id }?.bolumler.flatMap { $0.partlar }.forEach { partTemizle($0.id) }
        kendi.removeAll { $0.id == id }; kendiKaydet()
    }

    func bolumEkle(_ dersId: String, _ ad: String) {
        degistir(dersId) { d in d.bolumler.append(Bolum(no: (d.bolumler.map { $0.no }.max() ?? 0) + 1, baslik: ad, partlar: [])) }
    }
    func bolumAdi(_ dersId: String, _ no: Int, _ ad: String) {
        degistir(dersId) { d in if let i = d.bolumler.firstIndex(where: { $0.no == no }) { d.bolumler[i].baslik = ad } }
    }
    func bolumSil(_ dersId: String, _ no: Int) {
        degistir(dersId) { d in
            d.bolumler.filter { $0.no == no }.flatMap { $0.partlar }.forEach { partTemizle($0.id) }
            d.bolumler.removeAll { $0.no == no }
        }
    }

    /// desen: boş part'ın sayfa deseni; pdf (dosya adresi) verilirse içe aktarılır
    func partEkle(_ dersId: String, _ bolumNo: Int, ad: String, desen: String = "cizgili", pdf: URL? = nil) {
        let id = KendiDepo.yeniId()
        var m = KendiParca(desen: desen)
        if let pdf {
            // Çok sayfalı kitaplar için dosya doğrudan kopyalanır (belleğe alınmaz); sayfalar okuyucuda tembel yüklenir
            let hedef = KendiDepo.pdfURL(id)
            do { try FileManager.default.copyItem(at: pdf, to: hedef) } catch { Tani.yaz("PDF kopyalanamadı", error.localizedDescription); return }
            guard let belge = PDFDocument(url: hedef), belge.pageCount > 0, !belge.isLocked else {
                try? FileManager.default.removeItem(at: hedef); Tani.yaz("PDF açılamadı", ad); return
            }
            m.pdf = true; m.sayfa = belge.pageCount
        }
        var tum = KendiDepo.meta; tum[id] = m; KendiDepo.meta = tum
        degistir(dersId) { d in
            guard let i = d.bolumler.firstIndex(where: { $0.no == bolumNo }) else { return }
            let no = (d.bolumler[i].partlar.map { $0.no }.max() ?? 0) + 1
            d.bolumler[i].partlar.append(PartOzet(no: no, baslik: ad, kitap: nil, id: id, hazir: true))
        }
    }
    func partAdi(_ dersId: String, _ bolumNo: Int, _ partId: String, _ ad: String) {
        degistir(dersId) { d in
            guard let i = d.bolumler.firstIndex(where: { $0.no == bolumNo }), let j = d.bolumler[i].partlar.firstIndex(where: { $0.id == partId }) else { return }
            d.bolumler[i].partlar[j].baslik = ad
        }
    }
    func partSil(_ dersId: String, _ bolumNo: Int, _ partId: String) {
        partTemizle(partId)
        degistir(dersId) { d in
            guard let i = d.bolumler.firstIndex(where: { $0.no == bolumNo }) else { return }
            d.bolumler[i].partlar.removeAll { $0.id == partId }
        }
    }
    private func partTemizle(_ id: String) {
        KendiDepo.temizle(id)
        if ilerleme[id] != nil { ilerleme[id] = nil; if !Ayar.ornek { Depo.yaz(ilerleme, Depo.kok.appendingPathComponent("ilerleme.json")) } }
    }
}

// Ad sorusu (yeni kitap/bölüm/part, ad değiştirme) ve silme onayı
struct AdIstegi: Identifiable {
    let id = UUID()
    let baslik: String
    let ilk: String
    let tamam: (String) -> Void
}
struct AdSorusu: ViewModifier {
    @Binding var istek: AdIstegi?
    @State private var metin = ""
    func body(content: Content) -> some View {
        content
            .alert(istek?.baslik ?? "", isPresented: Binding(get: { istek != nil }, set: { if !$0 { istek = nil } })) {
                TextField("Ad", text: $metin)
                Button("Tamam") {
                    let t = metin.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { istek?.tamam(t) }
                }
                Button("Vazgeç", role: .cancel) {}
            }
            .onChange(of: istek?.id) { _, _ in metin = istek?.ilk ?? "" }
    }
}
struct SilIstegi: Identifiable {
    let id = UUID()
    let ad: String
    let sil: () -> Void
}
struct SilOnayi: ViewModifier {
    @Binding var istek: SilIstegi?
    func body(content: Content) -> some View {
        content.alert("“\(istek?.ad ?? "")” silinsin mi?", isPresented: Binding(get: { istek != nil }, set: { if !$0 { istek = nil } })) {
            Button("Sil", role: .destructive) { istek?.sil() }
            Button("Vazgeç", role: .cancel) {}
        }
    }
}
extension View {
    func adSorusu(_ istek: Binding<AdIstegi?>) -> some View { modifier(AdSorusu(istek: istek)) }
    func silOnayi(_ istek: Binding<SilIstegi?>) -> some View { modifier(SilOnayi(istek: istek)) }
}

// Cam yuvarlak "+" düğmesi
struct EkleDugmesi: View {
    let ad: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus").font(.system(size: 13, weight: .bold))
            Text(ad).font(Tema.yazi(13, .semibold))
        }
        .foregroundStyle(Tema.murekkep).padding(.horizontal, 14).frame(height: 36).camYuzey(18)
    }
}

// Okuyucudaki çizimleri sayfalara işleyip tek PDF yapar (paylaşmak için)
enum PdfPaylas {
    static func uret(belge: PDFDocument, cizimler: [String: Data], anahtar: (PDFPage) -> String?, ad: String) -> URL? {
        let temiz = ad.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(temiz + ".pdf")
        let r = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: PdfUretici.sayfaGenislik, height: PdfUretici.enAzYukseklik))
        do {
            try r.writePDF(to: url) { ctx in
                for i in 0..<belge.pageCount {
                    guard let p = belge.page(at: i) else { continue }
                    let b = p.bounds(for: .mediaBox)
                    ctx.beginPage(withBounds: b, pageInfo: [:])
                    let c = ctx.cgContext
                    c.saveGState(); c.translateBy(x: 0, y: b.height); c.scaleBy(x: 1, y: -1)
                    p.draw(with: .mediaBox, to: c)
                    c.restoreGState()
                    if let k = anahtar(p), let d = cizimler[k], let cizim = try? PKDrawing(data: d) {
                        UITraitCollection(userInterfaceStyle: .light).performAsCurrent { cizim.image(from: b, scale: 2).draw(in: b) }
                    }
                }
            }
            return url
        } catch { Tani.yaz("PDF paylaşım", error.localizedDescription); return nil }
    }
}
