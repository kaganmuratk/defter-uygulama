import UIKit
import PencilKit

// Kendi kalem çubuğumuz (Apple'ın PKToolPicker'ı yerine): ekranda yüzen cam şerit.
// Araçlar: kalem, fosforlu, silgi, seç (daire çizerek), yazı kutusu, gezin (kalemle kaydır). Her aracın rengi ve kalınlığı ayrı hatırlanır,
// silgiden kaleme dönünce kalemin rengi bozulmaz. Cetvel, parmakla çizme, silgi türü ve yapıştır ⋯ menüsünde.
// Çubuk yalnız tutamacından (uçtaki noktalar) sürüklenir ve 8 sabit konumdan birine oturur; konumu hatırlanır.
// Bu görünüm okuyucu alanının tamamını kaplar; boş yerlerden dokunuşlar alttaki PDF'e geçer.
enum KalemPaleti {
    static let kalem: [(String, String)] = [("Siyah", "15171c"), ("Lacivert", "1d3a8a"), ("Kırmızı", "d6322e"), ("Yeşil", "1f8a4c"), ("Turuncu", "e8801c"), ("Mor", "7a3fd1")]
    static let fosforlu: [(String, String)] = [("Sarı", "ffe94d"), ("Pembe", "ff8ec1"), ("Yeşil", "9be86a"), ("Mavi", "7cc7ff"), ("Turuncu", "ffb066"), ("Mor", "c9a6ff")]
    static func renkler(_ a: KalemCubugu.Arac) -> [(String, String)] { a == .fosforlu ? fosforlu : kalem }
}

extension UIColor {
    /// "rrggbb" (alfa yok); renk seçiciden gelen rengi kaydetmek için
    var onaltilikDeger: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func bayt(_ x: CGFloat) -> Int { min(max(Int((x * 255).rounded()), 0), 255) }
        return String(format: "%02x%02x%02x", bayt(r), bayt(g), bayt(b))
    }
}

final class KalemCubugu: UIView {
    enum Arac: String { case kalem, fosforlu, silgi, sec, metin, gezin, resim }
    enum Konum: String {
        case alt, ust, sol, sag, solAlt, sagAlt, solUst, sagUst
        var dikey: Bool { self == .sol || self == .sag }
    }

    var aracDegisti: (() -> Void)?
    var resimEkle: ((UIView) -> Void)?
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
    private(set) var silgiBoyu: CGFloat = 22
    private(set) var konum: Konum = Konum(rawValue: UserDefaults.standard.string(forKey: "kalemKonum") ?? "") ?? .alt
    private let silgiModu = UISegmentedControl(items: ["Parça sil", "Çizgiyi sil"])
    private var renkSira: [Arac: Int] = [.kalem: 0, .fosforlu: 0]
    private var ozel: [Arac: String] = [:]             // renk seçiciden seçilen özel renk (hex)
    private var ozelKullan: [Arac: Bool] = [:]         // true ise paletteki renk yerine özel renk geçerli
    private var seciciArac: Arac?
    private let ozelPanel = UIStackView()
    private let renkAlani = RenkAlani()
    private let parlaklikCubugu = UISlider()
    private let onizleme = UIView()
    private let hexEtiketi = UILabel()
    private var kalinlik: [Arac: CGFloat] = [.kalem: 3, .fosforlu: 18]
    private let kalinlikAraligi: [Arac: ClosedRange<Float>] = [.kalem: 1...14, .fosforlu: 8...44]

    private let govde = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private var aracDugmeleri: [Arac: UIButton] = [:]
    private let renkDaire = UIButton(type: .custom)
    private let menuDugmesi = UIButton(type: .system)
    private let ayarPaneli = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let renkSatiri = UIStackView()
    private let ayarSira = UIStackView()
    private let kalinlikCubugu = UISlider()
    private var ayarGizleme: DispatchWorkItem?

    private let sira = UIStackView()
    private let tutamac = UIView()
    private var tutGenislik: NSLayoutConstraint!
    private var tutYukseklik: NSLayoutConstraint!
    private var ayiricilar: [(en: NSLayoutConstraint, boy: NSLayoutConstraint)] = []
    private var yatayKisitlar: [NSLayoutConstraint] = []
    private var dikeyKisitlar: [NSLayoutConstraint] = []
    private var suruklemede = false
    private var surukleBaslangic: CGPoint = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        kur()
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Çizim yapan araçlarda (kalem, fosforlu, silgi) tuvalin çizim jesti açık olur; seç/yazı/gezin araçlarında kapalı.
    var cizimAktif: Bool { arac != .sec && arac != .metin && arac != .gezin && arac != .resim }

    /// Canvas'ın kullanacağı PencilKit aracı
    var pkArac: PKTool {
        switch arac {
        case .kalem, .sec, .metin, .gezin, .resim: return PKInkingTool(.pen, color: renk(.kalem), width: kalinlik[.kalem] ?? 3)
        case .fosforlu: return PKInkingTool(.marker, color: renk(.fosforlu), width: kalinlik[.fosforlu] ?? 18)
        case .silgi: return silgiVektor ? PKEraserTool(.vector) : PKEraserTool(.bitmap, width: silgiBoyu)
        }
    }
    func renk(_ a: Arac) -> UIColor {
        if ozelKullan[a] == true, let h = ozel[a] { return UIColor(onaltilik: h) }
        let liste = KalemPaleti.renkler(a)
        let i = min(max(renkSira[a] ?? 0, 0), liste.count - 1)
        return UIColor(onaltilik: liste[i].1)
    }

    // MARK: Kurulum
    private func kur() {
        translatesAutoresizingMaskIntoConstraints = false
        for a in [Arac.kalem, .fosforlu] {
            if let h = UserDefaults.standard.string(forKey: "ozelRenk-" + a.rawValue) {
                ozel[a] = h
                ozelKullan[a] = UserDefaults.standard.bool(forKey: "ozelKullan-" + a.rawValue)
            }
        }
        govde.layer.cornerRadius = 28; govde.layer.cornerCurve = .continuous; govde.clipsToBounds = true; govde.layer.borderWidth = 1
        govde.contentView.backgroundColor = Tema.camDolguUI
        ayarPaneli.layer.cornerRadius = 24; ayarPaneli.layer.cornerCurve = .continuous; ayarPaneli.clipsToBounds = true; ayarPaneli.layer.borderWidth = 1
        ayarPaneli.contentView.backgroundColor = Tema.camDolguUI
        ayarPaneli.isHidden = true
        addSubview(govde); addSubview(ayarPaneli)

        // Tutamaç: çubuk yalnız buradan sürüklenir (kol çarpınca yer değiştirmesin)
        tutamac.translatesAutoresizingMaskIntoConstraints = false
        let tutIkon = UIImageView(image: UIImage(systemName: "circle.grid.2x2.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)))
        tutIkon.tintColor = Tema.soykUI
        tutIkon.translatesAutoresizingMaskIntoConstraints = false
        tutamac.addSubview(tutIkon)
        NSLayoutConstraint.activate([tutIkon.centerXAnchor.constraint(equalTo: tutamac.centerXAnchor), tutIkon.centerYAnchor.constraint(equalTo: tutamac.centerYAnchor)])
        tutGenislik = tutamac.widthAnchor.constraint(equalToConstant: 22)
        tutYukseklik = tutamac.heightAnchor.constraint(equalToConstant: 42)
        NSLayoutConstraint.activate([tutGenislik, tutYukseklik])
        let surukle = UIPanGestureRecognizer(target: self, action: #selector(cubukSurukle(_:)))
        surukle.maximumNumberOfTouches = 1
        tutamac.addGestureRecognizer(surukle)
        tutamac.accessibilityIdentifier = "kalemTutamac"; tutamac.isAccessibilityElement = true; tutamac.accessibilityLabel = "Çubuğu taşı"

        let geri = simge("arrow.uturn.backward", "Geri al") { [weak self] in self?.geriAl?() }
        let ileri = simge("arrow.uturn.forward", "Yinele") { [weak self] in self?.yinele?() }
        geri.accessibilityIdentifier = "kalemGeri"; ileri.accessibilityIdentifier = "kalemYinele"
        let ayrac0 = ayirici(), ayrac1 = ayirici(), ayrac2 = ayirici()
        let bilgi: [(Arac, String, String)] = [(.kalem, "pencil.tip", "Kalem"), (.fosforlu, "highlighter", "Fosforlu"), (.silgi, "eraser", "Silgi"), (.sec, "lasso", "Seç"), (.metin, "textformat", "Yazı kutusu"), (.gezin, "arrow.up.and.down.and.arrow.left.and.right", "Gezin (kalemle kaydır)"), (.resim, "photo", "Görsel (taşı, boyutlandır)")]
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
        renkDaire.addAction(UIAction { [weak self] _ in self?.ayarDugmesi() }, for: .touchUpInside)
        renkDaire.accessibilityIdentifier = "kalemRenk"; renkDaire.accessibilityLabel = "Renk ve kalınlık"
        menuDugmesi.setImage(UIImage(systemName: "ellipsis.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)), for: .normal)
        menuDugmesi.showsMenuAsPrimaryAction = true
        menuDugmesi.accessibilityIdentifier = "kalemMenu"; menuDugmesi.accessibilityLabel = "Daha fazla"
        menuDugmesi.widthAnchor.constraint(equalToConstant: 42).isActive = true
        menuDugmesi.heightAnchor.constraint(equalToConstant: 42).isActive = true
        menuDugmesi.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] tamam in tamam(self?.menuOgeleri() ?? []) }])

        for v in [tutamac, ayrac0, geri, ileri, ayrac1] + araclar + [ayrac2, renkDaire, menuDugmesi] { sira.addArrangedSubview(v) }
        sira.spacing = 4; sira.alignment = .center
        sira.translatesAutoresizingMaskIntoConstraints = false
        govde.contentView.addSubview(sira)
        let c = govde.contentView
        yatayKisitlar = [sira.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 8), sira.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -10),
                         sira.centerYAnchor.constraint(equalTo: c.centerYAnchor)]
        dikeyKisitlar = [sira.topAnchor.constraint(equalTo: c.topAnchor, constant: 8), sira.bottomAnchor.constraint(equalTo: c.bottomAnchor, constant: -10),
                         sira.centerXAnchor.constraint(equalTo: c.centerXAnchor)]

        renkSatiri.axis = .horizontal; renkSatiri.spacing = 10; renkSatiri.alignment = .center
        kalinlikCubugu.addAction(UIAction { [weak self] _ in self?.kalinlikDegisti() }, for: .valueChanged)
        kalinlikCubugu.accessibilityIdentifier = "kalemKalinlik"
        silgiModu.selectedSegmentIndex = 0
        silgiModu.accessibilityIdentifier = "silgi-modu"
        silgiModu.isHidden = true
        silgiModu.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.silgiVektor = self.silgiModu.selectedSegmentIndex == 1
            self.kalinlikCubugu.isEnabled = !self.silgiVektor
            self.aracDegisti?(); self.ayarGizlemeyiPlanla()
        }, for: .valueChanged)
        // Özel renk paneli: renk alanı (sol-sağ ton, yukarı-aşağı doygunluk), parlaklık sürgüsü, önizleme + hex + Tamam
        renkAlani.translatesAutoresizingMaskIntoConstraints = false
        renkAlani.accessibilityIdentifier = "renk-alani"; renkAlani.isAccessibilityElement = true; renkAlani.accessibilityLabel = "Renk alanı"
        renkAlani.degisti = { [weak self] in self?.ozelGuncelle(uygula: true) }
        parlaklikCubugu.minimumValue = 0.05; parlaklikCubugu.maximumValue = 1
        parlaklikCubugu.accessibilityIdentifier = "renk-parlaklik"
        parlaklikCubugu.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.renkAlani.bri = CGFloat(self.parlaklikCubugu.value)
            self.ozelGuncelle(uygula: true)
        }, for: .valueChanged)
        onizleme.translatesAutoresizingMaskIntoConstraints = false
        onizleme.layer.cornerRadius = 15; onizleme.layer.borderWidth = 1
        onizleme.widthAnchor.constraint(equalToConstant: 30).isActive = true
        onizleme.heightAnchor.constraint(equalToConstant: 30).isActive = true
        hexEtiketi.font = Tema.uiArayuz(14, 600); hexEtiketi.textColor = Tema.murekkepUI
        var tamamAyar = UIButton.Configuration.filled()
        tamamAyar.cornerStyle = .capsule; tamamAyar.title = "Tamam"
        tamamAyar.baseBackgroundColor = Tema.dolguUI; tamamAyar.baseForegroundColor = Tema.dolguUstuUI
        tamamAyar.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        let tamam = UIButton(configuration: tamamAyar, primaryAction: UIAction { [weak self] _ in self?.ozelPaneliKapat() })
        tamam.accessibilityIdentifier = "renk-tamam"
        let altSatir = UIStackView(arrangedSubviews: [onizleme, hexEtiketi, UIView(), tamam])
        altSatir.axis = .horizontal; altSatir.spacing = 10; altSatir.alignment = .center
        ozelPanel.axis = .vertical; ozelPanel.spacing = 12; ozelPanel.alignment = .fill
        for v in [renkAlani, parlaklikCubugu, altSatir] { ozelPanel.addArrangedSubview(v) }
        ozelPanel.isHidden = true
        ayarSira.addArrangedSubview(renkSatiri); ayarSira.addArrangedSubview(silgiModu); ayarSira.addArrangedSubview(kalinlikCubugu); ayarSira.addArrangedSubview(ozelPanel)
        ayarSira.axis = .vertical; ayarSira.spacing = 12; ayarSira.alignment = .fill
        ayarSira.translatesAutoresizingMaskIntoConstraints = false
        ayarPaneli.contentView.addSubview(ayarSira)

        NSLayoutConstraint.activate([
            ayarSira.leadingAnchor.constraint(equalTo: ayarPaneli.contentView.leadingAnchor, constant: 18),
            ayarSira.trailingAnchor.constraint(equalTo: ayarPaneli.contentView.trailingAnchor, constant: -18),
            ayarSira.topAnchor.constraint(equalTo: ayarPaneli.contentView.topAnchor, constant: 14),
            ayarSira.bottomAnchor.constraint(equalTo: ayarPaneli.contentView.bottomAnchor, constant: -14),
            kalinlikCubugu.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])
        eksenUygula()
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
        v.translatesAutoresizingMaskIntoConstraints = false
        let en = v.widthAnchor.constraint(equalToConstant: 1), boy = v.heightAnchor.constraint(equalToConstant: 26)
        NSLayoutConstraint.activate([en, boy])
        ayiricilar.append((en, boy))
        return v
    }

    // MARK: Yerleşim (çubuk ve ayar paneli elle konumlanır)
    /// Yatay/dikey düzen: sol ve sağ kenarda çubuk dikey durur
    private func eksenUygula() {
        let d = konum.dikey
        sira.axis = d ? .vertical : .horizontal
        NSLayoutConstraint.deactivate(d ? yatayKisitlar : dikeyKisitlar)
        NSLayoutConstraint.activate(d ? dikeyKisitlar : yatayKisitlar)
        for a in ayiricilar { a.en.constant = d ? 26 : 1; a.boy.constant = d ? 1 : 26 }
        tutGenislik.constant = d ? 42 : 22; tutYukseklik.constant = d ? 22 : 42
    }
    private func govdeBoyu() -> CGSize {
        let b = sira.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        if konum.dikey { return CGSize(width: 56, height: min(b.height + 18, max(bounds.height - 24, 120))) }
        return CGSize(width: min(b.width + 18, max(bounds.width - 24, 120)), height: 56)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, !suruklemede else { return }
        let m: CGFloat = 16, g = safeAreaInsets, b = bounds, boy = govdeBoyu()
        let ortaX = (b.width - boy.width) / 2, ortaY = (b.height - boy.height) / 2
        let sol = g.left + m, sag = b.width - g.right - m - boy.width
        let ust = g.top + m, alt = b.height - g.bottom - m - boy.height
        let o: CGPoint
        switch konum {
        case .alt: o = CGPoint(x: ortaX, y: alt)
        case .ust: o = CGPoint(x: ortaX, y: ust)
        case .sol: o = CGPoint(x: sol, y: ortaY)
        case .sag: o = CGPoint(x: sag, y: ortaY)
        case .solAlt: o = CGPoint(x: sol, y: alt)
        case .sagAlt: o = CGPoint(x: sag, y: alt)
        case .solUst: o = CGPoint(x: sol, y: ust)
        case .sagUst: o = CGPoint(x: sag, y: ust)
        }
        govde.frame = CGRect(origin: o, size: boy)
        ayarYerlestir()
    }
    private func ayarYerlestir() {
        guard !ayarPaneli.isHidden else { return }
        let p = ayarSira.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let pw = max(p.width + 36, 260), ph = max(p.height + 28, 90)
        let g = govde.frame
        var o: CGPoint
        switch konum {
        case .alt, .solAlt, .sagAlt: o = CGPoint(x: g.midX - pw / 2, y: g.minY - 10 - ph)
        case .ust, .solUst, .sagUst: o = CGPoint(x: g.midX - pw / 2, y: g.maxY + 10)
        case .sol: o = CGPoint(x: g.maxX + 10, y: g.midY - ph / 2)
        case .sag: o = CGPoint(x: g.minX - 10 - pw, y: g.midY - ph / 2)
        }
        o.x = min(max(o.x, 12), max(bounds.width - pw - 12, 12))
        o.y = min(max(o.y, 12), max(bounds.height - ph - 12, 12))
        ayarPaneli.frame = CGRect(origin: o, size: CGSize(width: pw, height: ph))
    }

    // MARK: Çubuğu taşıma
    @objc private func cubukSurukle(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            suruklemede = true
            ayariKapat()
            surukleBaslangic = govde.center
        case .changed:
            let t = g.translation(in: self)
            govde.center = CGPoint(x: surukleBaslangic.x + t.x, y: surukleBaslangic.y + t.y)
        case .ended, .cancelled, .failed:
            let c = govde.center
            let kolon = c.x < bounds.width / 3 ? 0 : (c.x > bounds.width * 2 / 3 ? 2 : 1)
            let satir = c.y < bounds.height / 3 ? 0 : (c.y > bounds.height * 2 / 3 ? 2 : 1)
            let yeni: Konum
            switch (kolon, satir) {
            case (0, 0): yeni = .solUst
            case (1, 0): yeni = .ust
            case (2, 0): yeni = .sagUst
            case (0, 1): yeni = .sol
            case (2, 1): yeni = .sag
            case (0, 2): yeni = .solAlt
            case (1, 2): yeni = .alt
            case (2, 2): yeni = .sagAlt
            default: yeni = konum
            }
            konum = yeni
            UserDefaults.standard.set(yeni.rawValue, forKey: "kalemKonum")
            eksenUygula()
            suruklemede = false
            UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: []) {
                self.setNeedsLayout(); self.layoutIfNeeded()
            }
        default: break
        }
    }

    // MARK: Davranış
    private func dokunuldu(_ a: Arac) {
        if a == arac, a == .kalem || a == .fosforlu || a == .silgi { ayarDugmesi(); return }
        sec(a)
        if a == .resim, let b = aracDugmeleri[a] { resimEkle?(b) }
    }
    /// Renk dairesi ya da etkin aracın tekrar dokunulması: ayar paneli açıksa kapanır, kapalıysa açılır
    private func ayarDugmesi() {
        if !ayarPaneli.isHidden { ayariKapat() } else { ayarPaneliniAc() }
    }
    /// Çizim, sayfaya dokunma ve araç değişiminde okuyucu bunu çağırır
    func ayariKapat() {
        ayarGizleme?.cancel()
        if !ayarPaneli.isHidden { ayarGoster(false) }
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
        for v in sira.arrangedSubviews where v is UIButton && v !== renkDaire && v !== menuDugmesi && !(aracDugmeleri.values.contains { $0 === v }) {
            (v as? UIButton)?.tintColor = Tema.murekkepUI
        }
        menuDugmesi.tintColor = Tema.murekkepUI
        let cizim = arac == .kalem || arac == .fosforlu
        renkDaire.isHidden = !(cizim || arac == .sec)
        let gosterilen = arac == .fosforlu ? Arac.fosforlu : Arac.kalem
        renkDaire.backgroundColor = renk(gosterilen)
        renkDaire.layer.borderColor = Tema.camKenarUI.resolvedColor(with: traitCollection).cgColor
        setNeedsLayout()
    }

    /// Silgi paneli: parça silme / çizgiyi tamamen silme + boyut
    private func silgiPaneliniAc() {
        ozelPanel.isHidden = true; kalinlikCubugu.isHidden = false
        renkSatiri.isHidden = true; silgiModu.isHidden = false
        silgiModu.selectedSegmentIndex = silgiVektor ? 1 : 0
        kalinlikCubugu.minimumValue = 6; kalinlikCubugu.maximumValue = 60
        kalinlikCubugu.value = Float(silgiBoyu)
        kalinlikCubugu.isEnabled = !silgiVektor
        kalinlikCubugu.tintColor = Tema.vurguUI
        ayarGoster(true)
        ayarGizlemeyiPlanla()
    }
    private func ayarPaneliniAc() {
        if arac == .silgi { silgiPaneliniAc(); return }
        let a: Arac = arac == .fosforlu ? .fosforlu : .kalem
        if arac == .sec { sec(a) }
        ozelPanel.isHidden = true; kalinlikCubugu.isHidden = false
        renkSatiri.isHidden = false; silgiModu.isHidden = true; kalinlikCubugu.isEnabled = true
        renkSatiri.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let ozelAcik = ozelKullan[a] == true
        for (i, (ad, hex)) in KalemPaleti.renkler(a).enumerated() {
            let secili = !ozelAcik && (renkSira[a] ?? 0) == i
            let b = UIButton(type: .custom)
            b.backgroundColor = UIColor(onaltilik: hex)
            b.layer.cornerRadius = 17
            b.layer.borderWidth = secili ? 3 : 1
            b.layer.borderColor = secili ? Tema.vurguUI.cgColor : Tema.camKenarUI.resolvedColor(with: traitCollection).cgColor
            b.widthAnchor.constraint(equalToConstant: 34).isActive = true
            b.heightAnchor.constraint(equalToConstant: 34).isActive = true
            b.accessibilityLabel = ad; b.accessibilityIdentifier = "renk-\(i)"
            b.addAction(UIAction { [weak self] _ in self?.renkSec(a, i) }, for: .touchUpInside)
            renkSatiri.addArrangedSubview(b)
        }
        // Serbest renk: renk çarkı; özel renk seçiliyse o renkle dolu daire (tekrar dokununca seçici açılır)
        let o = UIButton(type: .custom)
        o.widthAnchor.constraint(equalToConstant: 34).isActive = true
        o.heightAnchor.constraint(equalToConstant: 34).isActive = true
        o.layer.cornerRadius = 17
        if ozelAcik {
            o.backgroundColor = renk(a)
            o.layer.borderWidth = 3; o.layer.borderColor = Tema.vurguUI.cgColor
        } else {
            let cark = CAGradientLayer()
            cark.type = .conic
            cark.colors = [UIColor.red, .yellow, .green, .cyan, .blue, .magenta, .red].map { $0.cgColor }
            cark.startPoint = CGPoint(x: 0.5, y: 0.5); cark.endPoint = CGPoint(x: 0.5, y: 0)
            cark.frame = CGRect(x: 0, y: 0, width: 34, height: 34); cark.cornerRadius = 17
            o.layer.insertSublayer(cark, at: 0)
            o.layer.borderWidth = 1; o.layer.borderColor = Tema.camKenarUI.resolvedColor(with: traitCollection).cgColor
        }
        o.accessibilityLabel = "Özel renk seç"; o.accessibilityIdentifier = "renk-ozel"
        o.addAction(UIAction { [weak self] _ in self?.ozelPaneliAc(a) }, for: .touchUpInside)
        renkSatiri.addArrangedSubview(o)

        let aralik = kalinlikAraligi[a] ?? 1...14
        kalinlikCubugu.minimumValue = aralik.lowerBound; kalinlikCubugu.maximumValue = aralik.upperBound
        kalinlikCubugu.value = Float(kalinlik[a] ?? 3)
        kalinlikCubugu.tintColor = Tema.vurguUI
        ayarGoster(true)
        ayarGizlemeyiPlanla()
    }
    private func ayarGoster(_ g: Bool) {
        ayarPaneli.isHidden = !g
        setNeedsLayout(); layoutIfNeeded()
    }
    // Yalnız görünen parçalar dokunuşu alır; boş alandan dokunuşlar PDF'e geçer
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let v = super.hitTest(point, with: event)
        return v === self ? nil : v
    }
    private func renkSec(_ a: Arac, _ i: Int) {
        renkSira[a] = i
        ozelKullan[a] = false
        UserDefaults.standard.set(false, forKey: "ozelKullan-" + a.rawValue)
        guncelle(); ayarPaneliniAc(); aracDegisti?()
    }

    // MARK: Özel renk (panelin içinde: renk alanı + parlaklık + hex)
    private func ozelPaneliAc(_ a: Arac) {
        seciciArac = a
        var h: CGFloat = 0, sa: CGFloat = 0, b: CGFloat = 0, al: CGFloat = 0
        renk(a).getHue(&h, saturation: &sa, brightness: &b, alpha: &al)
        // Siyaha yakın bir renkten açılınca alan baştan simsiyah görünmesin: canlı tonlarla başla
        let acilis = b < 0.35 ? 1 : b
        renkAlani.baslat(ton: h, doygunluk: sa, parlaklik: acilis)
        parlaklikCubugu.value = Float(acilis)
        ozelGuncelle(uygula: false)
        renkSatiri.isHidden = true; kalinlikCubugu.isHidden = true; silgiModu.isHidden = true; ozelPanel.isHidden = false
        ayarGizleme?.cancel()        // renk seçilirken panel kendiliğinden kapanmaz
        setNeedsLayout(); layoutIfNeeded()
    }
    private func ozelPaneliKapat() {
        ozelPanel.isHidden = true
        ayarPaneliniAc()
    }
    private func ozelGuncelle(uygula: Bool) {
        let r = renkAlani.renk
        onizleme.backgroundColor = r
        onizleme.layer.borderColor = Tema.camKenarUI.resolvedColor(with: traitCollection).cgColor
        hexEtiketi.text = "#" + r.onaltilikDeger.uppercased()
        if uygula, let a = seciciArac { ozelAyarla(a, r) }
    }
    private func ozelAyarla(_ a: Arac, _ renk: UIColor) {
        let hex = renk.onaltilikDeger
        ozel[a] = hex; ozelKullan[a] = true
        UserDefaults.standard.set(hex, forKey: "ozelRenk-" + a.rawValue)
        UserDefaults.standard.set(true, forKey: "ozelKullan-" + a.rawValue)
        guncelle(); aracDegisti?()
    }

    private func kalinlikDegisti() {
        if arac == .silgi { silgiBoyu = CGFloat(kalinlikCubugu.value); aracDegisti?(); ayarGizlemeyiPlanla(); return }
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
                guard let self else { return }; self.silgiVektor.toggle(); self.silgiModu.selectedSegmentIndex = self.silgiVektor ? 1 : 0; self.aracDegisti?()
            },
        ]
        if yapistirilabilir?() == true {
            o.append(UIAction(title: "Yapıştır", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in self?.yapistir?() })
        }
        return o
    }
}

/// Özel renk alanı: yatay eksen ton, dikey eksen doygunluk (üstte canlı, altta soluk); parlaklık ayrı sürgüyle
final class RenkAlani: UIView {
    private(set) var ton: CGFloat = 0, doygunluk: CGFloat = 1
    var bri: CGFloat = 1 { didSet { setNeedsDisplay() } }
    var degisti: (() -> Void)?
    var renk: UIColor { UIColor(hue: ton, saturation: doygunluk, brightness: bri, alpha: 1) }
    override var intrinsicContentSize: CGSize { CGSize(width: 300, height: 130) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 12; layer.cornerCurve = .continuous; clipsToBounds = true
        isOpaque = true
        let surukle = UIPanGestureRecognizer(target: self, action: #selector(dokun(_:)))
        surukle.maximumNumberOfTouches = 1
        addGestureRecognizer(surukle)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dokun(_:))))
    }
    required init?(coder: NSCoder) { fatalError() }

    func baslat(ton: CGFloat, doygunluk: CGFloat, parlaklik: CGFloat) {
        self.ton = ton; self.doygunluk = doygunluk; bri = parlaklik
        setNeedsDisplay()
    }
    @objc private func dokun(_ g: UIGestureRecognizer) {
        let p = g.location(in: self)
        ton = min(max(p.x / max(bounds.width, 1), 0), 1)
        doygunluk = 1 - min(max(p.y / max(bounds.height, 1), 0), 1)
        setNeedsDisplay()
        degisti?()
    }
    override func draw(_ rect: CGRect) {
        guard let c = UIGraphicsGetCurrentContext(), bounds.width > 1 else { return }
        let uzay = CGColorSpaceCreateDeviceRGB()
        let serit = 3
        let n = Int((bounds.width / CGFloat(serit)).rounded(.up))
        for i in 0..<n {
            let h = CGFloat(i) / CGFloat(max(n - 1, 1))
            let renkler = [UIColor(hue: h, saturation: 1, brightness: bri, alpha: 1).cgColor, UIColor(hue: h, saturation: 0, brightness: bri, alpha: 1).cgColor] as CFArray
            guard let g = CGGradient(colorsSpace: uzay, colors: renkler, locations: [0, 1]) else { continue }
            c.saveGState()
            c.clip(to: CGRect(x: CGFloat(i * serit), y: 0, width: CGFloat(serit), height: bounds.height))
            c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: bounds.height), options: [])
            c.restoreGState()
        }
        let imlec = CGRect(x: ton * bounds.width - 9, y: (1 - doygunluk) * bounds.height - 9, width: 18, height: 18)
        c.setLineWidth(3); c.setStrokeColor(UIColor.white.cgColor); c.strokeEllipse(in: imlec)
        c.setLineWidth(1); c.setStrokeColor(UIColor.black.withAlphaComponent(0.55).cgColor); c.strokeEllipse(in: imlec.insetBy(dx: -1.5, dy: -1.5))
    }
}
