import SwiftUI
import UIKit
import PDFKit
import CoreText

// Defter'in görsel dili: "Tuz ve Mürekkep". Zemin buz mavisi (koyuda gece laciverti), yazı lacivert,
// tek vurgu mercan pembesi (rehber: iki taban rengi + şaşırtan tek vurgu). Zeminde yumuşak renkli ışık lekeleri,
// kartlar ince beyaz cam, kitap kapakları palet gradyanları. Yazı tipleri: Literata (başlık, okuma) + Plus Jakarta Sans (arayüz).

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
    // Metin ve yüzeyler (açık: buz mavisi zemin + lacivert yazı; koyu: gece laciverti zemin + açık mavi yazı)
    static let murekkepUI = dinamik("072d59", "e6f5fd")
    static let soykUI = dinamik("072d59", "e6f5fd", acikA: 0.68, koyuA: 0.72)
    static let camDolguUI = dinamik("ffffff", "dbf2fc", acikA: 0.58, koyuA: 0.09)
    static let camKenarUI = dinamik("ffffff", "dbf2fc", acikA: 0.90, koyuA: 0.22)
    static let camVurguUI = dinamik("ffffff", "dbf2fc", acikA: 0.82, koyuA: 0.16)
    static let dolguUI = dinamik("072d59", "dbf2fc")          // dolu daire, ilerleme çubuğu, birincil düğme
    static let dolguUstuUI = dinamik("dbf2fc", "06162c")      // dolgunun üstündeki yazı
    static let zeminUI = dinamik("dbf2fc", "06162c")
    static let masaUI = dinamik("c7e6f6", "0a2342")
    static let kartUI = dinamik("072d59", "123c70")            // vurgulu "kalınan yer" kartı: lacivert
    static let kartYaziUI = dinamik("dbf2fc", "e6f5fd")
    static let vurguUI = dinamik("e8456b", "fd6e88")           // tek vurgu: mercan pembesi
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

// Genel arka plan: buz mavisi (koyuda gece laciverti) üstünde yumuşak pembe, deniz mavisi ve turkuaz ışık lekeleri + ince tane
struct Atmosfer: View {
    @Environment(\.colorScheme) private var sema
    var body: some View {
        GeometryReader { g in
            let b = max(g.size.width, g.size.height)
            let koyu = sema == .dark
            ZStack {
                Color(koyu ? UIColor(onaltilik: "06162c") : UIColor(onaltilik: "dbf2fc"))
                RadialGradient(colors: [Color(UIColor(onaltilik: "5aa9e6")).opacity(koyu ? 0.30 : 0.38), .clear], center: UnitPoint(x: 0.22, y: 0.20), startRadius: 0, endRadius: b * 0.55)
                RadialGradient(colors: [Color(UIColor(onaltilik: "fd6e88")).opacity(koyu ? 0.26 : 0.30), .clear], center: UnitPoint(x: 0.98, y: 0.04), startRadius: 0, endRadius: b * 0.62)
                RadialGradient(colors: [Color(UIColor(onaltilik: "74ffed")).opacity(koyu ? 0.14 : 0.40), .clear], center: UnitPoint(x: 0.02, y: 0.98), startRadius: 0, endRadius: b * 0.6)
                RadialGradient(colors: [Color(UIColor(onaltilik: "6331fb")).opacity(koyu ? 0.22 : 0.10), .clear], center: UnitPoint(x: 0.85, y: 0.95), startRadius: 0, endRadius: b * 0.5)
                Image("Gren").resizable(resizingMode: .tile).blendMode(.overlay).opacity(koyu ? 0.18 : 0.12).allowsHitTesting(false)
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
            .shadow(color: Color(red: 0.03, green: 0.15, blue: 0.35).opacity(0.16), radius: 18, x: 0, y: 10)
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

// Kitap kapağı: paletten bir gradyan (kitap kimliğinden kararlı seçilir), ışık, ince halkalar, sırt gölgesi; ad cam etiketle altta durur
struct KitapKapagi: View {
    let ders: Ders
    let sira: Int
    private static let renkler: [(String, String)] = [("072d59", "2f6fe0"), ("fd6e88", "ffa07a"), ("0f8f9a", "74ffed"), ("5b2be0", "9a7bff"), ("015d47", "3dbb8c"), ("e8650c", "ffb066")]
    private var cift: (String, String) {
        let t = ders.id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff }
        return Self.renkler[t % Self.renkler.count]
    }
    var body: some View {
        let sekil = UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8, bottomTrailingRadius: 22, topTrailingRadius: 22, style: .continuous)
        let c = cift
        GeometryReader { g in
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Color(UIColor(onaltilik: c.0)), Color(UIColor(onaltilik: c.1))], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color.white.opacity(0.42), .clear], center: .topTrailing, startRadius: 0, endRadius: g.size.width * 0.9)
                Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1.2).frame(width: g.size.width * 1.1).offset(x: g.size.width * 0.28, y: -g.size.height * 0.16)
                Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1.2).frame(width: g.size.width * 0.7).offset(x: g.size.width * 0.4, y: -g.size.height * 0.02)
                Image("Gren").resizable(resizingMode: .tile).blendMode(.overlay).opacity(0.35).allowsHitTesting(false)
                LinearGradient(colors: [Color.black.opacity(0.30), Color.white.opacity(0.08), .clear], startPoint: .leading, endPoint: UnitPoint(x: 0.12, y: 0.5))
                VStack(alignment: .leading, spacing: 4) {
                    Text(ders.baslik).font(Tema.baslik(min(24, g.size.width * 0.105), .semibold)).foregroundStyle(Tema.murekkep).lineLimit(2).minimumScaleFactor(0.7)
                    if let k = ders.kaynak { Text(k).font(Tema.yazi(12)).foregroundStyle(Tema.soluk).lineLimit(1) }
                }
                .padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                .camYuzey(16)
                .padding(.leading, 20).padding(.trailing, 10).padding(.bottom, 10)
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipShape(sekil)
            .overlay(sekil.strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
        }
        .aspectRatio(0.76, contentMode: .fit)
        .shadow(color: Color(red: 0.03, green: 0.15, blue: 0.35).opacity(0.32), radius: 18, x: 0, y: 14)
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
