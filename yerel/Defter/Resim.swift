import UIKit

// Nota eklenen görseller (galeriden ya da kameradan). Dosya kendi/ klasörüne (yedeğe dahil) küçültülüp JPEG olarak yazılır;
// sayfada konumu ve boyutu PartKaydi.resimler içinde durur. Görsel çizimin ALTINDA kalır, üstüne kalemle yazılabilir.
enum ResimDepo {
    static func url(_ dosya: String) -> URL { KendiDepo.klasor.appendingPathComponent(dosya) }

    /// En uzun kenarı 1800 piksele indirir (iPad kamerası/galeri fotoğrafları çok büyük); yönü düzeltir
    static func kaydet(_ img: UIImage) -> (dosya: String, boyut: CGSize)? {
        let en = max(img.size.width, img.size.height)
        guard en > 0 else { return nil }
        let oran = min(1, 1800 / en)
        let hedef = CGSize(width: max((img.size.width * oran).rounded(), 1), height: max((img.size.height * oran).rounded(), 1))
        let bicim = UIGraphicsImageRendererFormat()
        bicim.scale = 1; bicim.opaque = true
        let k = UIGraphicsImageRenderer(size: hedef, format: bicim).image { _ in img.draw(in: CGRect(origin: .zero, size: hedef)) }
        guard let d = k.jpegData(compressionQuality: 0.85) else { return nil }
        let ad = "r-" + UUID().uuidString.prefix(8).lowercased() + ".jpg"
        do { try d.write(to: url(ad), options: .atomic) } catch { Tani.yaz("görsel yazılamadı", error.localizedDescription); return nil }
        return (ad, hedef)
    }
    static func yukle(_ dosya: String) -> UIImage? { UIImage(contentsOfFile: url(dosya).path) }
}

/// Sayfadaki görsel: "Görsel" aracı açıkken dokununca seçilir; sürüklenir, sağ alt köşeden ya da iki parmakla boyutlanır, sol üstteki ✕ ile silinir.
final class ResimGorunumu: UIView, UIGestureRecognizerDelegate {
    private(set) var model: ResimKutusu
    var degisti: ((ResimKutusu) -> Void)?
    var silindi: ((String) -> Void)?
    var secildi: ((String) -> Void)?
    private let gorsel = UIImageView()
    private let boyutTutamaci = UIImageView(image: UIImage(systemName: "arrow.up.left.and.arrow.down.right.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .regular)))
    private let silDugmesi = UIButton(type: .system)
    private var baslangic: CGRect = .zero
    var secili = false { didSet { secimiGoster() } }

    init(model: ResimKutusu, gorsel resim: UIImage?) {
        self.model = model
        super.init(frame: CGRect(x: model.x, y: model.y, width: model.genislik, height: model.yukseklik))
        gorsel.image = resim
        gorsel.contentMode = .scaleAspectFill
        gorsel.clipsToBounds = true
        gorsel.layer.cornerRadius = 4
        gorsel.backgroundColor = UIColor(white: 0.5, alpha: 0.12)
        gorsel.frame = bounds; gorsel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(gorsel)
        layer.shadowColor = UIColor.black.cgColor; layer.shadowOpacity = 0.18; layer.shadowRadius = 4; layer.shadowOffset = CGSize(width: 0, height: 2)
        accessibilityIdentifier = "resim"; isAccessibilityElement = true; accessibilityLabel = "Görsel"

        boyutTutamaci.tintColor = Tema.vurguUI
        boyutTutamaci.backgroundColor = UIColor.white.withAlphaComponent(0.9)
        boyutTutamaci.layer.cornerRadius = 15; boyutTutamaci.clipsToBounds = true
        boyutTutamaci.isUserInteractionEnabled = true
        boyutTutamaci.accessibilityIdentifier = "resim-boyut"
        boyutTutamaci.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(boyutla(_:))))
        silDugmesi.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .regular)), for: .normal)
        silDugmesi.tintColor = Tema.vurguUI
        silDugmesi.backgroundColor = UIColor.white.withAlphaComponent(0.9)
        silDugmesi.layer.cornerRadius = 15; silDugmesi.clipsToBounds = true
        silDugmesi.accessibilityIdentifier = "resim-sil"; silDugmesi.accessibilityLabel = "Görseli sil"
        silDugmesi.addAction(UIAction { [weak self] _ in guard let self else { return }; self.silindi?(self.model.id) }, for: .touchUpInside)
        addSubview(boyutTutamaci); addSubview(silDugmesi)

        let tasima = UIPanGestureRecognizer(target: self, action: #selector(tasi(_:)))
        tasima.delegate = self
        addGestureRecognizer(tasima)
        let sikistir = UIPinchGestureRecognizer(target: self, action: #selector(sikistir(_:)))
        addGestureRecognizer(sikistir)
        let dokun = UITapGestureRecognizer(target: self, action: #selector(dokun))
        addGestureRecognizer(dokun)
        isUserInteractionEnabled = false
        secimiGoster()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        boyutTutamaci.frame = CGRect(x: bounds.width - 34, y: bounds.height - 34, width: 30, height: 30)
        silDugmesi.frame = CGRect(x: 4, y: 4, width: 30, height: 30)
    }
    /// Görsel aracı açıkken dokunuşları alır; kapanınca seçim de kalkar
    func etkinlestir(_ e: Bool) {
        isUserInteractionEnabled = e
        if !e { secili = false }
    }
    private func secimiGoster() {
        gorsel.layer.borderWidth = secili ? 2 : 0
        gorsel.layer.borderColor = Tema.vurguUI.cgColor
        boyutTutamaci.isHidden = !secili; silDugmesi.isHidden = !secili
    }
    private func modeliYaz() {
        model.x = Double(frame.origin.x); model.y = Double(frame.origin.y)
        model.genislik = Double(frame.width); model.yukseklik = Double(frame.height)
        degisti?(model)
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.view !== boyutTutamaci && touch.view !== silDugmesi
    }
    @objc private func dokun() { secildi?(model.id) }
    @objc private func tasi(_ g: UIPanGestureRecognizer) {
        guard let ust = superview else { return }
        switch g.state {
        case .began: secildi?(model.id); baslangic = frame
        case .changed:
            let t = g.translation(in: ust)
            let x = min(max(baslangic.origin.x + t.x, 20 - baslangic.width), ust.bounds.width - 20)
            let y = min(max(baslangic.origin.y + t.y, 20 - baslangic.height), ust.bounds.height - 20)
            frame.origin = CGPoint(x: x, y: y)
        case .ended, .cancelled: modeliYaz()
        default: break
        }
    }
    @objc private func boyutla(_ g: UIPanGestureRecognizer) {
        guard let ust = superview else { return }
        switch g.state {
        case .began: baslangic = frame
        case .changed:
            let t = g.translation(in: ust)
            let oran = baslangic.height / max(baslangic.width, 1)
            let w = min(max(baslangic.width + max(t.x, t.y / max(oran, 0.1)), 60), ust.bounds.width * 1.5)
            frame.size = CGSize(width: w, height: w * oran)
        case .ended, .cancelled: modeliYaz()
        default: break
        }
    }
    @objc private func sikistir(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began: secildi?(model.id); baslangic = frame
        case .changed:
            let w = min(max(baslangic.width * g.scale, 60), (superview?.bounds.width ?? 800) * 1.5)
            let oran = baslangic.height / max(baslangic.width, 1)
            let c = CGPoint(x: baslangic.midX, y: baslangic.midY)
            frame = CGRect(x: c.x - w / 2, y: c.y - w * oran / 2, width: w, height: w * oran)
        case .ended, .cancelled: modeliYaz()
        default: break
        }
    }
}
