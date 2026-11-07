import UIKit
import PencilKit
import UIKit.UIGestureRecognizerSubclass

// Notability'deki gibi: çizgiyi bitirip kalemi kaldırmadan kısa süre bekleyince el çizimi düzgün şekle dönüşür
// (düz çizgi, elips/daire, üçgen, dikdörtgen ve diğer çokgenler).

/// Kalemin çizgi sonunda hareketsiz kalıp kalmadığını izler; bir dokunuşu engellemez, çizimi bozmaz.
final class DurakGozcusu: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var beklemeSuresi: TimeInterval = 0.6
    var durdu: (() -> Void)?
    private var sonKonum: CGPoint = .zero
    private var sonHareket = Date()
    private var izleniyor = false

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false; delaysTouchesBegan = false; delaysTouchesEnded = false
        delegate = self
    }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1, let t = touches.first else { return }
        sonKonum = t.location(in: view); sonHareket = Date(); izleniyor = true
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard izleniyor, let t = touches.first else { return }
        let p = t.location(in: view)
        if hypot(p.x - sonKonum.x, p.y - sonKonum.y) > 3 { sonKonum = p; sonHareket = Date() }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        let bekledi = izleniyor && Date().timeIntervalSince(sonHareket) >= beklemeSuresi
        izleniyor = false
        if bekledi { durdu?() }
        state = .failed
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { izleniyor = false; state = .failed }
    override func reset() { izleniyor = false }
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
            if d > 40, sapma / d < 0.07 { sekil = [a, b] }
        } else {
            let cx = kutu.midX, cy = kutu.midY, rx = max(kutu.width / 2, 1), ry = max(kutu.height / 2, 1)
            let yaricaplar = ham.map { hypot(($0.x - cx) / rx, ($0.y - cy) / ry) }
            let ort = yaricaplar.reduce(0, +) / CGFloat(yaricaplar.count)
            let sap = (yaricaplar.map { ($0 - ort) * ($0 - ort) }.reduce(0, +) / CGFloat(yaricaplar.count)).squareRoot()
            if ort > 0.85, ort < 1.15, sap < 0.1 {
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
