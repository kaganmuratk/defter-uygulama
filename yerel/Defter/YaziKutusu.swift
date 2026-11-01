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
    /// Görüntüdeki metni tanır; tamam(metin, kullanılanDiller) ana iş parçacığında çağrılır
    static func tani(_ resim: UIImage, tamam: @escaping (String?, String) -> Void) {
        guard let cg = resim.cgImage else { tamam(nil, ""); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let istek = VNRecognizeTextRequest()
            istek.recognitionLevel = .accurate
            istek.usesLanguageCorrection = true
            let destek = (try? istek.supportedRecognitionLanguages()) ?? []
            let diller = destek.contains("tr-TR") ? ["tr-TR", "en-US"] : ["en-US"]
            istek.recognitionLanguages = diller
            let isleyici = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try isleyici.perform([istek]) } catch {
                DispatchQueue.main.async { tamam(nil, diller.joined(separator: ",")) }
                return
            }
            let gozlemler = ((istek.results as? [VNRecognizedTextObservation]) ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            let satirlar = gozlemler.compactMap { $0.topCandidates(1).first?.string }
            let metin = satirlar.isEmpty ? nil : satirlar.joined(separator: "\n")
            DispatchQueue.main.async { tamam(metin, diller.joined(separator: ",") + (destek.contains("tr-TR") ? "" : " (tr-TR desteklenmiyor)")) }
        }
    }

    /// Seçilen çizgileri beyaz zemine çizip tanımaya hazırlar
    static func resim(_ cizgiler: [PKStroke], alan: CGRect) -> UIImage {
        let cizim = PKDrawing(strokes: cizgiler)
        var img = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent { img = cizim.image(from: alan, scale: 3) }
        return UIGraphicsImageRenderer(size: img.size).image { c in
            UIColor.white.setFill(); c.fill(CGRect(origin: .zero, size: img.size)); img.draw(at: .zero)
        }
    }
}

// CI sınavı (-ocrTesti): el yazısı benzeri yazı tipiyle çizilmiş bir cümleyi tanıt, desteklenen dilleri göster
struct OcrSinavEkrani: View {
    @State private var sonuc = "çalışıyor…"
    var body: some View {
        Text(sonuc).font(.title3).padding().accessibilityIdentifier("ocr-sonuc")
            .task {
                let f = UIFont(name: "BradleyHandITCTT-Bold", size: 54) ?? .italicSystemFont(ofSize: 54)
                let s = NSAttributedString(string: "Merhaba dünya, bu bir deneme", attributes: [.font: f, .foregroundColor: UIColor.black])
                let r = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 120)).image { c in
                    UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: 900, height: 120)); s.draw(at: CGPoint(x: 10, y: 24))
                }
                MetinTanima.tani(r) { metin, diller in sonuc = "OCR: \(metin ?? "(boş)") | diller: \(diller)" }
            }
    }
}
