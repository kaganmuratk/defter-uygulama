import UIKit
import PencilKit
import UIKit.UIGestureRecognizerSubclass

// Notability'deki gibi: çizgiyi bitirip kalemi kaldırmadan kısa süre bekleyince el çizimi düzgün şekle dönüşür
// (düz çizgi, elips/daire, üçgen, dikdörtgen ve diğer çokgenler).

/// Kalemin çizgi sonunda hareketsiz kalıp kalmadığını izler; bir dokunuşu engellemez, çizimi bozmaz.
final class DurakGozcusu: UIGestureRecognizer, UIGestureRecognizerDelegate {
    // 2026-11-17 kök neden (Kağan: "kalemi kaldırmadan bekleyince şekil olmuyor"): eski sürüm yalnız KALDIRMA ANINDA
    // "son 0,6 sn hareket yok mu" diye bakıyordu; kalem kalkarken ucun yaptığı küçük kayma süreyi sıfırladığı için
    // şekil neredeyse hiç oluşmuyordu. Şimdi: kalem basılıyken 0,5 sn durursa "şekil istendi" İŞARETLENİR (görünür halka),
    // bu işaret yalnız belirgin yeni çizimle (>14 pt) bozulur; kalem kalkınca şekle çevrilir.
    var beklemeSuresi: TimeInterval = 0.5
    var durdu: ((Date) -> Void)?             // çizginin başladığı an (doğru çizgiyi bulmak için)
    private var baslangic = Date()
    private var sonKonum: CGPoint = .zero
    private var durakKonum: CGPoint = .zero
    private var izleniyor = false
    private var istendi = false
    private var zamanlayici: Timer?
    private let halka = CAShapeLayer()

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false; delaysTouchesBegan = false; delaysTouchesEnded = false
        delegate = self
        halka.fillColor = UIColor.clear.cgColor
        halka.strokeColor = Tema.vurguUI.withAlphaComponent(0.75).cgColor
        halka.lineWidth = 2.5
        halka.path = UIBezierPath(ovalIn: CGRect(x: -13, y: -13, width: 26, height: 26)).cgPath
    }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }

    private func kur() {
        zamanlayici?.invalidate()
        zamanlayici = Timer.scheduledTimer(withTimeInterval: beklemeSuresi, repeats: false) { [weak self] _ in self?.durakVar() }
    }
    private func durakVar() {
        guard izleniyor, !istendi else { return }
        istendi = true; durakKonum = sonKonum
        guard let v = view else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        halka.position = sonKonum
        halka.removeFromSuperlayer(); v.layer.addSublayer(halka)
        CATransaction.commit()
        let a = CABasicAnimation(keyPath: "transform.scale"); a.fromValue = 0.4; a.toValue = 1; a.duration = 0.18
        halka.add(a, forKey: "buyu")
    }
    private func temizle() {
        zamanlayici?.invalidate(); zamanlayici = nil
        izleniyor = false; istendi = false
        halka.removeFromSuperlayer()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1, let t = touches.first else { return }
        sonKonum = t.location(in: view); istendi = false; izleniyor = true; baslangic = Date()
        kur()
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard izleniyor, let t = touches.first else { return }
        let p = t.location(in: view)
        if istendi {
            // Durduktan sonra çizime belirgin biçimde devam edildiyse şekil isteği iptal; küçük kaymalar (kaldırma) sayılmaz
            if hypot(p.x - durakKonum.x, p.y - durakKonum.y) > 14 { istendi = false; halka.removeFromSuperlayer(); sonKonum = p; kur() }
            return
        }
        if hypot(p.x - sonKonum.x, p.y - sonKonum.y) > 3 { sonKonum = p; kur() }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        let tetikle = izleniyor && istendi
        temizle()
        if tetikle { durdu?(baslangic) }
        state = .failed
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { temizle(); state = .failed }
    override func reset() { zamanlayici?.invalidate(); zamanlayici = nil; izleniyor = false }
}

enum SekilTanima {
    /// Çizgiyi tanınan şekle çevirir; tanınmazsa nil (çizim olduğu gibi kalır).
    static func duzelt(_ s: PKStroke) -> PKStroke? {
        let ham = s.path.interpolatedPoints(by: .distance(4)).map { $0.location.applying(s.transform) }
        guard ham.count >= 8, let ilkNokta = s.path.first else { return nil }
        let boy = uzunluk(ham)
        let kutu = sinir(ham)
        let kose = hypot(kutu.width, kutu.height)
        guard boy > 40, kose > 30 else { return nil }
        let a = ham.first!, b = ham.last!
        let kapali = hypot(a.x - b.x, a.y - b.y) < max(boy * 0.18, 18)

        var sekil: [CGPoint]?
        if !kapali {
            // düz çizgi: tüm noktalar uç noktaları birleştiren doğruya yakın
            let sapma = ham.map { uzaklik($0, a, b) }.max() ?? 0
            let d = hypot(b.x - a.x, b.y - a.y)
            if d > 30, sapma / d < 0.09 { sekil = [a, b] }
        } else {
            let cx = kutu.midX, cy = kutu.midY, rx = max(kutu.width / 2, 1), ry = max(kutu.height / 2, 1)
            let yaricaplar = ham.map { hypot(($0.x - cx) / rx, ($0.y - cy) / ry) }
            let ort = yaricaplar.reduce(0, +) / CGFloat(yaricaplar.count)
            let sap = (yaricaplar.map { ($0 - ort) * ($0 - ort) }.reduce(0, +) / CGFloat(yaricaplar.count)).squareRoot()
            if ort > 0.82, ort < 1.18, sap < 0.12 {
                sekil = (0...48).map { i in
                    let t = CGFloat(i) / 48 * 2 * .pi
                    return CGPoint(x: cx + rx * cos(t), y: cy + ry * sin(t))
                }
            } else {
                var koseler = sadelestir(ham + [ham[0]], esik: kose * 0.07)
                if koseler.count > 1, let l = koseler.last, hypot(l.x - koseler[0].x, l.y - koseler[0].y) < kose * 0.05 { koseler.removeLast() }
                if (3...6).contains(koseler.count) {
                    // eksenlere yakın dörtgeni tam dikdörtgene çevir
                    if koseler.count == 4, eksenlere(koseler) {
                        koseler = [CGPoint(x: kutu.minX, y: kutu.minY), CGPoint(x: kutu.maxX, y: kutu.minY), CGPoint(x: kutu.maxX, y: kutu.maxY), CGPoint(x: kutu.minX, y: kutu.maxY)]
                    }
                    sekil = koseler + [koseler[0]]
                }
            }
        }
        guard let nokta = sekil, nokta.count >= 2 else { return nil }
        let yogun = yogunlastir(nokta)
        var pts: [PKStrokePoint] = []
        for (i, p) in yogun.enumerated() {
            pts.append(PKStrokePoint(location: p, timeOffset: Double(i) * 0.004, size: ilkNokta.size, opacity: ilkNokta.opacity, force: ilkNokta.force, azimuth: ilkNokta.azimuth, altitude: ilkNokta.altitude))
        }
        return PKStroke(ink: s.ink, path: PKStrokePath(controlPoints: pts, creationDate: s.path.creationDate), transform: .identity, mask: s.mask)
    }

    private static func uzunluk(_ p: [CGPoint]) -> CGFloat { zip(p, p.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) } }
    private static func sinir(_ p: [CGPoint]) -> CGRect {
        let xs = p.map(\.x), ys = p.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
    private static func uzaklik(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y, d = hypot(dx, dy)
        if d < 0.001 { return hypot(p.x - a.x, p.y - a.y) }
        return abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / d
    }
    /// Douglas–Peucker
    private static func sadelestir(_ p: [CGPoint], esik: CGFloat) -> [CGPoint] {
        guard p.count > 2, let a = p.first, let b = p.last else { return p }
        var en: CGFloat = 0, idx = 0
        for i in 1..<(p.count - 1) { let d = uzaklik(p[i], a, b); if d > en { en = d; idx = i } }
        if en > esik {
            let sol = sadelestir(Array(p[0...idx]), esik: esik), sag = sadelestir(Array(p[idx...]), esik: esik)
            return Array(sol.dropLast()) + sag
        }
        return [a, b]
    }
    private static func eksenlere(_ k: [CGPoint]) -> Bool {
        for i in 0..<4 {
            let a = k[i], b = k[(i + 1) % 4]
            let aci = abs(atan2(b.y - a.y, b.x - a.x)).truncatingRemainder(dividingBy: .pi / 2)
            if min(aci, .pi / 2 - aci) > 0.17 { return false }   // ~10°
        }
        return true
    }
    private static func yogunlastir(_ p: [CGPoint]) -> [CGPoint] {
        var s: [CGPoint] = [p[0]]
        for (a, b) in zip(p, p.dropFirst()) {
            let n = max(Int(hypot(b.x - a.x, b.y - a.y) / 4), 1)
            for j in 1...n { let t = CGFloat(j) / CGFloat(n); s.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)) }
        }
        return s
    }
}
