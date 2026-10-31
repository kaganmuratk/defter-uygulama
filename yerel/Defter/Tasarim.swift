import SwiftUI
import UIKit
import PDFKit
import CoreText

// Defter'in görsel dili: terracotta-erik atmosferi (koyu) ve şeftali-krem atmosferi (açık).
// Yazı tipleri: Literata (başlık ve okuma) + Plus Jakarta Sans (arayüz). Kartlar ve düğmeler bulanık cam.
// Zeminde Codex'in ürettiği fırça darbeli genel arka plan; kart ya da başlık başına görsel yok.

// Ayarlar → Görünüm
enum TemaSecimi: String, CaseIterable, Identifiable {
    case otomatik, acik, koyu
    var id: String { rawValue }
    var ad: String { switch self { case .otomatik: return "Otomatik"; case .acik: return "Açık"; case .koyu: return "Koyu" } }
    var sema: ColorScheme? { switch self { case .otomatik: return nil; case .acik: return .light; case .koyu: return .dark } }
}

enum Tema {
    private static func dinamik(_ acik: String, _ koyu: String, acikA: CGFloat = 1, koyuA: CGFloat = 1) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(onaltilik: koyu, alfa: koyuA) : UIColor(onaltilik: acik, alfa: acikA) }
    }
    // Metin ve yüzeyler
    static let murekkepUI = dinamik("3d211c", "fbefe6")
    static let soykUI = dinamik("3d211c", "fbefe6", acikA: 0.72, koyuA: 0.74)
    static let camDolguUI = dinamik("ffffff", "fff4ec", acikA: 0.46, koyuA: 0.15)
    static let camKenarUI = dinamik("ffffff", "fff4ec", acikA: 0.75, koyuA: 0.30)
    static let camVurguUI = dinamik("ffffff", "fff4ec", acikA: 0.7, koyuA: 0.2)
    static let dolguUI = dinamik("3d211c", "fbefe6")          // dolu daire, ilerleme çubuğu, birincil düğme
    static let dolguUstuUI = dinamik("fbefe6", "4a2a25")      // dolgunun üstündeki yazı
    static let zeminUI = dinamik("f6e1d3", "5c3a47")
    static let masaUI = dinamik("efd3c3", "4a2d36")
    static let kartUI = UIColor(onaltilik: "fff9f4")           // beyaz "kalınan yer" satırı: iki modda da beyaz
    static let kartYaziUI = UIColor(onaltilik: "3d211c")
    static let vurguUI = UIColor(onaltilik: "b4553a")          // tek vurgu: terracotta
    static let cizgiUI = camKenarUI
    static let noktaUI = UIColor(white: 1, alpha: 0.07)

    static let murekkep = Color(murekkepUI), soluk = Color(soykUI), cam = Color(camDolguUI), camKenar = Color(camKenarUI), camVurgu = Color(camVurguUI)
    static let dolgu = Color(dolguUI), dolguUstu = Color(dolguUstuUI), zemin = Color(zeminUI), masa = Color(masaUI)
    static let kart = Color(kartUI), kartYazi = Color(kartYaziUI), vurgu = Color(vurguUI), cizgi = Color(cizgiUI), nokta = Color(noktaUI)

    // Yazı tipleri (değişken yazı tipleri: ağırlık ekseni elle ayarlanır; kayıtlı değilse sistem yazı tipine düşer)
    private static func agirlikDegeri(_ a: Font.Weight) -> CGFloat {
        switch a {
        case .ultraLight: return 200
        case .thin: return 250
        case .light: return 300
        case .regular: return 400
        case .medium: return 500
        case .semibold: return 600
        case .bold: return 700
        case .heavy: return 800
        default: return 900
        }
    }
    static func uiYazi(_ aile: String, _ boy: CGFloat, _ agirlik: CGFloat) -> UIFont {
        let eksen = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let d = UIFontDescriptor(fontAttributes: [.family: aile]).addingAttributes([eksen: [2003265652: agirlik]])   // 'wght'
        let f = UIFont(descriptor: d, size: boy)
        if f.familyName.hasPrefix(String(aile.prefix(5))) { return f }
        return UIFont.systemFont(ofSize: boy, weight: UIFont.Weight(rawValue: (agirlik - 400) / 500))
    }
    static func baslik(_ boy: CGFloat, _ agirlik: Font.Weight = .semibold) -> Font { Font(uiYazi("Literata", boy, agirlikDegeri(agirlik)) as CTFont) }
    static func yazi(_ boy: CGFloat, _ agirlik: Font.Weight = .regular) -> Font { Font(uiYazi("Plus Jakarta Sans", boy, agirlikDegeri(agirlik)) as CTFont) }
    static func etiket(_ boy: CGFloat = 12, _ agirlik: Font.Weight = .semibold) -> Font { yazi(boy, agirlik) }
    static func uiBaslik(_ boy: CGFloat, _ agirlik: CGFloat = 600) -> UIFont { uiYazi("Literata", boy, agirlik) }
    static func uiArayuz(_ boy: CGFloat, _ agirlik: CGFloat = 500) -> UIFont { uiYazi("Plus Jakarta Sans", boy, agirlik) }
}

// Genel arka plan: fırça darbeli atmosfer + ince tane. Üstüne kartlar camla oturur.
struct Atmosfer: View {
    @Environment(\.colorScheme) private var sema
    var body: some View {
        GeometryReader { g in
            ZStack {
                (sema == .dark ? Color(UIColor(onaltilik: "8a5646")) : Color(UIColor(onaltilik: "f6e1d3")))
                Image(sema == .dark ? "AtmosferKoyu" : "AtmosferAcik").resizable().scaledToFill()
                    .frame(width: g.size.width, height: g.size.height).clipped()
                if sema == .dark {
                    LinearGradient(colors: [.clear, Color(red: 0.16, green: 0.06, blue: 0.09).opacity(0.5)], startPoint: UnitPoint(x: 0.5, y: 0.4), endPoint: .bottom)
                    RadialGradient(colors: [Color(red: 0.29, green: 0.12, blue: 0.10).opacity(0.5), .clear], center: .topTrailing, startRadius: 0, endRadius: g.size.width * 0.5)
                } else {
                    LinearGradient(colors: [.clear, Color(red: 0.94, green: 0.80, blue: 0.75).opacity(0.35)], startPoint: UnitPoint(x: 0.5, y: 0.5), endPoint: .bottom)
                }
                Image("Gren").resizable(resizingMode: .tile).blendMode(.overlay).opacity(0.26).allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

// Eski ad: noktalı zemin yerine artık atmosfer
struct NoktaliZemin: View { var body: some View { Atmosfer() } }

// Bulanık, yarı saydam cam yüzey
struct CamYuzey: ViewModifier {
    var yaricap: CGFloat
    var vurgulu = false
    func body(content: Content) -> some View {
        let sekil = RoundedRectangle(cornerRadius: yaricap, style: .continuous)
        content
            .background(.ultraThinMaterial, in: sekil)
            .background(vurgulu ? Tema.camVurgu : Tema.cam, in: sekil)
            .overlay(sekil.strokeBorder(Tema.camKenar, lineWidth: 1))
            .shadow(color: Color(red: 0.12, green: 0.03, blue: 0.03).opacity(0.22), radius: 16, x: 0, y: 10)
    }
}
extension View {
    func camYuzey(_ yaricap: CGFloat = 24, vurgulu: Bool = false) -> some View { modifier(CamYuzey(yaricap: yaricap, vurgulu: vurgulu)) }
}

// Küçük başlık (eski adı korunur): "Kitaplar", "Bölümler" gibi
struct Etiket: View {
    let yazi: String
    var renk: Color = Tema.murekkep
    var body: some View { Text(yazi).font(Tema.yazi(15, .semibold)).foregroundStyle(renk) }
}

// Kitap kapağı: genel atmosfer görseli kırpılır, sırt gölgesi ve parıltı eklenir, ad cam etiketle üstte durur
struct KitapKapagi: View {
    let ders: Ders
    let sira: Int
    @Environment(\.colorScheme) private var sema
    var body: some View {
        let sekil = UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8, bottomTrailingRadius: 22, topTrailingRadius: 22, style: .continuous)
        GeometryReader { g in
            ZStack(alignment: .bottomLeading) {
                Image(sema == .dark ? "AtmosferKoyu" : "AtmosferAcik").resizable().scaledToFill()
                    .frame(width: g.size.width, height: g.size.height).clipped()
                RadialGradient(colors: [Color(red: 1, green: 0.92, blue: 0.84).opacity(0.55), .clear], center: .topTrailing, startRadius: 0, endRadius: g.size.width * 0.8)
                LinearGradient(colors: [Color.black.opacity(0.30), Color.white.opacity(0.10), .clear], startPoint: .leading, endPoint: UnitPoint(x: 0.12, y: 0.5))
                VStack(alignment: .leading, spacing: 4) {
                    Text(ders.baslik).font(Tema.baslik(min(24, g.size.width * 0.105), .semibold)).foregroundStyle(Tema.murekkep).lineLimit(2).minimumScaleFactor(0.7)
                    if let k = ders.kaynak { Text(k).font(Tema.yazi(12)).foregroundStyle(Tema.soluk).lineLimit(1) }
                }
                .padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                .camYuzey(16)
                .padding(.leading, 20).padding(.trailing, 10).padding(.bottom, 10)
            }
            .clipShape(sekil)
            .overlay(sekil.strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        }
        .aspectRatio(0.76, contentMode: .fit)
        .shadow(color: Color(red: 0.12, green: 0.03, blue: 0.03).opacity(0.4), radius: 18, x: 0, y: 14)
    }
}

// İnce ilerleme çubuğu
struct IlerlemeCubugu: View {
    let biten: Int; let toplam: Int
    var etiketGoster = true
    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tema.soluk.opacity(0.3))
                    Capsule().fill(Tema.dolgu).frame(width: toplam > 0 ? max(5, g.size.width * CGFloat(biten) / CGFloat(toplam)) : 0).opacity(biten > 0 ? 1 : 0)
                }
            }.frame(height: 4)
            if etiketGoster { Text("\(biten)/\(toplam)").font(Tema.yazi(12, .semibold)).foregroundStyle(Tema.soluk).monospacedDigit() }
        }
    }
}

// PDF önbelleğinden bir sayfanın küçük resmi
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
