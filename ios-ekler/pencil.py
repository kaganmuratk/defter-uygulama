# Apple Pencil köprüsü: çift dokunuş (Pencil 2 / Pro) ve sıkıştırma (Pencil Pro) → JS'e 'pencilCiftDokun' olayı.
# app.js bu olayla silgiye geçer; kalem ekrandan kalkınca kaleme döner (Kağan 2026-10-29/30).
# `npx cap add ios` sonrası, `npx cap sync ios` öncesi çalışır (workflow: .github/workflows/ipa.yml).
# Capacitor 7'nin varsayılan AppDelegate'inde webView özelliği yok: kök CAPBridgeViewController uygulama
# etkinleşince bulunur ve etkileşim onun web görünümüne eklenir.
import io
import sys

YOL = "ios/App/App/AppDelegate.swift"
CAPA = "func applicationDidBecomeActive(_ application: UIApplication) {"

KOD = '''

// MARK: - Apple Pencil köprüsü (KaganOS Defter)
@MainActor
final class PencilDinleyici: NSObject, UIPencilInteractionDelegate {
    weak var webView: WKWebView?

    private func gonder() {
        webView?.evaluateJavaScript("window.dispatchEvent(new Event('pencilCiftDokun'))", completionHandler: nil)
    }

    // iOS 17.5+: Pencil Pro/2 dokunuşu. Bu uygulanınca eski pencilInteractionDidTap çağrılmaz.
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        gonder()
    }

    // iOS 17.5+: Pencil Pro sıkıştırma; yalnız hareket bitince bir kez.
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        if squeeze.phase == .ended { gonder() }
    }

    // iOS 17.5 öncesi: Pencil 2 çift dokunuş.
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        gonder()
    }
}

@MainActor
enum PencilKoprusu {
    // UIPencilInteraction.delegate zayıf tutulur; dinleyiciyi burada canlı tut.
    static var dinleyici: PencilDinleyici?

    static func bagla(_ pencere: UIWindow?) {
        guard dinleyici == nil, let kok = bul(pencere?.rootViewController), let web = kok.webView else { return }
        let d = PencilDinleyici()
        d.webView = web
        let etkilesim = UIPencilInteraction()
        etkilesim.delegate = d
        web.addInteraction(etkilesim)
        dinleyici = d
    }

    private static func bul(_ vc: UIViewController?) -> CAPBridgeViewController? {
        guard let vc = vc else { return nil }
        if let kok = vc as? CAPBridgeViewController { return kok }
        for cocuk in vc.children {
            if let kok = bul(cocuk) { return kok }
        }
        return nil
    }
}
'''

s = io.open(YOL, encoding="utf-8").read()
if CAPA not in s:
    sys.exit("çapa yok: applicationDidBecomeActive (Capacitor şablonu değişmiş olabilir)")
if "import WebKit" not in s:
    s = s.replace("import UIKit", "import UIKit\nimport WebKit", 1)
s = s.replace(CAPA, CAPA + "\n        PencilKoprusu.bagla(window)", 1)
s += KOD
io.open(YOL, "w", encoding="utf-8").write(s)
print("AppDelegate: Apple Pencil köprüsü eklendi")
