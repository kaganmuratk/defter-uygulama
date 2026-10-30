import UIKit
import PDFKit
import PencilKit
import SwiftUI

// Okuyucu: part PDF'i (PDFKit) + her sayfanın üstünde PencilKit tuvali (PDFPageOverlayViewProvider).
// Yakınlaştırma, kaydırma, avuç reddi, kalem türleri/renk/kalınlık/silgi (PKToolPicker) Apple'dan hazır gelir.
// Kullanıcı verisi (çizimler, yapışkan notlar, eklenen sayfalar) PartKaydi'nde; çıkarken "kaydedilsin mi?" sorulur,
// arada taslak dosyasına yazılır (uygulama kapansa da kaybolmaz).
final class OkuyucuKontrol: UIViewController, PDFPageOverlayViewProvider, PKCanvasViewDelegate, PKToolPickerObserver, UIPencilInteractionDelegate {
    let partOzet: PartOzet
    let part: Part
    var kapat: (() -> Void)?

    private let pdfView = PDFView()
    private let ustCubuk = UIView()
    private let baslikEtiket = UILabel()
    private let yukleniyor = UIActivityIndicatorView(style: .large)
    private let toolPicker = PKToolPicker()
    private let paletSahibi = PaletSahibi()
    private var sayfalar: [SayfaBilgi] = []                  // belge sırasıyla
    private var anahtarlar: [ObjectIdentifier: String] = [:]  // PDFPage → sayfa anahtarı
    private var katmanlar: [String: SayfaKatmani] = [:]       // görünen sayfaların katmanları
    private var kayit = PartKaydi()
    private var kirli = false { didSet { kaydetDugmesi.isEnabled = kirli; kaydetDugmesi.alpha = kirli ? 1 : 0.45 } }
    private var notlarGizli = false
    private var paletAcik = true
    private var taslakIsi: DispatchWorkItem?
    private let kendiGeriAlma = UndoManager()
    override var undoManager: UndoManager? { kendiGeriAlma }

    // Pencil: çift dokunuş/sıkıştırma ile silgiye geçilmişse kalem ekrandan kalkınca önceki araca dön (Kağan'ın istediği davranış)
    private var ciftDokunusSilgisi = false
    private var oncekiArac: PKTool = PKInkingTool(.pen, color: .label, width: 3)
    private var sonAracDegisimi: Date = .distantPast
    private var aracDegisimOncesi: PKTool?
    private var gecerliArac: PKTool = PKInkingTool(.pen, color: .label, width: 3)

    private lazy var kaydetDugmesi = ustDugme("Kaydet", sembol: nil) { [weak self] in self?.kaydet() }

    init(partOzet: PartOzet, part: Part) {
        self.partOzet = partOzet; self.part = part
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Tema.zeminUI
        kurUstCubuk()
        kurPdf()
        view.addSubview(paletSahibi)
        yukleniyor.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(yukleniyor)
        NSLayoutConstraint.activate([yukleniyor.centerXAnchor.constraint(equalTo: view.centerXAnchor), yukleniyor.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        yukleniyor.startAnimating()
        let kalem = UIPencilInteraction()
        kalem.delegate = self
        view.addInteraction(kalem)
        toolPicker.addObserver(self)
        toolPicker.selectedTool = gecerliArac
        if #available(iOS 18.0, *) { toolPicker.showsDrawingPolicyControls = false }
        Senkron.ortak.acikPart = part.id
        Task { await yukle() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        paletiGoster(paletAcik)
    }

    // MARK: Yükleme
    private func yukle() async {
        // Önce taslak (önceki oturum kaydedilmeden kapandıysa), yoksa kalıcı kayıt
        if !Ayar.ornek, let t = Depo.oku(PartKaydi.self, Depo.taslakURL(part.id)) { kayit = t; kirli = true }
        else { kayit = Ayar.ornek ? PartKaydi() : Depo.partKaydi(part.id); kirli = false }
        guard let uretilen = await PdfUretici.ortak.belge(part) else {
            yukleniyor.stopAnimating()
            let e = UILabel(); e.text = "Sayfalar hazırlanamadı."; e.textColor = .secondaryLabel
            e.frame = view.bounds; e.textAlignment = .center; view.addSubview(e)
            return
        }
        let (doc, bilgi) = uretilen
        sayfalar = bilgi
        for (i, b) in bilgi.enumerated() { if let p = doc.page(at: i) { anahtarlar[ObjectIdentifier(p)] = b.anahtar } }
        // Eklenen boş sayfaları yerlerine koy (sırayla; bir ek sayfa başka bir ek sayfanın ardından gelebilir)
        for ek in kayit.ekSayfalar { ekSayfaYerlestir(ek, belge: doc) }
        pdfView.document = doc
        yukleniyor.stopAnimating()
        DispatchQueue.main.async { [weak self] in self?.olcekleriAyarla(); self?.kaldigiYereGit() }
    }

    private func kaldigiYereGit() {
        guard let doc = pdfView.document, let sira = IcerikYonetici.ortak.ilerleme[part.id]?.sayfa,
              let i = sayfalar.firstIndex(where: { $0.bolumSira == sira }), let p = doc.page(at: i) else { return }
        pdfView.go(to: p)
    }

    private func olcekleriAyarla() {
        let sigdir = pdfView.scaleFactorForSizeToFit
        guard sigdir > 0 else { return }
        pdfView.minScaleFactor = sigdir * 0.5
        pdfView.maxScaleFactor = sigdir * 5
        pdfView.scaleFactor = sigdir
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let oran = pdfView.scaleFactor / max(pdfView.scaleFactorForSizeToFit, 0.01)
        let sayfa = pdfView.currentPage
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self else { return }
            let sigdir = self.pdfView.scaleFactorForSizeToFit
            self.pdfView.minScaleFactor = sigdir * 0.5
            self.pdfView.maxScaleFactor = sigdir * 5
            self.pdfView.scaleFactor = sigdir * max(oran, 1)
            if let s = sayfa { self.pdfView.go(to: s) }
        }
    }

    // MARK: PDF görünümü
    private func kurPdf() {
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(pdfView, belowSubview: ustCubuk)
        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: ustCubuk.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.pageBreakMargins = UIEdgeInsets(top: 14, left: 24, bottom: 14, right: 24)
        pdfView.autoScales = false
        pdfView.backgroundColor = Tema.masaUI
        pdfView.pageShadowsEnabled = true
        pdfView.pageOverlayViewProvider = self
        pdfView.isInMarkupMode = true
        NotificationCenter.default.addObserver(self, selector: #selector(sayfaDegisti), name: .PDFViewPageChanged, object: pdfView)
    }

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        guard let anahtar = anahtarlar[ObjectIdentifier(page)] else { return nil }
        if let k = katmanlar[anahtar] { return k }
        let k = SayfaKatmani(anahtar: anahtar, sayfaBoyu: page.bounds(for: .mediaBox).size)
        k.tuval.delegate = self
        k.tuval.drawingPolicy = Ayar.ornek ? .anyInput : .pencilOnly
        k.tuval.tool = gecerliArac
        if let d = kayit.cizimler[anahtar], let cizim = try? PKDrawing(data: d) { k.tuval.drawing = cizim }
        toolPicker.addObserver(k.tuval)
        toolPicker.setVisible(paletAcik, forFirstResponder: k.tuval)
        k.notAc = { [weak self] id in self?.notuAc(id) }
        k.notTasindi = { [weak self] id, nokta in self?.notTasi(id, nokta) }
        k.notSil = { [weak self] id in self?.notSil(id) }
        k.notlariGoster(kayit.notlar.filter { $0.sayfa == anahtar }, gizli: notlarGizli)
        katmanlar[anahtar] = k
        return k
    }

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        guard let k = overlayView as? SayfaKatmani else { return }
        cizimiAl(k)
        toolPicker.removeObserver(k.tuval)
        katmanlar[k.anahtar] = nil
    }

    private func cizimiAl(_ k: SayfaKatmani) {
        let veri = k.tuval.drawing.strokes.isEmpty ? nil : k.tuval.drawing.dataRepresentation()
        if kayit.cizimler[k.anahtar] != veri { kayit.cizimler[k.anahtar] = veri }
    }

    // MARK: Çizim olayları
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard let k = canvasView.superview as? SayfaKatmani else { return }
        cizimiAl(k)
        kirli = true
        taslakPlanla()
    }
    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        if ciftDokunusSilgisi, gecerliArac is PKEraserTool {
            ciftDokunusSilgisi = false
            aracSec(oncekiArac)
        }
    }

    func toolPickerSelectedToolDidChange(_ toolPicker: PKToolPicker) {
        aracDegisimOncesi = gecerliArac
        gecerliArac = toolPicker.selectedTool
        sonAracDegisimi = Date()
        for k in katmanlar.values { k.tuval.tool = gecerliArac }
    }

    private func aracSec(_ arac: PKTool) {
        toolPicker.selectedTool = arac
        gecerliArac = arac
        for k in katmanlar.values { k.tuval.tool = arac }
    }

    // MARK: Apple Pencil çift dokunuş / Pro sıkıştırma
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) { kalemDokunusu() }
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) { kalemDokunusu() }
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        if squeeze.phase == .ended { kalemDokunusu() }
    }
    private func kalemDokunusu() {
        let once = gecerliArac
        // Sistem (araç paleti) dokunuşu kendisi işlediyse ikinci kez çevirme; yalnız "kalkınca dön" bayrağını kur
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            if Date().timeIntervalSince(self.sonAracDegisimi) < 0.4 {
                if self.gecerliArac is PKEraserTool { self.oncekiArac = self.aracDegisimOncesi ?? once; self.ciftDokunusSilgisi = true }
                else { self.ciftDokunusSilgisi = false }
                return
            }
            if self.gecerliArac is PKEraserTool { self.ciftDokunusSilgisi = false; self.aracSec(self.oncekiArac) }
            else { self.oncekiArac = self.gecerliArac; self.ciftDokunusSilgisi = true; self.aracSec(PKEraserTool(.bitmap)) }
            self.bilgiGoster(self.gecerliArac is PKEraserTool ? "Silgi" : "Kalem")
        }
    }

    // MARK: İlerleme
    @objc private func sayfaDegisti() {
        guard let p = pdfView.currentPage, let anahtar = anahtarlar[ObjectIdentifier(p)],
              let b = sayfalar.first(where: { $0.anahtar == anahtar }), let sira = b.bolumSira else { return }
        IcerikYonetici.ortak.ilerlemeYaz(part.id) { i in
            i.sayfa = sira
            var z = Set(i.ziyaret ?? []); z.insert(sira); i.ziyaret = Array(z).sorted()
            if i.durum != "bitti" { i.durum = "yarim" }
        }
    }

    // MARK: Kayıt
    private func taslakPlanla() {
        taslakIsi?.cancel()
        let is_ = DispatchWorkItem { [weak self] in
            guard let self, !Ayar.ornek else { return }
            for k in self.katmanlar.values { self.cizimiAl(k) }
            Depo.yaz(self.kayit, Depo.taslakURL(self.part.id))
        }
        taslakIsi = is_
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: is_)
    }
    private func kaydet() {
        for k in katmanlar.values { cizimiAl(k) }
        kayit.zaman = Zaman.simdi
        taslakIsi?.cancel()
        if !Ayar.ornek {
            if Depo.yaz(kayit, Depo.kayitURL(part.id)) { try? FileManager.default.removeItem(at: Depo.taslakURL(part.id)) }
            Senkron.ortak.partKaydedildi(part.id)
        }
        kirli = false
        bilgiGoster("Kaydedildi")
    }
    private func vazgec() {
        taslakIsi?.cancel()
        try? FileManager.default.removeItem(at: Depo.taslakURL(part.id))
        kirli = false
    }
    private func cik() {
        guard kirli else { bitir(); return }
        let a = UIAlertController(title: "Çizimler kaydedilsin mi?", message: "Kaydedilmezse bu oturumdaki çizimler, notlar ve eklenen sayfalar silinir.", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Kaydet", style: .default) { [weak self] _ in self?.kaydet(); self?.bitir() })
        a.addAction(UIAlertAction(title: "Vazgeç, sil", style: .destructive) { [weak self] _ in self?.vazgec(); self?.bitir() })
        a.addAction(UIAlertAction(title: "İptal", style: .cancel))
        present(a, animated: true)
    }
    private func bitir() {
        Senkron.ortak.acikPart = nil
        toolPicker.setVisible(false, forFirstResponder: paletSahibi)
        for k in katmanlar.values { toolPicker.setVisible(false, forFirstResponder: k.tuval) }
        kapat?()
    }

    // MARK: Ek sayfalar
    private func ekSayfaYerlestir(_ ek: EkSayfa, belge: PDFDocument) {
        var hedef = belge.pageCount
        for i in 0..<belge.pageCount { if let p = belge.page(at: i), anahtarlar[ObjectIdentifier(p)] == ek.sonra { hedef = i + 1; break } }
        let s = BosSayfa(desen: ek.cizgili ? .cizgili : .duz)
        anahtarlar[ObjectIdentifier(s)] = "e" + ek.id
        belge.insert(s, at: hedef)
    }
    private func sayfaEkle(_ desen: BosSayfa.Desen) {
        guard let doc = pdfView.document, let p = pdfView.currentPage, let anahtar = anahtarlar[ObjectIdentifier(p)] else { return }
        var ek = EkSayfa(sonra: anahtar)
        ek.cizgili = desen != .duz
        let s = BosSayfa(desen: desen)
        anahtarlar[ObjectIdentifier(s)] = "e" + ek.id
        doc.insert(s, at: doc.index(for: p) + 1)
        kayit.ekSayfalar.append(ek)
        kirli = true; taslakPlanla()
        pdfView.go(to: s)
    }
    private func sayfaSil() {
        guard let doc = pdfView.document, let p = pdfView.currentPage, let anahtar = anahtarlar[ObjectIdentifier(p)], anahtar.hasPrefix("e") else { return }
        let id = String(anahtar.dropFirst())
        let onceki = kayit.ekSayfalar.first(where: { $0.id == id })?.sonra ?? ""
        for i in kayit.ekSayfalar.indices where kayit.ekSayfalar[i].sonra == anahtar { kayit.ekSayfalar[i].sonra = onceki }
        kayit.ekSayfalar.removeAll { $0.id == id }
        kayit.cizimler[anahtar] = nil
        kayit.notlar.removeAll { $0.sayfa == anahtar }
        doc.removePage(at: doc.index(for: p))
        kirli = true; taslakPlanla()
    }

    // MARK: Yapışkan notlar
    private func notEkle() {
        guard let p = pdfView.currentPage, let anahtar = anahtarlar[ObjectIdentifier(p)] else { return }
        let merkez = CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY)
        let pdfNokta = pdfView.convert(merkez, to: p)
        let boy = p.bounds(for: .mediaBox)
        let x = min(max(pdfNokta.x, 30), boy.width - 30), y = min(max(boy.height - pdfNokta.y, 30), boy.height - 30)
        let not = YapiskanNot(sayfa: anahtar, x: Double(x), y: Double(y))
        kayit.notlar.append(not)
        kirli = true; taslakPlanla()
        katmanlar[anahtar]?.notlariGoster(kayit.notlar.filter { $0.sayfa == anahtar }, gizli: false)
        notlarGizli = false
        notuAc(not.id)
    }
    private func notuAc(_ id: String) {
        guard let not = kayit.notlar.first(where: { $0.id == id }) else { return }
        let ed = NotEditoru(not: not)
        ed.bitti = { [weak self] yeni in
            guard let self, let i = self.kayit.notlar.firstIndex(where: { $0.id == id }) else { return }
            if self.kayit.notlar[i] != yeni { self.kayit.notlar[i] = yeni; self.kirli = true; self.taslakPlanla() }
            self.katmanlar[yeni.sayfa]?.notlariGoster(self.kayit.notlar.filter { $0.sayfa == yeni.sayfa }, gizli: self.notlarGizli)
            self.paletiGoster(self.paletAcik)
        }
        ed.sil = { [weak self] in self?.notSil(id) }
        ed.modalPresentationStyle = .formSheet
        ed.preferredContentSize = CGSize(width: 560, height: 620)
        present(ed, animated: true)
    }
    private func notTasi(_ id: String, _ nokta: CGPoint) {
        guard let i = kayit.notlar.firstIndex(where: { $0.id == id }) else { return }
        kayit.notlar[i].x = Double(nokta.x); kayit.notlar[i].y = Double(nokta.y)
        kirli = true; taslakPlanla()
    }
    private func notSil(_ id: String) {
        guard let not = kayit.notlar.first(where: { $0.id == id }) else { return }
        kayit.notlar.removeAll { $0.id == id }
        kirli = true; taslakPlanla()
        katmanlar[not.sayfa]?.notlariGoster(kayit.notlar.filter { $0.sayfa == not.sayfa }, gizli: notlarGizli)
    }
    private func notlariDegistir() {
        notlarGizli.toggle()
        for (anahtar, k) in katmanlar { k.notlariGoster(kayit.notlar.filter { $0.sayfa == anahtar }, gizli: notlarGizli) }
        bilgiGoster(notlarGizli ? "Notlar gizlendi" : "Notlar gösteriliyor")
    }

    // MARK: Araç paleti
    private func paletiGoster(_ acik: Bool) {
        paletAcik = acik
        toolPicker.setVisible(acik, forFirstResponder: paletSahibi)
        for k in katmanlar.values { toolPicker.setVisible(acik, forFirstResponder: k.tuval) }
        if acik { paletSahibi.becomeFirstResponder() }
    }

    // MARK: Üst çubuk
    private func kurUstCubuk() {
        ustCubuk.translatesAutoresizingMaskIntoConstraints = false
        ustCubuk.backgroundColor = Tema.zeminUI
        view.addSubview(ustCubuk)
        let cizgi = UIView(); cizgi.backgroundColor = UIColor.separator; cizgi.translatesAutoresizingMaskIntoConstraints = false
        ustCubuk.addSubview(cizgi)

        let geri = ustDugme("Geri", sembol: "chevron.left") { [weak self] in self?.cik() }
        geri.accessibilityIdentifier = "geri"
        baslikEtiket.text = "Part \(part.no) · \(part.baslik)"
        baslikEtiket.font = .systemFont(ofSize: 17, weight: .semibold)
        baslikEtiket.textColor = .secondaryLabel
        baslikEtiket.lineBreakMode = .byTruncatingTail
        baslikEtiket.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let icindekiler = UIButton(type: .system)
        icindekiler.setImage(UIImage(systemName: "list.bullet"), for: .normal)
        icindekiler.showsMenuAsPrimaryAction = true
        icindekiler.menu = UIMenu(title: "Bölümler", children: [UIDeferredMenuElement.uncached { [weak self] tamam in
            guard let self, let doc = self.pdfView.document else { tamam([]); return }
            var ogeler: [UIMenuElement] = []
            for i in 0..<doc.pageCount {
                guard let p = doc.page(at: i), let a = self.anahtarlar[ObjectIdentifier(p)] else { continue }
                let ad = self.sayfalar.first(where: { $0.anahtar == a })?.baslik ?? "Not sayfası"
                ogeler.append(UIAction(title: ad, image: UIImage(systemName: a.hasPrefix("e") ? "doc" : (a.hasPrefix("c") ? "checkmark.circle" : "text.alignleft"))) { [weak self] _ in self?.pdfView.go(to: p) })
            }
            tamam(ogeler)
        }])
        icindekiler.accessibilityIdentifier = "icindekiler"

        let kalem = ikonDugme("pencil.tip.crop.circle", ad: "Kalem paleti") { [weak self] in guard let self else { return }; self.paletiGoster(!self.paletAcik) }
        let geriAl = ikonDugme("arrow.uturn.backward", ad: "Geri al") { [weak self] in self?.kendiGeriAlma.undo() }
        let yinele = ikonDugme("arrow.uturn.forward", ad: "Yinele") { [weak self] in self?.kendiGeriAlma.redo() }
        let not = ikonDugme("note.text.badge.plus", ad: "Yapışkan not") { [weak self] in self?.notEkle() }
        not.accessibilityIdentifier = "notEkle"

        let sayfaMenu = UIButton(type: .system)
        sayfaMenu.setImage(UIImage(systemName: "doc.badge.plus"), for: .normal)
        sayfaMenu.showsMenuAsPrimaryAction = true
        sayfaMenu.accessibilityIdentifier = "sayfaMenu"
        sayfaMenu.menu = UIMenu(title: "Sayfa", children: [
            UIAction(title: "Çizgili sayfa ekle", image: UIImage(systemName: "line.3.horizontal")) { [weak self] _ in self?.sayfaEkle(.cizgili) },
            UIAction(title: "Kareli sayfa ekle", image: UIImage(systemName: "squareshape.split.3x3")) { [weak self] _ in self?.sayfaEkle(.kareli) },
            UIAction(title: "Noktalı sayfa ekle", image: UIImage(systemName: "circle.grid.3x3")) { [weak self] _ in self?.sayfaEkle(.noktali) },
            UIAction(title: "Düz sayfa ekle", image: UIImage(systemName: "doc")) { [weak self] _ in self?.sayfaEkle(.duz) },
            UIMenu(options: .displayInline, children: [
                UIAction(title: "Notları gizle / göster", image: UIImage(systemName: "eye.slash")) { [weak self] _ in self?.notlariDegistir() },
                UIAction(title: "Bu not sayfasını sil", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.sayfaSil() },
            ]),
        ])

        let bitir = ikonDugme("checkmark.seal", ad: "Bitirdim") { [weak self] in
            guard let self else { return }
            let bitti = IcerikYonetici.ortak.ilerleme[self.part.id]?.durum == "bitti"
            IcerikYonetici.ortak.ilerlemeYaz(self.part.id) { $0.durum = bitti ? "yarim" : "bitti" }
            self.bilgiGoster(bitti ? "Yarım olarak işaretlendi" : "Part bitti olarak işaretlendi")
        }
        kirli = false

        let sol = UIStackView(arrangedSubviews: [geri, baslikEtiket]); sol.spacing = 8; sol.alignment = .center
        let sag = UIStackView(arrangedSubviews: [icindekiler, sayfaMenu, not, geriAl, yinele, kalem, bitir, kaydetDugmesi]); sag.spacing = 6; sag.alignment = .center
        for v in [sol, sag] { v.translatesAutoresizingMaskIntoConstraints = false; ustCubuk.addSubview(v) }
        NSLayoutConstraint.activate([
            ustCubuk.topAnchor.constraint(equalTo: view.topAnchor),
            ustCubuk.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ustCubuk.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ustCubuk.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 56),
            sol.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            sol.bottomAnchor.constraint(equalTo: ustCubuk.bottomAnchor, constant: -8),
            sol.heightAnchor.constraint(equalToConstant: 40),
            sag.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            sag.centerYAnchor.constraint(equalTo: sol.centerYAnchor),
            sol.trailingAnchor.constraint(lessThanOrEqualTo: sag.leadingAnchor, constant: -12),
            cizgi.leadingAnchor.constraint(equalTo: ustCubuk.leadingAnchor),
            cizgi.trailingAnchor.constraint(equalTo: ustCubuk.trailingAnchor),
            cizgi.bottomAnchor.constraint(equalTo: ustCubuk.bottomAnchor),
            cizgi.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
        ])
    }

    private func ikonDugme(_ sembol: String, ad: String, _ eylem: @escaping () -> Void) -> UIButton {
        let b = UIButton(type: .system, primaryAction: UIAction { _ in eylem() })
        b.setImage(UIImage(systemName: sembol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)), for: .normal)
        b.accessibilityLabel = ad
        b.widthAnchor.constraint(equalToConstant: 42).isActive = true
        b.heightAnchor.constraint(equalToConstant: 42).isActive = true
        return b
    }
    private func ustDugme(_ yazi: String, sembol: String?, _ eylem: @escaping () -> Void) -> UIButton {
        var c = UIButton.Configuration.plain()
        c.title = yazi
        if let s = sembol { c.image = UIImage(systemName: s, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)); c.imagePadding = 4 }
        c.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 10)
        if yazi == "Kaydet" { c = .filled(); c.title = yazi; c.cornerStyle = .capsule; c.baseBackgroundColor = Tema.vurguUI }
        let b = UIButton(configuration: c, primaryAction: UIAction { _ in eylem() })
        b.accessibilityIdentifier = yazi
        return b
    }

    private let bilgi = UILabel()
    private func bilgiGoster(_ yazi: String) {
        if bilgi.superview == nil {
            bilgi.font = .systemFont(ofSize: 15, weight: .semibold)
            bilgi.textColor = .systemBackground
            bilgi.backgroundColor = .label
            bilgi.textAlignment = .center
            bilgi.layer.cornerRadius = 16; bilgi.clipsToBounds = true
            view.addSubview(bilgi)
        }
        bilgi.text = yazi
        let boy = bilgi.intrinsicContentSize
        bilgi.frame = CGRect(x: (view.bounds.width - boy.width - 32) / 2, y: view.safeAreaInsets.top + 66, width: boy.width + 32, height: 34)
        bilgi.alpha = 1
        UIView.animate(withDuration: 0.3, delay: 1.4) { self.bilgi.alpha = 0 }
    }
}

// Araç paleti görünürlüğü için görünmez ilk yanıtlayıcı
final class PaletSahibi: UIView {
    override var canBecomeFirstResponder: Bool { true }
}

// Bir PDF sayfasının üstündeki katman: kalem tuvali + yapışkan not rozetleri.
final class SayfaKatmani: UIView {
    let anahtar: String
    let tuval = PKCanvasView()
    var notAc: ((String) -> Void)?
    var notTasindi: ((String, CGPoint) -> Void)?
    var notSil: ((String) -> Void)?
    private var rozetler: [String: NotRozeti] = [:]

    init(anahtar: String, sayfaBoyu: CGSize) {
        self.anahtar = anahtar
        super.init(frame: CGRect(origin: .zero, size: sayfaBoyu))
        backgroundColor = .clear
        tuval.backgroundColor = .clear
        tuval.isOpaque = false
        tuval.isScrollEnabled = false
        tuval.translatesAutoresizingMaskIntoConstraints = false
        tuval.accessibilityIdentifier = "tuval-" + anahtar
        addSubview(tuval)
        NSLayoutConstraint.activate([
            tuval.topAnchor.constraint(equalTo: topAnchor), tuval.bottomAnchor.constraint(equalTo: bottomAnchor),
            tuval.leadingAnchor.constraint(equalTo: leadingAnchor), tuval.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func notlariGoster(_ notlar: [YapiskanNot], gizli: Bool) {
        for r in rozetler.values { r.removeFromSuperview() }
        rozetler = [:]
        guard !gizli else { return }
        for n in notlar {
            let r = NotRozeti(not: n)
            r.center = CGPoint(x: n.x, y: n.y)
            r.ac = { [weak self] in self?.notAc?(n.id) }
            r.sil = { [weak self] in self?.notSil?(n.id) }
            r.tasindi = { [weak self] p in self?.notTasindi?(n.id, p) }
            addSubview(r)
            rozetler[n.id] = r
        }
    }
}

// Sayfa üstündeki katlanmış yapışkan not: dokununca açılır, parmakla sürüklenir, basılı tutunca silinir.
final class NotRozeti: UIView, UIContextMenuInteractionDelegate {
    var ac: (() -> Void)?
    var sil: (() -> Void)?
    var tasindi: ((CGPoint) -> Void)?
    init(not: YapiskanNot) {
        super.init(frame: CGRect(x: 0, y: 0, width: 46, height: 46))
        backgroundColor = NotRenk.renk(not.renk)
        layer.cornerRadius = 6
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22; layer.shadowRadius = 5; layer.shadowOffset = CGSize(width: 0, height: 3)
        transform = CGAffineTransform(rotationAngle: -0.05)
        let ikon = UIImageView(image: UIImage(systemName: (not.yazi.isEmpty && not.cizim == nil) ? "square.and.pencil" : "text.alignleft"))
        ikon.tintColor = UIColor(white: 0.15, alpha: 0.75)
        ikon.frame = bounds.insetBy(dx: 12, dy: 12)
        ikon.contentMode = .scaleAspectFit
        addSubview(ikon)
        // Katlanmış köşe
        let kose = CAShapeLayer()
        let yol = UIBezierPath(); yol.move(to: CGPoint(x: 34, y: 46)); yol.addLine(to: CGPoint(x: 46, y: 34)); yol.addLine(to: CGPoint(x: 34, y: 34)); yol.close()
        kose.path = yol.cgPath; kose.fillColor = UIColor(white: 0, alpha: 0.12).cgColor
        layer.addSublayer(kose)
        accessibilityIdentifier = "not-rozeti"
        isAccessibilityElement = true; accessibilityLabel = "Yapışkan not"
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dokun)))
        let surukle = UIPanGestureRecognizer(target: self, action: #selector(surukle(_:)))
        surukle.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        addGestureRecognizer(surukle)
        addInteraction(UIContextMenuInteraction(delegate: self))
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func dokun() { ac?() }
    @objc private func surukle(_ g: UIPanGestureRecognizer) {
        guard let ust = superview else { return }
        let t = g.translation(in: ust)
        center = CGPoint(x: min(max(center.x + t.x, 23), ust.bounds.width - 23), y: min(max(center.y + t.y, 23), ust.bounds.height - 23))
        g.setTranslation(.zero, in: ust)
        if g.state == .ended { tasindi?(center) }
    }
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "Aç", image: UIImage(systemName: "arrow.up.left.and.arrow.down.right")) { _ in self?.ac?() },
                UIAction(title: "Notu sil", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in self?.sil?() },
            ])
        }
    }
}

enum NotRenk {
    static let secenekler: [(String, String)] = [("sari", "ffe27a"), ("pembe", "ffb3c8"), ("mavi", "a8d8ff"), ("yesil", "b5ec9f"), ("turuncu", "ffc58a"), ("mor", "d6c2ff")]
    static func renk(_ ad: String) -> UIColor { UIColor(onaltilik: secenekler.first { $0.0 == ad }?.1 ?? "ffe27a") }
}

// Kullanıcının eklediği boş sayfa: desenli kâğıt (çizgili, kareli, noktalı, düz)
final class BosSayfa: PDFPage {
    enum Desen { case cizgili, kareli, noktali, duz }
    let desen: Desen
    init(desen: Desen) {
        self.desen = desen
        super.init()
        setBounds(CGRect(x: 0, y: 0, width: PdfUretici.sayfaGenislik, height: PdfUretici.enAzYukseklik), for: .mediaBox)
    }
    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        let r = bounds(for: box)
        context.setFillColor(UIColor.white.cgColor)
        context.fill(r)
        let aralik: CGFloat = 36
        switch desen {
        case .duz: break
        case .cizgili:
            context.setStrokeColor(UIColor(onaltilik: "c9d3e6").cgColor); context.setLineWidth(0.8)
            var y = r.maxY - 110
            while y > r.minY + 40 { context.move(to: CGPoint(x: r.minX + 48, y: y)); context.addLine(to: CGPoint(x: r.maxX - 48, y: y)); y -= aralik }
            context.strokePath()
            context.setStrokeColor(UIColor(onaltilik: "f2b8b5").cgColor); context.setLineWidth(1)
            context.move(to: CGPoint(x: r.minX + 96, y: r.minY + 30)); context.addLine(to: CGPoint(x: r.minX + 96, y: r.maxY - 30)); context.strokePath()
        case .kareli:
            context.setStrokeColor(UIColor(onaltilik: "dbe2ee").cgColor); context.setLineWidth(0.6)
            var x = r.minX + 24; while x < r.maxX { context.move(to: CGPoint(x: x, y: r.minY)); context.addLine(to: CGPoint(x: x, y: r.maxY)); x += 24 }
            var y = r.minY + 24; while y < r.maxY { context.move(to: CGPoint(x: r.minX, y: y)); context.addLine(to: CGPoint(x: r.maxX, y: y)); y += 24 }
            context.strokePath()
        case .noktali:
            context.setFillColor(UIColor(onaltilik: "b9c3d6").cgColor)
            var y = r.minY + 24
            while y < r.maxY { var x = r.minX + 24; while x < r.maxX { context.fillEllipse(in: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)); x += 24 }; y += 24 }
        }
    }
}

// SwiftUI köprüsü
struct OkuyucuEkrani: UIViewControllerRepresentable {
    let partOzet: PartOzet
    let part: Part
    let kapat: () -> Void
    func makeUIViewController(context: Context) -> OkuyucuKontrol {
        let k = OkuyucuKontrol(partOzet: partOzet, part: part)
        k.kapat = kapat
        return k
    }
    func updateUIViewController(_ uiViewController: OkuyucuKontrol, context: Context) {}
}
