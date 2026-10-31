import Foundation
import PDFKit
import WebKit
import CryptoKit

// Part metnini cihazda PDF'e basar: her bölüm bir sayfa (yüksekliği içeriğe göre), cevaplar ayrı sayfa.
// Dizgi web sürümüyle aynı (800 px kâğıt, 21 px yazı) → eski web çizimleri birebir taşınabilir.
// Sonuç part içeriğinin özetiyle önbelleğe alınır; içerik değişmedikçe yeniden basılmaz.
@MainActor
final class PdfUretici: NSObject, WKNavigationDelegate {
    static let ortak = PdfUretici()
    static let stilSurumu = "4"
    nonisolated static let kagit: CGFloat = 800, solPay: CGFloat = 48, ustPay: CGFloat = 44, altPay: CGFloat = 64
    nonisolated static var sayfaGenislik: CGFloat { kagit + 2 * solPay }
    nonisolated static let enAzYukseklik: CGFloat = 1150   // kısa bölümlerde altta not alacak yer kalsın

    private var webView: WKWebView?
    private var yuklendi: CheckedContinuation<Void, Never>?
    private var surecler: [String: Task<(PDFDocument, [SayfaBilgi])?, Never>] = [:]

    func belge(_ part: Part) async -> (PDFDocument, [SayfaBilgi])? {
        if let s = surecler[part.id] { return await s.value }
        let t = Task { await self.uret(part) }
        surecler[part.id] = t
        let r = await t.value
        surecler[part.id] = nil
        return r
    }

    private func ozet(_ part: Part) -> String {
        let d = (try? JSONEncoder().encode(part)) ?? Data()
        return SHA256.hash(data: d + Data(Self.stilSurumu.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    private func uret(_ part: Part) async -> (PDFDocument, [SayfaBilgi])? {
        let anahtar = "\(part.id)-\(ozet(part))"
        let pdfURL = Depo.pdfler.appendingPathComponent(anahtar + ".pdf"), bilgiURL = Depo.pdfler.appendingPathComponent(anahtar + ".json")
        if let doc = PDFDocument(url: pdfURL), let bilgi = Depo.oku([SayfaBilgi].self, bilgiURL), doc.pageCount == bilgi.count { return (doc, bilgi) }

        hazirla()
        guard let web = webView else { return nil }
        var sayfalar: [(String, String, SayfaBilgi)] = []   // (başlık, html, bilgi)
        for (i, b) in part.bolumler.enumerated() {
            var html = (i == 0 ? (part.giris ?? "") : "") + b.html
            if let r = html.range(of: #"<details class="cevaplar">\s*<summary>[^<]*</summary>([\s\S]*)</details>"#, options: .regularExpression) {
                let blok = String(html[r])
                let ic = blok.replacingOccurrences(of: #"^<details class="cevaplar">\s*<summary>[^<]*</summary>"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: "</details>", with: "")
                html.removeSubrange(r)
                sayfalar.append((b.baslik, html, SayfaBilgi(anahtar: "b\(i)", baslik: b.baslik, bolumSira: i)))
                sayfalar.append(("Cevaplar", ic, SayfaBilgi(anahtar: "c\(i)", baslik: "Cevaplar · " + (b.kisa ?? b.baslik), bolumSira: i)))
            } else {
                sayfalar.append((b.baslik, html, SayfaBilgi(anahtar: "b\(i)", baslik: b.baslik, bolumSira: i)))
            }
        }
        let sonuc = PDFDocument()
        var bilgiler: [SayfaBilgi] = []
        for (baslik, govde, bilgi) in sayfalar {
            let dosya = Depo.icerik.appendingPathComponent("_sayfa.html")
            try? Self.html(baslik: baslik, govde: govde).write(to: dosya, atomically: true, encoding: .utf8)
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                yuklendi = c
                web.loadFileURL(dosya, allowingReadAccessTo: Depo.icerik)
            }
            let js = #"""
            await document.fonts.ready;
            await Promise.all([...document.images].map(async g => {
                if (!g.complete) await new Promise(r => { g.onload = g.onerror = r; });
                try { await g.decode(); } catch (e) {}
            }));
            const kok = document.querySelector('.kagit');
            const re = /(Şekil|Tablo) (\d+\.\d+[a-z]?)/g;
            const w = document.createTreeWalker(kok, NodeFilter.SHOW_TEXT);
            const dugumler = [];
            while (w.nextNode()) dugumler.push(w.currentNode);
            for (const d of dugumler) {
                if (d.parentElement.closest('h1,h2,h3,h4,.ref')) continue;
                const t = d.nodeValue; re.lastIndex = 0;
                if (!re.test(t)) continue;
                re.lastIndex = 0;
                const f = document.createDocumentFragment(); let son = 0, m;
                while ((m = re.exec(t))) {
                    f.append(t.slice(son, m.index));
                    const s = document.createElement('span'); s.className = 'ref'; s.textContent = m[0]; f.append(s);
                    son = m.index + m[0].length;
                }
                f.append(t.slice(son)); d.replaceWith(f);
            }
            await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
            const atiflar = [...document.querySelectorAll('.ref')].flatMap(s => [...s.getClientRects()].map(r => ({ ad: s.textContent, x: r.left + scrollX, y: r.top + scrollY, w: r.width, h: r.height })));
            const hedefler = {};
            document.querySelectorAll('img').forEach(g => {
                const m = /sekil-(\d+)-(\d+)([a-z]?)/.exec(g.getAttribute('src') || ''); if (!m) return;
                const y = g.getBoundingClientRect().top + scrollY, ad = 'Şekil ' + m[1] + '.' + m[2];
                if (m[3]) hedefler[ad + m[3]] = y;
                if (!(ad in hedefler)) hedefler[ad] = y;
            });
            document.querySelectorAll('h2,h3,h4').forEach(h => {
                const m = /^(Tablo \d+\.\d+)/.exec(h.textContent.trim());
                if (m) hedefler[m[1]] = h.getBoundingClientRect().top + scrollY;
            });
            return JSON.stringify({ alt: Math.ceil(kok.getBoundingClientRect().bottom), atiflar, hedefler });
            """#
            struct Olcum: Decodable { var alt: Double; var atiflar: [Atif]; var hedefler: [String: Double] }
            let ham = (try? await web.callAsyncJavaScript(js, arguments: [:], in: nil, contentWorld: .page)) as? String
            let olcum = ham.flatMap { try? JSONDecoder().decode(Olcum.self, from: Data($0.utf8)) }
            let alt = olcum?.alt ?? 1000
            var bilgi = bilgi
            bilgi.atiflar = olcum?.atiflar; bilgi.hedefler = olcum?.hedefler
            let yukseklik = max(Self.enAzYukseklik, CGFloat(alt) + Self.altPay)
            web.frame = CGRect(x: web.frame.origin.x, y: 0, width: Self.sayfaGenislik, height: yukseklik)
            let cfg = WKPDFConfiguration()
            cfg.rect = CGRect(x: 0, y: 0, width: Self.sayfaGenislik, height: yukseklik)
            let veri: Data? = await withCheckedContinuation { c in
                web.createPDF(configuration: cfg) { r in c.resume(returning: try? r.get()) }
            }
            guard let v = veri, let tek = PDFDocument(data: v), let sayfa = tek.page(at: 0) else {
                Tani.yaz("PDF sayfası basılamadı", "\(part.id) \(bilgi.anahtar)"); continue
            }
            sonuc.insert(sayfa, at: sonuc.pageCount)
            bilgiler.append(bilgi)
        }
        guard sonuc.pageCount > 0 else { return nil }
        // Eski önbellekleri temizle, yenisini yaz
        if let eski = try? FileManager.default.contentsOfDirectory(at: Depo.pdfler, includingPropertiesForKeys: nil) {
            for u in eski where u.lastPathComponent.hasPrefix(part.id + "-") { try? FileManager.default.removeItem(at: u) }
        }
        _ = sonuc.write(to: pdfURL)
        Depo.yaz(bilgiler, bilgiURL)
        return (PDFDocument(url: pdfURL) ?? sonuc, bilgiler)
    }

    private func hazirla() {
        // Yazı tipleri içerik klasörüne kopyalanır (WebView yalnız o klasörü okuyabilir)
        for ad in ["figtree-latin-wght-normal", "figtree-latin-ext-wght-normal"] {
            let hedef = Depo.icerik.appendingPathComponent(ad + ".woff2")
            if !FileManager.default.fileExists(atPath: hedef.path), let kaynak = Bundle.main.url(forResource: ad, withExtension: "woff2") {
                try? FileManager.default.copyItem(at: kaynak, to: hedef)
            }
        }
        if webView != nil { return }
        let w = WKWebView(frame: CGRect(x: 0, y: 0, width: Self.sayfaGenislik, height: 1200))
        w.navigationDelegate = self
        w.isOpaque = false
        // Görünmez ama pencere hiyerarşisinde: bazı iOS sürümleri ekran dışı görünümde görselleri basmıyor
        if let pencere = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
            w.alpha = 0.01
            w.frame.origin = CGPoint(x: -Self.sayfaGenislik - 50, y: 0)
            pencere.addSubview(w)
        }
        webView = w
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.yuklendi?.resume(); self.yuklendi = nil }
    }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.yuklendi?.resume(); self.yuklendi = nil }
    }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.yuklendi?.resume(); self.yuklendi = nil }
    }

    static func html(baslik: String, govde: String) -> String {
        let g = govde.replacingOccurrences(of: "src=\"icerik/", with: "src=\"")
        return """
        <!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=\(Int(sayfaGenislik))"><style>
        @font-face { font-family: "Figtree"; font-weight: 300 900; src: url("figtree-latin-wght-normal.woff2") format("woff2"); unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215; }
        @font-face { font-family: "Figtree"; font-weight: 300 900; src: url("figtree-latin-ext-wght-normal.woff2") format("woff2"); unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF; }
        * { box-sizing: border-box; }
        html, body { margin: 0; background: transparent; color: #15151c; -webkit-text-size-adjust: 100%; }
        .ref { text-decoration: underline; text-decoration-thickness: 1.5px; text-underline-offset: 3px; text-decoration-color: currentColor; }
        .kagit { width: \(Int(kagit))px; margin: \(Int(ustPay))px \(Int(solPay))px 0; font: 400 21px/1.7 "Figtree", -apple-system, sans-serif; letter-spacing: .002em; }
        h1 { font: 800 2.55em/1.12 "Figtree"; letter-spacing: -.03em; margin: 0 0 1.6rem; }
        h2 { font: 700 1.4rem/1.25 "Figtree"; letter-spacing: -.02em; margin: 2.2rem 0 .8rem; }
        h3 { font: 700 1.15rem/1.3 "Figtree"; margin: 1.8rem 0 .6rem; }
        p, li { max-width: 42rem; } p { margin: 0 0 1.1rem; }
        ul, ol { padding-left: 1.35rem; margin: 0 0 1.2rem; } li { margin: .35rem 0; }
        li::marker { color: #4f5bd5; font-weight: 700; }
        strong { font-weight: 700; } em, i { font-style: normal; font-weight: 600; }
        a { color: #4f5bd5; text-decoration: none; }
        code { font: .9em "Figtree"; background: #ececf1; padding: .1em .4em; border-radius: .4em; }
        pre { white-space: pre-wrap; background: #ececf1; border-radius: 12px; padding: 14px 16px; font: 17px/1.5 ui-monospace, Menlo, monospace; }
        blockquote { margin: 1.5rem 0; padding: 1rem 1.2rem; background: #e9eafb; border-radius: 1rem; font-size: 1.05rem; line-height: 1.6; }
        blockquote p:last-child { margin-bottom: 0; }
        img { display: block; width: 100%; height: auto; margin: 1.5rem 0 1.8rem; border-radius: 1rem; background: #fff; border: 1px solid #e0e0e8; }
        hr { border: 0; border-top: 1px solid #e0e0e8; margin: 2rem 0; }
        .tablo { margin: 1.4rem 0 1.7rem; border: 1px solid #e0e0e8; border-radius: 1rem; overflow: hidden; background: #fff; }
        table { border-collapse: collapse; width: 100%; font-size: .98rem; line-height: 1.5; }
        th { text-align: left; background: #ececf1; font-weight: 700; } th, td { padding: .7rem .9rem; border-bottom: 1px solid #e0e0e8; vertical-align: top; }
        tr:last-child td { border-bottom: 0; }
        </style></head><body><div class="kagit"><div class="metin"><h1>\(baslik)</h1>\(g)</div></div></body></html>
        """
    }
}
