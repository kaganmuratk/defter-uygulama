import UIKit
import Vision
import PencilKit
import SwiftUI

// Yazı kutusu: sayfaya yazılı (klavyeyle) metin. Taşınır, genişliği değişir; yazı tipi, boyut, kalınlık ve renk seçilir.
// Seçim aracından "metne çevir" ile el yazısı bu kutuya dönüştürülebilir.
enum YaziTipi {
    static let secenekler: [(String, String)] = [("jakarta", "Düz"), ("literata", "Kitap"), ("georgia", "Klasik"), ("menlo", "Kod"), ("el", "El yazısı")]
    static func font(_ ad: String, _ boyut: CGFloat, kalin: Bool) -> UIFont {
        switch ad {
        case "literata": return Tema.uiYazi("Literata", boyut, kalin ? 700 : 400)
        case "georgia": return UIFont(name: kalin ? "Georgia-Bold" : "Georgia", size: boyut) ?? .systemFont(ofSize: boyut, weight: kalin ? .bold : .regular)
        case "menlo": return UIFont(name: kalin ? "Menlo-Bold" : "Menlo-Regular", size: boyut) ?? .monospacedSystemFont(ofSize: boyut, weight: kalin ? .bold : .regular)
        case "el": return UIFont(name: "BradleyHandITCTT-Bold", size: boyut) ?? .italicSystemFont(ofSize: boyut)
        default: return Tema.uiYazi("Plus Jakarta Sans", boyut, kalin ? 700 : 400)
        }
    }
}

final class YaziKutusuGorunumu: UIView, UITextViewDelegate {
    private(set) var model: YaziKutusu
    var degisti: ((YaziKutusu) -> Void)?
    var silindi: ((String) -> Void)?
    var olcek: CGFloat = 1 { didSet { yerlestir() } }
    private let metin = UITextView()
    private let tutamac = UIView()          // üst kenar: sürükleyerek taşı
    private let boyutTutamaci = UIView()    // sağ alt köşe: genişlik
    private let cerceve = CAShapeLayer()
    private let cubuk = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let cubukSira = UIStackView()
    private static let tutamacYuksekligi: CGFloat = 16

    init(model: YaziKutusu) {
        self.model = model
        super.init(frame: .zero)
        accessibilityIdentifier = "yazi-kutusu"
        metin.backgroundColor = .clear
        metin.isScrollEnabled = false
        metin.textContainerInset = UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        metin.delegate = self
        metin.accessibilityIdentifier = "yazi-metni"
        metin.autocorrectionType = .no
        addSubview(metin)
        cerceve.strokeColor = Tema.vurguUI.cgColor; cerceve.fillColor = UIColor.clear.cgColor
        cerceve.lineDashPattern = [6, 4]; cerceve.lineWidth = 1.5; cerceve.isHidden = true
        layer.addSublayer(cerceve)

        tutamac.backgroundColor = Tema.vurguUI.withAlphaComponent(0.85)
        tutamac.layer.cornerRadius = 6
        let grip = UIImageView(image: UIImage(systemName: "line.3.horizontal", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)))
        grip.tintColor = .white; grip.contentMode = .center; grip.frame = CGRect(x: 0, y: 0, width: 40, height: Self.tutamacYuksekligi)
        tutamac.addSubview(grip)
        tutamac.isHidden = true
        tutamac.accessibilityIdentifier = "yazi-tasi"
        tutamac.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(tasiJesti(_:))))
        addSubview(tutamac)
        boyutTutamaci.backgroundColor = .white
        boyutTutamaci.layer.cornerRadius = 11; boyutTutamaci.layer.borderWidth = 3; boyutTutamaci.layer.borderColor = Tema.vurguUI.cgColor
        boyutTutamaci.isHidden = true
        boyutTutamaci.accessibilityIdentifier = "yazi-boyut"
        boyutTutamaci.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(boyutJesti(_:))))
        addSubview(boyutTutamaci)

        cubuk.layer.cornerRadius = 20; cubuk.layer.cornerCurve = .continuous; cubuk.clipsToBounds = true
        cubuk.layer.borderWidth = 1; cubuk.layer.borderColor = Tema.camKenarUI.cgColor
        cubuk.contentView.backgroundColor = Tema.camDolguUI
        cubukSira.spacing = 2; cubukSira.alignment = .center
        cubukSira.translatesAutoresizingMaskIntoConstraints = false
        cubuk.contentView.addSubview(cubukSira)
        NSLayoutConstraint.activate([
            cubukSira.leadingAnchor.constraint(equalTo: cubuk.contentView.leadingAnchor, constant: 8), cubukSira.trailingAnchor.constraint(equalTo: cubuk.contentView.trailingAnchor, constant: -8),
            cubukSira.topAnchor.constraint(equalTo: cubuk.contentView.topAnchor, constant: 4), cubukSira.bottomAnchor.constraint(equalTo: cubuk.contentView.bottomAnchor, constant: -4),
        ])
        cubuk.isHidden = true
        addSubview(cubuk)
        cubukDugmeleri()
        gorunumuYenile()
    }
    required init?(coder: NSCoder) { fatalError() }

    func duzenle() { metin.becomeFirstResponder() }

    // MARK: Görünüm
    private func gorunumuYenile() {
        metin.font = YaziTipi.font(model.yazi, CGFloat(model.boyut), kalin: model.kalin)
        metin.textColor = UIColor(onaltilik: model.renk)
        metin.text = model.metin
        boyutlandir()
    }
    /// Genişlik sabit, yükseklik metne göre
    private func boyutlandir() {
        let g = CGFloat(model.genislik)
        let h = metin.sizeThatFits(CGSize(width: g, height: .greatestFiniteMagnitude)).height
        frame = CGRect(x: CGFloat(model.x), y: CGFloat(model.y), width: g, height: max(h, 36) + Self.tutamacYuksekligi)
        yerlestir()
    }
    private func yerlestir() {
        let ters = 1 / max(olcek, 0.3)
        metin.frame = CGRect(x: 0, y: Self.tutamacYuksekligi, width: bounds.width, height: max(bounds.height - Self.tutamacYuksekligi, 0))
        tutamac.frame = CGRect(x: bounds.midX - 22, y: 0, width: 44, height: Self.tutamacYuksekligi)
        boyutTutamaci.transform = .identity
        boyutTutamaci.frame = CGRect(x: 0, y: 0, width: 22, height: 22)
        boyutTutamaci.center = CGPoint(x: bounds.width - 6, y: bounds.height - 6)
        boyutTutamaci.transform = CGAffineTransform(scaleX: ters, y: ters)
        cerceve.frame = bounds
        cerceve.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerRadius: 6).cgPath
        cubugu_yerlestir()
    }
    private func cubugu_yerlestir() {
        guard !cubuk.isHidden else { return }
        let ters = 1 / max(olcek, 0.3)
        cubuk.transform = .identity
        let w = cubukSira.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width + 16
        cubuk.bounds = CGRect(x: 0, y: 0, width: max(w, 200), height: 44)
        cubuk.center = CGPoint(x: min(max(bounds.midX, cubuk.bounds.width * ters / 2), max(bounds.width, cubuk.bounds.width * ters)), y: -(26 + 8) * ters)
        cubuk.transform = CGAffineTransform(scaleX: ters, y: ters)
    }
    private func secimDurumu(_ a: Bool) {
        cerceve.isHidden = !a; tutamac.isHidden = !a; boyutTutamaci.isHidden = !a; cubuk.isHidden = !a
        if a { cubugu_yerlestir() }
    }

    // MARK: Metin düzenleme
    func textViewDidBeginEditing(_ textView: UITextView) { secimDurumu(true) }
    func textViewDidEndEditing(_ textView: UITextView) {
        secimDurumu(false)
        if model.metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { silindi?(model.id); removeFromSuperview() }
    }
    func textViewDidChange(_ textView: UITextView) {
        model.metin = textView.text
        let g = CGFloat(model.genislik)
        let h = textView.sizeThatFits(CGSize(width: g, height: .greatestFiniteMagnitude)).height
        frame.size.height = max(h, 36) + Self.tutamacYuksekligi
        yerlestir()
        degisti?(model)
    }

    // MARK: Taşı / genişlet
    @objc private func tasiJesti(_ g: UIPanGestureRecognizer) {
        guard let ust = superview else { return }
        let t = g.translation(in: ust); g.setTranslation(.zero, in: ust)
        frame.origin.x = min(max(frame.origin.x + t.x, 0), max(ust.bounds.width - 60, 0))
        frame.origin.y = min(max(frame.origin.y + t.y, 0), max(ust.bounds.height - 40, 0))
        model.x = Double(frame.origin.x); model.y = Double(frame.origin.y)
        if g.state == .ended { degisti?(model) }
    }
    @objc private func boyutJesti(_ g: UIPanGestureRecognizer) {
        guard let ust = superview else { return }
        let t = g.translation(in: ust); g.setTranslation(.zero, in: ust)
        let yeni = min(max(CGFloat(model.genislik) + t.x, 90), max(ust.bounds.width - frame.origin.x - 8, 90))
        model.genislik = Double(yeni)
        let h = metin.sizeThatFits(CGSize(width: yeni, height: .greatestFiniteMagnitude)).height
        frame.size = CGSize(width: yeni, height: max(h, 36) + Self.tutamacYuksekligi)
        yerlestir()
        if g.state == .ended { degisti?(model) }
    }

    // MARK: Biçim çubuğu
    private func cubukDugmeleri() {
        func dugme(_ sembol: String, _ ad: String, _ kimlik: String, kirmizi: Bool = false, _ eylem: @escaping () -> Void) -> UIButton {
            let b = UIButton(type: .system, primaryAction: UIAction { _ in eylem() })
            b.setImage(UIImage(systemName: sembol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)), for: .normal)
            b.tintColor = kirmizi ? .systemRed : Tema.murekkepUI
            b.accessibilityLabel = ad; b.accessibilityIdentifier = kimlik
            b.widthAnchor.constraint(equalToConstant: 38).isActive = true
            b.heightAnchor.constraint(equalToConstant: 34).isActive = true
            return b
        }
        let tip = UIButton(type: .system)
        tip.setImage(UIImage(systemName: "textformat", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)), for: .normal)
        tip.tintColor = Tema.murekkepUI; tip.showsMenuAsPrimaryAction = true
        tip.accessibilityLabel = "Yazı tipi"; tip.accessibilityIdentifier = "yazi-tipi"
        tip.menu = UIMenu(title: "Yazı tipi", children: YaziTipi.secenekler.map { (kod, ad) in
            UIAction(title: ad) { [weak self] _ in self?.degistir { $0.yazi = kod } }
        })
        tip.widthAnchor.constraint(equalToConstant: 38).isActive = true; tip.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let renk = UIButton(type: .system)
        renk.setImage(UIImage(systemName: "paintpalette", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)), for: .normal)
        renk.tintColor = Tema.murekkepUI; renk.showsMenuAsPrimaryAction = true
        renk.accessibilityLabel = "Yazı rengi"; renk.accessibilityIdentifier = "yazi-renk"
        renk.menu = UIMenu(title: "Renk", children: KalemPaleti.kalem.map { (ad, hex) in
            UIAction(title: ad, image: UIImage(systemName: "circle.fill")?.withTintColor(UIColor(onaltilik: hex), renderingMode: .alwaysOriginal)) { [weak self] _ in self?.degistir { $0.renk = hex } }
        })
        renk.widthAnchor.constraint(equalToConstant: 38).isActive = true; renk.heightAnchor.constraint(equalToConstant: 34).isActive = true
        for v in [tip,
                  dugme("textformat.size.smaller", "Küçült", "yazi-kucult") { [weak self] in self?.degistir { $0.boyut = max($0.boyut - 2, 10) } },
                  dugme("textformat.size.larger", "Büyüt", "yazi-buyut") { [weak self] in self?.degistir { $0.boyut = min($0.boyut + 2, 72) } },
                  dugme("bold", "Kalın", "yazi-kalin") { [weak self] in self?.degistir { $0.kalin.toggle() } },
                  renk,
                  dugme("trash", "Kutuyu sil", "yazi-sil", kirmizi: true) { [weak self] in
                      guard let self else { return }
                      self.model.metin = ""; self.silindi?(self.model.id); self.metin.resignFirstResponder(); self.removeFromSuperview()
                  }] as [UIView] { cubukSira.addArrangedSubview(v) }
    }
    private func degistir(_ f: (inout YaziKutusu) -> Void) {
        f(&model)
        metin.font = YaziTipi.font(model.yazi, CGFloat(model.boyut), kalin: model.kalin)
        metin.textColor = UIColor(onaltilik: model.renk)
        let g = CGFloat(model.genislik)
        let h = metin.sizeThatFits(CGSize(width: g, height: .greatestFiniteMagnitude)).height
        frame.size.height = max(h, 36) + Self.tutamacYuksekligi
        yerlestir()
        degisti?(model)
    }

    // Biçim çubuğu kutunun dışında durur; dokunuşlar ona da ulaşsın
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if !cubuk.isHidden, let v = cubuk.hitTest(convert(point, to: cubuk), with: event) { return v }
        return super.hitTest(point, with: event)
    }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if !cubuk.isHidden, cubuk.frame.contains(point) { return true }
        return super.point(inside: point, with: event)
    }
}

// MARK: El yazısını metne çevirme (Vision)
enum MetinTanima {
    /// Görüntüdeki metni tanır; tamam(metin, kullanılanDiller) ana iş parçacığında çağrılır.
    /// Tek harf ve kısa yazılar için üç deneme yapılır: (1) doğru + dil düzeltmeli, (2) dil düzeltmesiz, (3) hızlı mod.
    static func tani(_ resim: UIImage, tamam: @escaping (String?, String) -> Void) {
        guard let cg = resim.cgImage else { tamam(nil, ""); return }
        DispatchQueue.global(qos: .userInitiated).async {
            var notDiller = ""
            var sonuc: String?
            let denemeler: [(Bool, VNRequestTextRecognitionLevel)] = [(true, .accurate), (false, .accurate), (false, .fast)]
            for (duzeltme, seviye) in denemeler {
                let istek = VNRecognizeTextRequest()
                istek.recognitionLevel = seviye
                istek.usesLanguageCorrection = duzeltme
                istek.minimumTextHeight = 0
                let destek = (try? istek.supportedRecognitionLanguages()) ?? []
                let diller = destek.contains("tr-TR") ? ["tr-TR", "en-US"] : ["en-US"]
                istek.recognitionLanguages = diller
                notDiller = diller.joined(separator: ",") + (destek.contains("tr-TR") ? "" : " (tr-TR desteklenmiyor)")
                guard (try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([istek])) != nil else { continue }
                let gozlemler = ((istek.results as? [VNRecognizedTextObservation]) ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                let satirlar = gozlemler.compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if !satirlar.isEmpty { sonuc = satirlar.joined(separator: "\n"); break }
            }
            DispatchQueue.main.async { tamam(sonuc, notDiller) }
        }
    }

    /// Seçilen çizgileri tanımaya uygun bir görüntüye çevirir: siyah, biraz kalınlaştırılmış, geniş beyaz kenarlı ve büyük
    /// (Vision tek harf ve küçük yazıyı ancak büyük, yüksek kontrastlı ve boşluklu görüntüde tanıyor).
    static func resim(_ cizgiler: [PKStroke], alan: CGRect) -> UIImage {
        let kalin: [PKStroke] = cizgiler.map { s in
            var pts: [PKStrokePoint] = []
            for p in s.path {
                pts.append(PKStrokePoint(location: p.location, timeOffset: p.timeOffset,
                                         size: CGSize(width: max(p.size.width, 2) * 1.6, height: max(p.size.height, 2) * 1.6),
                                         opacity: 1, force: p.force, azimuth: p.azimuth, altitude: p.altitude))
            }
            return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: pts, creationDate: s.path.creationDate), transform: s.transform, mask: s.mask)
        }
        let pay = max(30, max(alan.width, alan.height) * 0.6)
        let genis = alan.insetBy(dx: -pay, dy: -pay)
        let oran = min(max(640 / max(genis.height, 1), 2), 8)
        var img = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent { img = PKDrawing(strokes: kalin).image(from: genis, scale: oran) }
        return UIGraphicsImageRenderer(size: img.size).image { c in
            UIColor.white.setFill(); c.fill(CGRect(origin: .zero, size: img.size)); img.draw(at: .zero)
        }
    }

    /// Eski yöntem (karşılaştırma sınavı için): ince çizgi, dar kenar
    static func resimEski(_ cizgiler: [PKStroke], alan: CGRect) -> UIImage {
        var img = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent { img = PKDrawing(strokes: cizgiler).image(from: alan.insetBy(dx: -16, dy: -16), scale: 3) }
        return UIGraphicsImageRenderer(size: img.size).image { c in
            UIColor.white.setFill(); c.fill(CGRect(origin: .zero, size: img.size)); img.draw(at: .zero)
        }
    }
}

// CI sınavı (-ocrTesti): yazı tipiyle çizilmiş cümle + elle çizilmiş gibi düz çizgilerden harfler (K, L, T, E, H); eski ve yeni yöntemi karşılaştırır
struct OcrSinavEkrani: View {
    @State private var satirlar: [String] = ["çalışıyor…"]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(satirlar, id: \.self) { Text($0).font(.callout.monospaced()) }
        }
        .padding()
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("ocr-sonuc")
        .accessibilityLabel(satirlar.joined(separator: " | "))
        .task { await calistir() }
    }

    private func cizgi(_ noktalar: [CGPoint]) -> PKStroke {
        let pts = noktalar.enumerated().map { (i, p) in
            PKStrokePoint(location: p, timeOffset: Double(i) * 0.02, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: pts, creationDate: Date()))
    }
    private func ara(_ a: CGPoint, _ b: CGPoint, adim: Int = 12) -> [CGPoint] {
        (0...adim).map { CGPoint(x: a.x + (b.x - a.x) * CGFloat($0) / CGFloat(adim), y: a.y + (b.y - a.y) * CGFloat($0) / CGFloat(adim)) }
    }
    private func harf(_ h: String) -> [PKStroke] {
        let o = CGPoint(x: 100, y: 100), g: CGFloat = 70, y: CGFloat = 100
        switch h {
        case "K": return [cizgi(ara(o, CGPoint(x: o.x, y: o.y + y))), cizgi(ara(CGPoint(x: o.x + g, y: o.y), CGPoint(x: o.x, y: o.y + y * 0.55))), cizgi(ara(CGPoint(x: o.x + 10, y: o.y + y * 0.45), CGPoint(x: o.x + g, y: o.y + y)))]
        case "L": return [cizgi(ara(o, CGPoint(x: o.x, y: o.y + y))), cizgi(ara(CGPoint(x: o.x, y: o.y + y), CGPoint(x: o.x + g, y: o.y + y)))]
        case "T": return [cizgi(ara(o, CGPoint(x: o.x + g, y: o.y))), cizgi(ara(CGPoint(x: o.x + g / 2, y: o.y), CGPoint(x: o.x + g / 2, y: o.y + y)))]
        case "H": return [cizgi(ara(o, CGPoint(x: o.x, y: o.y + y))), cizgi(ara(CGPoint(x: o.x + g, y: o.y), CGPoint(x: o.x + g, y: o.y + y))), cizgi(ara(CGPoint(x: o.x, y: o.y + y / 2), CGPoint(x: o.x + g, y: o.y + y / 2)))]
        default: return [cizgi(ara(o, CGPoint(x: o.x + g, y: o.y))), cizgi(ara(o, CGPoint(x: o.x, y: o.y + y))), cizgi(ara(CGPoint(x: o.x, y: o.y + y / 2), CGPoint(x: o.x + g * 0.8, y: o.y + y / 2))), cizgi(ara(CGPoint(x: o.x, y: o.y + y), CGPoint(x: o.x + g, y: o.y + y)))]
        }
    }
    private func tanit(_ r: UIImage) async -> String {
        await withCheckedContinuation { c in MetinTanima.tani(r) { m, _ in c.resume(returning: m ?? "(boş)") } }
    }

    private func calistir() async {
        var cikti: [String] = []
        // 1) Yazı tipiyle çizilmiş cümle
        let f = UIFont(name: "BradleyHandITCTT-Bold", size: 54) ?? .italicSystemFont(ofSize: 54)
        let s = NSAttributedString(string: "Merhaba dünya, bu bir deneme", attributes: [.font: f, .foregroundColor: UIColor.black])
        let r = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 120)).image { c in
            UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: 900, height: 120)); s.draw(at: CGPoint(x: 10, y: 24))
        }
        cikti.append("cümle: " + (await tanit(r)))
        // 2) Çizgilerden harfler: eski ve yeni yöntem
        for h in ["K", "L", "T", "H", "E"] {
            let c = harf(h)
            var alan = c[0].renderBounds
            for x in c.dropFirst() { alan = alan.union(x.renderBounds) }
            let eski = await tanit(MetinTanima.resimEski(c, alan: alan))
            let yeni = await tanit(MetinTanima.resim(c, alan: alan))
            cikti.append("\(h): eski=\(eski) yeni=\(yeni)")
        }
        satirlar = cikti
    }
}
