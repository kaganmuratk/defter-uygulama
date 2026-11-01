import UIKit
import PencilKit

// Kendi kalem çubuğumuz (Apple'ın PKToolPicker'ı yerine): ekranın altında yüzen cam şerit.
// Araçlar: kalem, fosforlu, silgi, seç (daire çizerek). Her aracın rengi ve kalınlığı ayrı hatırlanır,
// silgiden kaleme dönünce kalemin rengi bozulmaz. Cetvel, parmakla çizme, silgi türü ve yapıştır ⋯ menüsünde.
enum KalemPaleti {
    static let kalem: [(String, String)] = [("Siyah", "15171c"), ("Lacivert", "1d3a8a"), ("Kırmızı", "d6322e"), ("Yeşil", "1f8a4c"), ("Turuncu", "e8801c"), ("Mor", "7a3fd1")]
    static let fosforlu: [(String, String)] = [("Sarı", "ffe94d"), ("Pembe", "ff8ec1"), ("Yeşil", "9be86a"), ("Mavi", "7cc7ff"), ("Turuncu", "ffb066"), ("Mor", "c9a6ff")]
    static func renkler(_ a: KalemCubugu.Arac) -> [(String, String)] { a == .fosforlu ? fosforlu : kalem }
}

final class KalemCubugu: UIView {
    enum Arac: String { case kalem, fosforlu, silgi, sec, metin }

    var aracDegisti: (() -> Void)?
    var geriAl: (() -> Void)?
    var yinele: (() -> Void)?
    var cetvelDegisti: ((Bool) -> Void)?
    var parmakDegisti: ((Bool) -> Void)?
    var yapistir: (() -> Void)?
    var yapistirilabilir: (() -> Bool)?

    private(set) var arac: Arac = .kalem
    private(set) var cetvel = false
    private(set) var parmakla = false
    private(set) var silgiVektor = false
    private var renkSira: [Arac: Int] = [.kalem: 0, .fosforlu: 0]
    private var kalinlik: [Arac: CGFloat] = [.kalem: 3, .fosforlu: 18]
    private let kalinlikAraligi: [Arac: ClosedRange<Float>] = [.kalem: 1...14, .fosforlu: 8...44]

    private let govde = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private var aracDugmeleri: [Arac: UIButton] = [:]
    private let renkDaire = UIButton(type: .custom)
    private let menuDugmesi = UIButton(type: .system)
    private let ayarPaneli = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let renkSatiri = UIStackView()
    private let kalinlikCubugu = UISlider()
    private var ayarGizleme: DispatchWorkItem?
    private var yukseklik: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        kur()
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Canvas'ın kullanacağı PencilKit aracı
    var pkArac: PKTool {
        switch arac {
        case .kalem, .sec, .metin: return PKInkingTool(.pen, color: renk(.kalem), width: kalinlik[.kalem] ?? 3)
        case .fosforlu: return PKInkingTool(.marker, color: renk(.fosforlu), width: kalinlik[.fosforlu] ?? 18)
        case .silgi: return silgiVektor ? PKEraserTool(.vector) : PKEraserTool(.bitmap)
        }
    }
    func renk(_ a: Arac) -> UIColor {
        let liste = KalemPaleti.renkler(a)
        let i = min(max(renkSira[a] ?? 0, 0), liste.count - 1)
        return UIColor(onaltilik: liste[i].1)
    }

    // MARK: Kurulum
    private func kur() {
        translatesAutoresizingMaskIntoConstraints = false
        govde.translatesAutoresizingMaskIntoConstraints = false
        govde.layer.cornerRadius = 28; govde.layer.cornerCurve = .continuous; govde.clipsToBounds = true; govde.layer.borderWidth = 1
        govde.contentView.backgroundColor = Tema.camDolguUI
        ayarPaneli.translatesAutoresizingMaskIntoConstraints = false
        ayarPaneli.layer.cornerRadius = 24; ayarPaneli.layer.cornerCurve = .continuous; ayarPaneli.clipsToBounds = true; ayarPaneli.layer.borderWidth = 1
        ayarPaneli.contentView.backgroundColor = Tema.camDolguUI
        ayarPaneli.isHidden = true
        addSubview(govde); addSubview(ayarPaneli)

        let geri = simge("arrow.uturn.backward", "Geri al") { [weak self] in self?.geriAl?() }
        let ileri = simge("arrow.uturn.forward", "Yinele") { [weak self] in self?.yinele?() }
        geri.accessibilityIdentifier = "kalemGeri"; ileri.accessibilityIdentifier = "kalemYinele"
        let ayrac1 = ayirici(), ayrac2 = ayirici()
        let bilgi: [(Arac, String, String)] = [(.kalem, "pencil.tip", "Kalem"), (.fosforlu, "highlighter", "Fosforlu"), (.silgi, "eraser", "Silgi"), (.sec, "lasso", "Seç"), (.metin, "textformat", "Yazı kutusu")]
        var araclar: [UIView] = []
        for (a, s, ad) in bilgi {
            let b = simge(s, ad) { [weak self] in self?.dokunuldu(a) }
            b.accessibilityIdentifier = "arac-" + a.rawValue
            aracDugmeleri[a] = b; araclar.append(b)
        }
        renkDaire.translatesAutoresizingMaskIntoConstraints = false
        renkDaire.layer.cornerRadius = 15; renkDaire.layer.borderWidth = 2.5
        renkDaire.widthAnchor.constraint(equalToConstant: 30).isActive = true
        renkDaire.heightAnchor.constraint(equalToConstant: 30).isActive = true
        renkDaire.addAction(UIAction { [weak self] _ in self?.ayarPaneliniAc() }, for: .touchUpInside)
        renkDaire.accessibilityIdentifier = "kalemRenk"; renkDaire.accessibilityLabel = "Renk ve kalınlık"
        menuDugmesi.setImage(UIImage(systemName: "ellipsis.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)), for: .normal)
        menuDugmesi.showsMenuAsPrimaryAction = true
        menuDugmesi.accessibilityIdentifier = "kalemMenu"; menuDugmesi.accessibilityLabel = "Daha fazla"
        menuDugmesi.widthAnchor.constraint(equalToConstant: 42).isActive = true
        menuDugmesi.heightAnchor.constraint(equalToConstant: 42).isActive = true
        menuDugmesi.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] tamam in tamam(self?.menuOgeleri() ?? []) }])

        let sira = UIStackView(arrangedSubviews: [geri, ileri, ayrac1] + araclar + [ayrac2, renkDaire, menuDugmesi])
        sira.spacing = 4; sira.alignment = .center
        sira.translatesAutoresizingMaskIntoConstraints = false
        govde.contentView.addSubview(sira)

        renkSatiri.axis = .horizontal; renkSatiri.spacing = 10; renkSatiri.alignment = .center
        kalinlikCubugu.addAction(UIAction { [weak self] _ in self?.kalinlikDegisti() }, for: .valueChanged)
        kalinlikCubugu.accessibilityIdentifier = "kalemKalinlik"
        let ayarSira = UIStackView(arrangedSubviews: [renkSatiri, kalinlikCubugu])
        ayarSira.axis = .vertical; ayarSira.spacing = 12; ayarSira.alignment = .fill
        ayarSira.translatesAutoresizingMaskIntoConstraints = false
        ayarPaneli.contentView.addSubview(ayarSira)

        NSLayoutConstraint.activate([
            govde.leadingAnchor.constraint(equalTo: leadingAnchor), govde.trailingAnchor.constraint(equalTo: trailingAnchor),
            govde.bottomAnchor.constraint(equalTo: bottomAnchor), govde.heightAnchor.constraint(equalToConstant: 56),
            sira.leadingAnchor.constraint(equalTo: govde.contentView.leadingAnchor, constant: 10),
            sira.trailingAnchor.constraint(equalTo: govde.contentView.trailingAnchor, constant: -10),
            sira.centerYAnchor.constraint(equalTo: govde.contentView.centerYAnchor),
            ayarPaneli.bottomAnchor.constraint(equalTo: govde.topAnchor, constant: -10),
            ayarPaneli.centerXAnchor.constraint(equalTo: centerXAnchor),
            ayarPaneli.heightAnchor.constraint(equalToConstant: 112),
            ayarSira.leadingAnchor.constraint(equalTo: ayarPaneli.contentView.leadingAnchor, constant: 18),
            ayarSira.trailingAnchor.constraint(equalTo: ayarPaneli.contentView.trailingAnchor, constant: -18),
            ayarSira.topAnchor.constraint(equalTo: ayarPaneli.contentView.topAnchor, constant: 14),
            ayarSira.bottomAnchor.constraint(equalTo: ayarPaneli.contentView.bottomAnchor, constant: -14),
            kalinlikCubugu.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])
        yukseklik = heightAnchor.constraint(equalToConstant: 56)
        yukseklik.isActive = true
        guncelle()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (k: KalemCubugu, _: UITraitCollection) in k.kenarlar() }
        kenarlar()
    }

    private func kenarlar() {
        let c = Tema.camKenarUI.resolvedColor(with: traitCollection).cgColor
        govde.layer.borderColor = c; ayarPaneli.layer.borderColor = c
    }

    private func simge(_ ad: String, _ etiket: String, _ eylem: @escaping () -> Void) -> UIButton {
        let b = UIButton(type: .system, primaryAction: UIAction { _ in eylem() })
        b.setImage(UIImage(systemName: ad, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)), for: .normal)
        b.accessibilityLabel = etiket; b.toolTip = etiket
        b.layer.cornerRadius = 14; b.layer.cornerCurve = .continuous
        b.widthAnchor.constraint(equalToConstant: 42).isActive = true
        b.heightAnchor.constraint(equalToConstant: 42).isActive = true
        return b
    }
    private func ayirici() -> UIView {
        let v = UIView(); v.backgroundColor = Tema.camKenarUI
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return v
    }

    // MARK: Davranış
    private func dokunuldu(_ a: Arac) {
        if a == arac, a == .kalem || a == .fosforlu { ayarPaneliniAc(); return }
        sec(a)
    }
    func sec(_ a: Arac) {
        arac = a
        ayarGoster(false)
        guncelle()
        aracDegisti?()
    }

    private func guncelle() {
        for (a, b) in aracDugmeleri {
            let secili = a == arac
            b.tintColor = secili ? Tema.vurguUI : Tema.murekkepUI
            b.backgroundColor = secili ? Tema.vurguUI.withAlphaComponent(0.16) : .clear
        }
        for v in govde.contentView.subviews.first?.subviews ?? [] where v is UIButton && v !== renkDaire && v !== menuDugmesi && !(aracDugmeleri.values.contains { $0 === v }) {
            (v as? UIButton)?.tintColor = Tema.murekkepUI
        }
        menuDugmesi.tintColor = Tema.murekkepUI
        let cizim = arac == .kalem || arac == .fosforlu
        renkDaire.isHidden = !(cizim || arac == .sec)
        let gosterilen = arac == .fosforlu ? Arac.fosforlu : Arac.kalem
        renkDaire.backgroundColor = renk(gosterilen)
        renkDaire.layer.borderColor = Tema.camKenarUI.resolvedColor(with: traitCollection).cgColor
    }

    private func ayarPaneliniAc() {
        let a: Arac = arac == .fosforlu ? .fosforlu : .kalem
        if arac == .silgi || arac == .sec { sec(a) }
        renkSatiri.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, (ad, hex)) in KalemPaleti.renkler(a).enumerated() {
            let b = UIButton(type: .custom)
            b.backgroundColor = UIColor(onaltilik: hex)
            b.layer.cornerRadius = 17
            b.layer.borderWidth = (renkSira[a] ?? 0) == i ? 3 : 1
            b.layer.borderColor = (renkSira[a] ?? 0) == i ? Tema.vurguUI.cgColor : Tema.camKenarUI.resolvedColor(with: traitCollection).cgColor
            b.widthAnchor.constraint(equalToConstant: 34).isActive = true
            b.heightAnchor.constraint(equalToConstant: 34).isActive = true
            b.accessibilityLabel = ad; b.accessibilityIdentifier = "renk-\(i)"
            b.addAction(UIAction { [weak self] _ in self?.renkSec(a, i) }, for: .touchUpInside)
            renkSatiri.addArrangedSubview(b)
        }
        let aralik = kalinlikAraligi[a] ?? 1...14
        kalinlikCubugu.minimumValue = aralik.lowerBound; kalinlikCubugu.maximumValue = aralik.upperBound
        kalinlikCubugu.value = Float(kalinlik[a] ?? 3)
        kalinlikCubugu.tintColor = Tema.vurguUI
        ayarGoster(true)
        ayarGizlemeyiPlanla()
    }
    private func ayarGoster(_ g: Bool) {
        ayarPaneli.isHidden = !g
        yukseklik.constant = g ? 56 + 10 + 112 : 56
        superview?.layoutIfNeeded()
    }
    // Şeridin yalnız görünen parçaları dokunuşu alır; boş alandan dokunuşlar PDF'e geçer
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let v = super.hitTest(point, with: event)
        return v === self ? nil : v
    }
    private func renkSec(_ a: Arac, _ i: Int) {
        renkSira[a] = i
        guncelle(); ayarPaneliniAc(); aracDegisti?()
    }
    private func kalinlikDegisti() {
        let a: Arac = arac == .fosforlu ? .fosforlu : .kalem
        kalinlik[a] = CGFloat(kalinlikCubugu.value)
        aracDegisti?()
        ayarGizlemeyiPlanla()
    }
    private func ayarGizlemeyiPlanla() {
        ayarGizleme?.cancel()
        let is_ = DispatchWorkItem { [weak self] in self?.ayarGoster(false) }
        ayarGizleme = is_
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: is_)
    }

    private func menuOgeleri() -> [UIMenuElement] {
        var o: [UIMenuElement] = [
            UIAction(title: "Cetvel", image: UIImage(systemName: "ruler"), state: cetvel ? .on : .off) { [weak self] _ in
                guard let self else { return }; self.cetvel.toggle(); self.cetvelDegisti?(self.cetvel)
            },
            UIAction(title: "Parmakla da çiz", image: UIImage(systemName: "hand.draw"), state: parmakla ? .on : .off) { [weak self] _ in
                guard let self else { return }; self.parmakla.toggle(); self.parmakDegisti?(self.parmakla)
            },
            UIAction(title: "Silgi: çizgiyi tamamen sil", image: UIImage(systemName: "eraser.line.dashed"), state: silgiVektor ? .on : .off) { [weak self] _ in
                guard let self else { return }; self.silgiVektor.toggle(); self.aracDegisti?()
            },
        ]
        if yapistirilabilir?() == true {
            o.append(UIAction(title: "Yapıştır", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in self?.yapistir?() })
        }
        return o
    }
}
