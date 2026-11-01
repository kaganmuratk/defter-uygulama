import UIKit
import PencilKit

// Seçim aracı: kalemle daire çizerek çizgileri seç; kutuyu sürükleyip taşı, köşeden büyüt/küçült;
// renk, kalınlık, çoğalt, kopyala, kes, sil. Değişiklikler geri alınabilir.
enum SecimPanosu { static var kopya: [PKStroke] = [] }

/// Seçilen çizgilerin etrafındaki kesikli kutu ve dört köşe tutamacı
final class SecimKutusu: UIView {
    let tutamaclar: [UIView] = (0..<4).map { i in
        let v = UIView(frame: CGRect(x: 0, y: 0, width: 26, height: 26))
        v.tag = i
        v.backgroundColor = .white
        v.layer.cornerRadius = 13; v.layer.borderWidth = 3; v.layer.borderColor = Tema.vurguUI.cgColor
        v.layer.shadowColor = UIColor.black.cgColor; v.layer.shadowOpacity = 0.25; v.layer.shadowRadius = 3; v.layer.shadowOffset = CGSize(width: 0, height: 1)
        v.accessibilityIdentifier = "secim-tutamac-\(i)"
        return v
    }
    private let cerceve = CAShapeLayer()
    var olcek: CGFloat = 1 { didSet { setNeedsLayout() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Tema.vurguUI.withAlphaComponent(0.05)
        cerceve.strokeColor = Tema.vurguUI.cgColor; cerceve.fillColor = UIColor.clear.cgColor
        cerceve.lineWidth = 2; cerceve.lineDashPattern = [7, 5]
        layer.addSublayer(cerceve)
        for t in tutamaclar { addSubview(t) }
        accessibilityIdentifier = "secim-kutusu"
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        cerceve.frame = bounds
        cerceve.path = UIBezierPath(roundedRect: bounds, cornerRadius: 6).cgPath
        cerceve.lineWidth = 2 / max(olcek, 0.3)
        let noktalar = [CGPoint(x: 0, y: 0), CGPoint(x: bounds.width, y: 0), CGPoint(x: 0, y: bounds.height), CGPoint(x: bounds.width, y: bounds.height)]
        for (i, t) in tutamaclar.enumerated() {
            t.transform = .identity
            t.center = noktalar[i]
            t.transform = CGAffineTransform(scaleX: 1 / max(olcek, 0.3), y: 1 / max(olcek, 0.3))
        }
    }
    // Köşe tutamaçları kutunun dışına taştığı için dokunma alanı genişletilir
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -22, dy: -22).contains(point)
    }
}

final class SecimKontrol: NSObject {
    private weak var katman: SayfaKatmani?
    private let lasso = UIPanGestureRecognizer()
    private let lassoCizgi = CAShapeLayer()
    private var noktalar: [CGPoint] = []
    private var secili: [Int] = []
    private let kutu = SecimKutusu()
    private let cubuk = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let cubukSira = UIStackView()
    private var hareketOncesi: PKDrawing?
    private var toplamOlcek: CGFloat = 1
    private var sabitNokta = CGPoint.zero
    private var sonUzaklik: CGFloat = 1

    /// PDF yakınlaştırma oranı: kutu ve çubuk ekranda hep aynı boyda kalsın diye ters ölçeklenir
    var olcek: CGFloat = 1 { didSet { kutu.olcek = olcek; if !secili.isEmpty { cubuguYerlestir() } } }
    var etkin = false {
        didSet {
            guard oldValue != etkin else { return }
            lasso.isEnabled = etkin
            if !etkin { birak() }
        }
    }
    var kutusuVarMi: Bool { !secili.isEmpty }
    var metinHazir: ((String, CGRect) -> Void)?   // (tanınan metin, seçimin sayfadaki alanı)

    init(katman: SayfaKatmani) {
        self.katman = katman
        super.init()
        lasso.addTarget(self, action: #selector(lassoJesti(_:)))
        lasso.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        lasso.maximumNumberOfTouches = 1
        lasso.isEnabled = false
        katman.addGestureRecognizer(lasso)
        lassoCizgi.strokeColor = Tema.vurguUI.cgColor; lassoCizgi.fillColor = Tema.vurguUI.withAlphaComponent(0.07).cgColor
        lassoCizgi.lineWidth = 2; lassoCizgi.lineDashPattern = [6, 4]
        let tasi = UIPanGestureRecognizer(target: self, action: #selector(tasiJesti(_:)))
        kutu.addGestureRecognizer(tasi)
        for t in kutu.tutamaclar { t.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(boyutJesti(_:)))) }
        cubuk.layer.cornerRadius = 22; cubuk.layer.cornerCurve = .continuous; cubuk.clipsToBounds = true
        cubuk.layer.borderWidth = 1; cubuk.layer.borderColor = Tema.camKenarUI.cgColor
        cubuk.contentView.backgroundColor = Tema.camDolguUI
        cubukSira.spacing = 2; cubukSira.alignment = .center
        cubukSira.translatesAutoresizingMaskIntoConstraints = false
        cubuk.contentView.addSubview(cubukSira)
        NSLayoutConstraint.activate([
            cubukSira.leadingAnchor.constraint(equalTo: cubuk.contentView.leadingAnchor, constant: 8), cubukSira.trailingAnchor.constraint(equalTo: cubuk.contentView.trailingAnchor, constant: -8),
            cubukSira.topAnchor.constraint(equalTo: cubuk.contentView.topAnchor, constant: 4), cubukSira.bottomAnchor.constraint(equalTo: cubuk.contentView.bottomAnchor, constant: -4),
        ])
        cubukDugmeleri()
    }

    // MARK: Daire çizerek seçme
    @objc private func lassoJesti(_ g: UIPanGestureRecognizer) {
        guard let k = katman else { return }
        let p = g.location(in: k)
        switch g.state {
        case .began:
            birak(); noktalar = [p]
            lassoCizgi.path = nil; k.layer.addSublayer(lassoCizgi)
        case .changed:
            noktalar.append(p)
            lassoCizgi.path = yol(noktalar).cgPath
        case .ended:
            lassoCizgi.removeFromSuperlayer()
            sec(noktalar)
        default:
            lassoCizgi.removeFromSuperlayer()
        }
    }
    private func yol(_ n: [CGPoint]) -> UIBezierPath {
        let y = UIBezierPath()
        guard let ilk = n.first else { return y }
        y.move(to: ilk); for p in n.dropFirst() { y.addLine(to: p) }
        return y
    }
    private func sec(_ n: [CGPoint]) {
        guard let k = katman, n.count > 3 else { return }
        let poligon = yol(n); poligon.close()
        let cg = poligon.cgPath
        let cizim = k.tuval.drawing
        var bulunan: [Int] = []
        for (i, s) in cizim.strokes.enumerated() {
            guard s.renderBounds.intersects(poligon.bounds) else { continue }
            var toplam = 0, icinde = 0
            for nk in s.path.interpolatedPoints(by: .distance(8)) {
                toplam += 1
                if cg.contains(nk.location.applying(s.transform)) { icinde += 1 }
            }
            if toplam > 0, Double(icinde) / Double(toplam) >= 0.5 { bulunan.append(i) }
        }
        guard !bulunan.isEmpty else { return }
        secili = bulunan
        kutuGoster()
    }

    func birak() {
        secili = []; toplamOlcek = 1
        kutu.removeFromSuperview(); cubuk.removeFromSuperview()
    }

    // MARK: Kutu ve işlem çubuğu
    private func sinirlar() -> CGRect? {
        guard let k = katman else { return nil }
        let s = k.tuval.drawing.strokes
        let r = secili.filter { $0 < s.count }.map { s[$0].renderBounds }
        guard var u = r.first else { return nil }
        for x in r.dropFirst() { u = u.union(x) }
        return u
    }
    private func kutuGoster() {
        guard let k = katman, let r = sinirlar() else { birak(); return }
        kutu.frame = r.insetBy(dx: -8, dy: -8)
        kutu.olcek = olcek
        if kutu.superview == nil { k.addSubview(kutu) }
        k.bringSubviewToFront(kutu)
        if cubuk.superview == nil { k.addSubview(cubuk) }
        k.bringSubviewToFront(cubuk)
        cubuguYerlestir()
    }
    private func cubuguYerlestir() {
        guard let k = katman, kutu.superview != nil else { return }
        cubuk.transform = .identity
        let genislik = cubukSira.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width + 16
        cubuk.bounds = CGRect(origin: .zero, size: CGSize(width: max(genislik, 200), height: 44))
        let ters = 1 / max(olcek, 0.3)
        var cy = kutu.frame.minY - (30 + 14) * ters
        if cy < 24 * ters { cy = kutu.frame.maxY + (30 + 14) * ters }
        let genis = cubuk.bounds.width * ters / 2
        let cx = min(max(kutu.frame.midX, genis + 4), max(k.bounds.width - genis - 4, genis + 4))
        cubuk.center = CGPoint(x: cx, y: cy)
        cubuk.transform = CGAffineTransform(scaleX: ters, y: ters)
    }

    // MARK: Taşı / boyutlandır
    @objc private func tasiJesti(_ g: UIPanGestureRecognizer) {
        guard let k = katman else { return }
        switch g.state {
        case .began: hareketBasla()
        case .changed:
            let t = g.translation(in: k); g.setTranslation(.zero, in: k)
            donustur(CGAffineTransform(translationX: t.x, y: t.y))
        case .ended, .cancelled, .failed: hareketBitir()
        default: break
        }
    }
    @objc private func boyutJesti(_ g: UIPanGestureRecognizer) {
        guard let k = katman, let tut = g.view else { return }
        let r = kutu.frame
        switch g.state {
        case .began:
            hareketBasla()
            // tutulan köşenin tersindeki köşe sabit kalır
            switch tut.tag {
            case 0: sabitNokta = CGPoint(x: r.maxX, y: r.maxY)
            case 1: sabitNokta = CGPoint(x: r.minX, y: r.maxY)
            case 2: sabitNokta = CGPoint(x: r.maxX, y: r.minY)
            default: sabitNokta = CGPoint(x: r.minX, y: r.minY)
            }
            sonUzaklik = max(hypot(g.location(in: k).x - sabitNokta.x, g.location(in: k).y - sabitNokta.y), 20)
        case .changed:
            let p = g.location(in: k)
            let yeni = max(hypot(p.x - sabitNokta.x, p.y - sabitNokta.y), 20)
            var s = yeni / sonUzaklik
            let hedef = toplamOlcek * s
            if hedef < 0.15 || hedef > 10 { return }
            sonUzaklik = yeni; toplamOlcek = hedef
            if s.isNaN || s.isInfinite { s = 1 }
            let T = CGAffineTransform(translationX: sabitNokta.x, y: sabitNokta.y).scaledBy(x: s, y: s).translatedBy(x: -sabitNokta.x, y: -sabitNokta.y)
            donustur(T)
        case .ended, .cancelled, .failed: hareketBitir()
        default: break
        }
    }
    private func hareketBasla() { hareketOncesi = katman?.tuval.drawing; katman?.secimSuruyor = true; toplamOlcek = 1 }
    private func donustur(_ T: CGAffineTransform) {
        guard let k = katman else { return }
        var d = k.tuval.drawing
        for i in secili where i < d.strokes.count { d.strokes[i].transform = d.strokes[i].transform.concatenating(T) }
        k.tuval.drawing = d
        kutu.frame = kutu.frame.applying(T)
        cubuguYerlestir()
    }
    private func hareketBitir() {
        guard let k = katman else { return }
        k.secimSuruyor = false
        if let o = hareketOncesi { geriAlmaKaydet(o) }
        hareketOncesi = nil
        k.cizimDegisti?()
        kutuGoster()
    }

    // MARK: Geri alma
    private func geriAlmaKaydet(_ eski: PKDrawing) {
        guard let k = katman, let um = k.undoManager else { return }
        um.registerUndo(withTarget: self) { hedef in
            guard let kk = hedef.katman else { return }
            let simdi = kk.tuval.drawing
            kk.secimSuruyor = true
            kk.tuval.drawing = eski
            kk.secimSuruyor = false
            hedef.birak()
            kk.cizimDegisti?()
            hedef.geriAlmaKaydet(simdi)
        }
    }
    /// Çizim üzerinde değişiklik yapar; geri alınabilir ve kayda işlenir
    private func degistir(_ f: (inout PKDrawing) -> Void) {
        guard let k = katman else { return }
        let once = k.tuval.drawing
        var d = once
        f(&d)
        k.secimSuruyor = true
        k.tuval.drawing = d
        k.secimSuruyor = false
        geriAlmaKaydet(once)
        k.cizimDegisti?()
    }

    // MARK: İşlemler
    private func cubukDugmeleri() {
        func dugme(_ sembol: String, _ ad: String, kimlik: String, kirmizi: Bool = false, eylem: @escaping () -> Void) -> UIButton {
            let b = UIButton(type: .system, primaryAction: UIAction { _ in eylem() })
            b.setImage(UIImage(systemName: sembol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)), for: .normal)
            b.tintColor = kirmizi ? UIColor.systemRed : Tema.murekkepUI
            b.accessibilityLabel = ad; b.accessibilityIdentifier = kimlik; b.toolTip = ad
            b.widthAnchor.constraint(equalToConstant: 40).isActive = true
            b.heightAnchor.constraint(equalToConstant: 36).isActive = true
            return b
        }
        let renk = UIButton(type: .system)
        renk.setImage(UIImage(systemName: "paintpalette", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)), for: .normal)
        renk.tintColor = Tema.murekkepUI
        renk.showsMenuAsPrimaryAction = true
        renk.accessibilityLabel = "Rengi değiştir"; renk.accessibilityIdentifier = "secim-renk"
        renk.menu = UIMenu(title: "Renk", children: KalemPaleti.kalem.map { (ad, hex) in
            UIAction(title: ad, image: UIImage(systemName: "circle.fill")?.withTintColor(UIColor(onaltilik: hex), renderingMode: .alwaysOriginal)) { [weak self] _ in self?.renkDegistir(UIColor(onaltilik: hex)) }
        })
        renk.widthAnchor.constraint(equalToConstant: 40).isActive = true
        renk.heightAnchor.constraint(equalToConstant: 36).isActive = true
        for v in [renk,
                  dugme("minus.circle", "İncelt", kimlik: "secim-ince") { [weak self] in self?.kalinlikDegistir(0.8) },
                  dugme("plus.circle", "Kalınlaştır", kimlik: "secim-kalin") { [weak self] in self?.kalinlikDegistir(1.25) },
                  dugme("plus.square.on.square", "Çoğalt", kimlik: "secim-cogalt") { [weak self] in self?.cogalt() },
                  dugme("doc.on.doc", "Kopyala", kimlik: "secim-kopyala") { [weak self] in self?.kopyala() },
                  dugme("textformat.abc", "Metne çevir", kimlik: "secim-metne") { [weak self] in self?.metneCevir() },
                  dugme("scissors", "Kes", kimlik: "secim-kes") { [weak self] in self?.kes() },
                  dugme("trash", "Sil", kimlik: "secim-sil", kirmizi: true) { [weak self] in self?.sil() }] as [UIView] {
            cubukSira.addArrangedSubview(v)
        }
    }

    private func renkDegistir(_ renk: UIColor) {
        let ids = secili
        degistir { d in
            for i in ids where i < d.strokes.count { d.strokes[i].ink = PKInk(d.strokes[i].ink.inkType, color: renk) }
        }
        kutuGoster()
    }
    private func kalinlikDegistir(_ carpan: CGFloat) {
        let ids = secili
        degistir { d in
            for i in ids where i < d.strokes.count {
                let s = d.strokes[i]
                let yol = s.path
                var pts: [PKStrokePoint] = []
                for p in yol {
                    pts.append(PKStrokePoint(location: p.location, timeOffset: p.timeOffset, size: CGSize(width: p.size.width * carpan, height: p.size.height * carpan),
                                             opacity: p.opacity, force: p.force, azimuth: p.azimuth, altitude: p.altitude))
                }
                let yeni = PKStrokePath(controlPoints: pts, creationDate: yol.creationDate)
                d.strokes[i] = PKStroke(ink: s.ink, path: yeni, transform: s.transform, mask: s.mask)
            }
        }
        kutuGoster()
    }
    private func kopyala() {
        guard let k = katman else { return }
        let s = k.tuval.drawing.strokes
        SecimPanosu.kopya = secili.filter { $0 < s.count }.map { s[$0] }
    }
    private func kes() { kopyala(); sil() }
    func secimiSil() { sil() }
    private func metneCevir() {
        guard let k = katman, let r = sinirlar() else { return }
        let s = k.tuval.drawing.strokes
        let secilen = secili.filter { $0 < s.count }.map { s[$0] }
        let resim = MetinTanima.resim(secilen, alan: r.insetBy(dx: -16, dy: -16))
        MetinTanima.tani(resim) { [weak self] metin, _ in self?.metinHazir?(metin ?? "", r) }
    }
    private func sil() {
        let ids = secili.sorted(by: >)
        degistir { d in for i in ids where i < d.strokes.count { d.strokes.remove(at: i) } }
        birak()
    }
    private func cogalt() {
        let ids = secili
        var yeniler: [Int] = []
        degistir { d in
            let kayma = CGAffineTransform(translationX: 28, y: 28)
            for i in ids where i < d.strokes.count {
                let s = d.strokes[i]
                d.strokes.append(PKStroke(ink: s.ink, path: s.path, transform: s.transform.concatenating(kayma), mask: s.mask))
                yeniler.append(d.strokes.count - 1)
            }
        }
        secili = yeniler
        kutuGoster()
    }

    /// Panodaki çizgileri verilen merkeze yapıştırır ve seçer
    func yapistir(merkez: CGPoint) {
        guard !SecimPanosu.kopya.isEmpty else { return }
        let kopya = SecimPanosu.kopya
        var u = kopya[0].renderBounds
        for s in kopya.dropFirst() { u = u.union(s.renderBounds) }
        let T = CGAffineTransform(translationX: merkez.x - u.midX, y: merkez.y - u.midY)
        var yeniler: [Int] = []
        degistir { d in
            for s in kopya {
                d.strokes.append(PKStroke(ink: s.ink, path: s.path, transform: s.transform.concatenating(T), mask: s.mask))
                yeniler.append(d.strokes.count - 1)
            }
        }
        secili = yeniler
        kutuGoster()
    }
}
