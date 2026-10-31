import Foundation

// "Şekil 1.3" / "Tablo 1.1" atıfının hangi part'ta olduğunu bulur (görsel adı ya da "Tablo N.M" başlığı).
@MainActor
enum AtifIndeksi {
    private static var onbellek: [String: String] = [:]

    static func temel(_ ad: String) -> String { ad.replacingOccurrences(of: "[a-z]$", with: "", options: .regularExpression) }

    static func partBul(_ ad: String) -> String? {
        if onbellek.isEmpty { onbellek = kur() }
        return onbellek[ad] ?? onbellek[temel(ad)]
    }

    private static func kur() -> [String: String] {
        var d: [String: String] = [:]
        guard let plan = IcerikYonetici.ortak.plan,
              let resim = try? NSRegularExpression(pattern: #"sekil-(\d+)-(\d+)([a-z]?)"#),
              let tablo = try? NSRegularExpression(pattern: #"<h[2-4][^>]*>\s*(Tablo \d+\.\d+)"#) else { return d }
        for o in plan.dersler.flatMap({ $0.bolumler.flatMap { $0.partlar } }) where o.hazir {
            guard let p = IcerikYonetici.ortak.part(o.id) else { continue }
            let html = ([p.giris ?? ""] + p.bolumler.map { $0.html }).joined()
            let aralik = NSRange(html.startIndex..., in: html)
            func al(_ m: NSTextCheckingResult, _ i: Int) -> String { Range(m.range(at: i), in: html).map { String(html[$0]) } ?? "" }
            for m in resim.matches(in: html, range: aralik) {
                let ad = "Şekil \(al(m, 1)).\(al(m, 2))"
                if d[ad] == nil { d[ad] = o.id }
                if !al(m, 3).isEmpty, d[ad + al(m, 3)] == nil { d[ad + al(m, 3)] = o.id }
            }
            for m in tablo.matches(in: html, range: aralik) {
                let ad = al(m, 1)
                if d[ad] == nil { d[ad] = o.id }
            }
        }
        return d
    }
}
