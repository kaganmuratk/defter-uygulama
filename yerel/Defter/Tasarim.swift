import SwiftUI
import UIKit
import PDFKit

// Defter'in görsel dili: "laboratuvar defteri".
// Sıcak kâğıt zemin + mürekkep siyahı + tek elektrik mavisi vurgu; editoryal serif başlıklar (New York),
// monospace küçük etiketler, iri numaralar; boş alanlarda mühendis defteri gibi noktalı ızgara.
enum Tema {
    static let vurguUI = UIColor { $0.userInterfaceStyle == .dark ? UIColor(onaltilik: "7b8cff") : UIColor(onaltilik: "2342f5") }
    static let zeminUI = UIColor { $0.userInterfaceStyle == .dark ? UIColor(onaltilik: "121214") : UIColor(onaltilik: "f3f1ea") }
    static let masaUI = UIColor { $0.userInterfaceStyle == .dark ? UIColor(onaltilik: "1a1a1e") : UIColor(onaltilik: "e8e5db") }
    static let kartUI = UIColor { $0.userInterfaceStyle == .dark ? UIColor(onaltilik: "1d1d22") : UIColor(onaltilik: "fffefa") }
    static let murekkepUI = UIColor { $0.userInterfaceStyle == .dark ? UIColor(onaltilik: "eceae4") : UIColor(onaltilik: "16161a") }
    static let soykUI = UIColor { $0.userInterfaceStyle == .dark ? UIColor(onaltilik: "8e8c86") : UIColor(onaltilik: "77746c") }
    static let cizgiUI = UIColor { $0.userInterfaceStyle == .dark ? UIColor(onaltilik: "2c2c33") : UIColor(onaltilik: "dcd8cc") }
    static let noktaUI = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.07) : UIColor(onaltilik: "16161a", alfa: 0.11) }

    static let vurgu = Color(vurguUI), zemin = Color(zeminUI), masa = Color(masaUI), kart = Color(kartUI)
    static let murekkep = Color(murekkepUI), soluk = Color(soykUI), cizgi = Color(cizgiUI), nokta = Color(noktaUI)

    static func baslik(_ boy: CGFloat, _ agirlik: Font.Weight = .bold) -> Font { .system(size: boy, weight: agirlik, design: .serif) }
    static func etiket(_ boy: CGFloat = 12, _ agirlik: Font.Weight = .semibold) -> Font { .system(size: boy, weight: agirlik, design: .monospaced) }

    // PDF görünümünün arka planı: noktalı defter deseni (yatayda kenarlar boş kalmasın)
    static func noktaliDesen(stil: UIUserInterfaceStyle) -> UIColor {
        let aralik: CGFloat = 22
        let r = UIGraphicsImageRenderer(size: CGSize(width: aralik, height: aralik))
        let img = r.image { c in
            let tc = UITraitCollection(userInterfaceStyle: stil)
            masaUI.resolvedColor(with: tc).setFill(); c.fill(CGRect(x: 0, y: 0, width: aralik, height: aralik))
            noktaUI.resolvedColor(with: tc).withAlphaComponent(stil == .dark ? 0.09 : 0.16).setFill()
            c.cgContext.fillEllipse(in: CGRect(x: aralik / 2 - 1, y: aralik / 2 - 1, width: 2, height: 2))
        }
        return UIColor(patternImage: img)
    }
}

// Noktalı ızgara zemin (SwiftUI)
struct NoktaliZemin: View {
    var body: some View {
        ZStack {
            Tema.zemin
            Canvas { c, boy in
                let aralik: CGFloat = 24
                var y: CGFloat = aralik / 2
                while y < boy.height {
                    var x: CGFloat = aralik / 2
                    while x < boy.width { c.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(Tema.nokta)); x += aralik }
                    y += aralik
                }
            }
        }
        .ignoresSafeArea()
    }
}

// Monospace küçük başlık: "— KİTAPLAR" gibi
struct Etiket: View {
    let yazi: String
    var renk: Color = Tema.soluk
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(renk).frame(width: 14, height: 1.5)
            Text(yazi.uppercased(with: Locale(identifier: "tr_TR"))).font(Tema.etiket(12)).tracking(1.6).foregroundStyle(renk)
        }
    }
}

// Kitap kapağı: görsel yerine tipografi ve ölçü çizgileriyle üretilen özgün kapak
struct KitapKapagi: View {
    let ders: Ders
    let sira: Int
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(sira % 2 == 0 ? Tema.vurgu : Tema.murekkep)
                // Sırt
                Rectangle().fill(Color.black.opacity(0.18)).frame(width: 9)
                // Ölçü çizgileri (laboratuvar defteri kapağı)
                VStack(spacing: 7) {
                    ForEach(0..<6, id: \.self) { _ in Rectangle().fill(Color.white.opacity(0.16)).frame(height: 1) }
                }
                .padding(.leading, 26).padding(.trailing, 16).padding(.top, g.size.height * 0.56)
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: "%02d", sira + 1)).font(Tema.etiket(13, .bold)).foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    Text(ders.baslik).font(Tema.baslik(min(30, g.size.width * 0.17), .heavy)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.6)
                    if let k = ders.kaynak { Text(k.uppercased(with: Locale(identifier: "tr_TR"))).font(Tema.etiket(10, .bold)).tracking(1.4).foregroundStyle(.white.opacity(0.7)) }
                }
                .padding(.leading, 26).padding(.trailing, 14).padding(.vertical, 16)
            }
        }
        .aspectRatio(0.7, contentMode: .fit)
        .shadow(color: .black.opacity(0.18), radius: 10, x: 4, y: 8)
    }
}

// PDF önbelleğinden bir sayfanın küçük resmi (kütüphanede "kaldığın yer" önizlemesi)
enum SayfaOnizleme {
    static func resim(partId: String, bolumSira: Int?, boy: CGSize) -> UIImage? {
        guard let dosyalar = try? FileManager.default.contentsOfDirectory(at: Depo.pdfler, includingPropertiesForKeys: nil),
              let pdf = dosyalar.first(where: { $0.lastPathComponent.hasPrefix(partId + "-") && $0.pathExtension == "pdf" }),
              let doc = PDFDocument(url: pdf) else { return nil }
        var i = 0
        if let sira = bolumSira, let bilgi = Depo.oku([SayfaBilgi].self, pdf.deletingPathExtension().appendingPathExtension("json")),
           let j = bilgi.firstIndex(where: { $0.bolumSira == sira }) { i = j }
        return doc.page(at: i)?.thumbnail(of: boy, for: .mediaBox)
    }
}
