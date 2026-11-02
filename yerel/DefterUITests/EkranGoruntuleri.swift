import XCTest

// Simülatörde örnek içerikle uygulamayı gezer, her adımda ekran görüntüsü ekler (CI artifact'ına çıkarılır).
final class EkranGoruntuleri: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-ornek", "-tema", "acik"]
    }

    private func cek(_ ad: String) {
        let e = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        e.name = ad
        e.lifetime = .keepAlways
        add(e)
    }

    func testGezinti() throws {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.buttons["kitap-fizyoloji"].firstMatch.waitForExistence(timeout: 15))
        cek("01-kutuphane-dikey")
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        cek("02-kutuphane-yatay")
        XCUIDevice.shared.orientation = .portrait
        sleep(2)

        let kitap = app.buttons["kitap-fizyoloji"].firstMatch
        XCTAssertTrue(kitap.waitForExistence(timeout: 5))
        kitap.tap()
        if !app.buttons["bolum-1"].waitForExistence(timeout: 3) { kitap.tap() }
        XCTAssertTrue(app.buttons["bolum-1"].waitForExistence(timeout: 5))
        cek("03-kitap-bolumler")
        app.buttons["bolum-1"].tap()
        XCTAssertTrue(app.buttons["part-01"].waitForExistence(timeout: 5))
        cek("04-bolum-partlar")

        app.buttons["part-01"].tap()
        XCTAssertTrue(app.buttons["geri"].waitForExistence(timeout: 10))
        sleep(6)   // PDF cihazda basılıyor
        cek("05-okuyucu-dikey")

        // Örnek modda tuval her girdiyi kabul eder: parmakla bir çizgi çiz
        let pdf = app.otherElements.matching(identifier: "tuval-b0").firstMatch
        if pdf.waitForExistence(timeout: 5) {
            let bas = pdf.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.75))
            let son = pdf.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.8))
            bas.press(forDuration: 0.1, thenDragTo: son)
            sleep(1)
        }
        cek("06-okuyucu-cizim")

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        cek("07-okuyucu-yatay")
        XCUIDevice.shared.orientation = .portrait
        sleep(2)

        app.buttons["notEkle"].tap()
        sleep(2)
        cek("08-yapiskan-not-acik")
        if app.buttons["notBitti"].waitForExistence(timeout: 3) { app.buttons["notBitti"].tap() }
        sleep(1)
        cek("09-yapiskan-not-rozet")

        app.buttons["sayfaMenu"].tap()
        sleep(1)
        cek("10-sayfa-menusu")
        if app.buttons["Çizgili sayfa ekle"].exists { app.buttons["Çizgili sayfa ekle"].tap() }
        sleep(2)
        cek("11-cizgili-sayfa")

        app.buttons["geri"].tap()
        sleep(1)
        cek("12-kayit-sorusu")
        if app.buttons["Kaydet"].exists { app.alerts.buttons["Kaydet"].firstMatch.tap() }
        sleep(1)
        cek("13-kayit-sonrasi")
    }
    // Koyu tema: her ekranı yatayda gezip görüntüle (açık tema testGezinti'de görüntülenir)
    func testKoyuTema() throws {
        app.launchArguments = ["-ornek", "-tema", "koyu"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["kitap-fizyoloji"].firstMatch.waitForExistence(timeout: 15))
        sleep(1)
        cek("k1-kutuphane-yatay")
        let kitap = app.buttons["kitap-fizyoloji"].firstMatch
        if kitap.waitForExistence(timeout: 5) { kitap.tap() }
        if !app.buttons["bolum-1"].waitForExistence(timeout: 3) { kitap.tap() }
        sleep(1)
        cek("k2-kitap-yatay")
        if app.buttons["bolum-1"].exists { app.buttons["bolum-1"].tap() }
        sleep(1)
        cek("k3-bolum-yatay")
        if app.buttons["part-01"].waitForExistence(timeout: 5) { app.buttons["part-01"].tap() }
        sleep(7)
        cek("k4-okuyucu-yatay")
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        cek("k5-okuyucu-dikey")
    }

    // Kendi kitabını oluştur: yeni kitap menüsü → defter türü → ad → doğrudan okuyucu (bölüm/part adımı yok)
    func testKendiKitap() throws {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.buttons["yeniKitap"].waitForExistence(timeout: 15))
        app.buttons["yeniKitap"].tap()
        let kareli = app.buttons["Kareli defter"]
        XCTAssertTrue(kareli.waitForExistence(timeout: 5))
        cek("k0-yeni-kitap-menusu")
        kareli.tap()
        let alan = app.alerts.textFields.firstMatch
        XCTAssertTrue(alan.waitForExistence(timeout: 5))
        alan.typeText("Kimya")
        cek("k1-kitap-adi")
        app.alerts.buttons["Tamam"].tap()
        let kitap = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'kitap-k-'")).firstMatch
        XCTAssertTrue(kitap.waitForExistence(timeout: 5))
        cek("k2-kutuphane")
        kitap.tap()
        XCTAssertTrue(app.buttons["geri"].waitForExistence(timeout: 10))
        sleep(3)
        cek("k6-okuyucu")
    }
}

// Yedek mantığı: geçici klasörlerde yedekle → sil → geri yükle → karşılaştır (uygulama kendi sınavını çalıştırır)
final class YedekSinavi: XCTestCase {
    func testYedekGeriYukleme() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-yedekTesti"]
        app.launch()
        let sonuc = app.staticTexts["yedek-sonuc"]
        XCTAssertTrue(sonuc.waitForExistence(timeout: 20))
        let ek = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); ek.name = "yedek-sinavi"; ek.lifetime = .keepAlways; add(ek)
        XCTAssertEqual(sonuc.label, "YEDEK-TEST: TAMAM")
    }
}

// Vision ile metin tanıma sınavı: desteklenen diller ve el yazısı benzeri yazı tipiyle tanıma sonucu ekran görüntüsünde görünür
final class OcrSinavi: XCTestCase {
    func testOcr() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ocrTesti"]
        app.launch()
        let sonuc = app.descendants(matching: .any)["ocr-sonuc"].firstMatch
        XCTAssertTrue(sonuc.waitForExistence(timeout: 20))
        sleep(12)
        let ek = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); ek.name = "ocr-sonucu"; ek.lifetime = .keepAlways; add(ek)
        let ek2 = XCTAttachment(string: sonuc.label); ek2.name = "ocr-metin"; ek2.lifetime = .keepAlways; add(ek2)
        XCTAssertFalse(sonuc.label.contains("çalışıyor"))
    }
}

// Kalem çubuğu, çizim, çizgiye dokunarak seçme, silme ve yazı kutusu (örnek modda parmak çizebilir)
final class KalemSinavi: XCTestCase {
    var app: XCUIApplication!
    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-ornek", "-tema", "acik"]
    }
    private func cek(_ ad: String) {
        let e = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); e.name = ad; e.lifetime = .keepAlways; add(e)
    }
    func testCizimSecimYazi() throws {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.buttons["yeniKitap"].waitForExistence(timeout: 15))
        app.buttons["yeniKitap"].tap()
        app.buttons["Düz defter"].tap()
        let alan = app.alerts.textFields.firstMatch
        XCTAssertTrue(alan.waitForExistence(timeout: 5))
        alan.typeText("Deneme")
        app.alerts.buttons["Tamam"].tap()
        let kitap = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'kitap-k-'")).firstMatch
        XCTAssertTrue(kitap.waitForExistence(timeout: 5))
        kitap.tap()
        XCTAssertTrue(app.buttons["geri"].waitForExistence(timeout: 10))
        sleep(3)
        // PDFKit sayfa katmanlarını erişilebilirlik ağacında göstermez; pencere koordinatlarıyla çalışılır
        let pencere = app.windows.firstMatch
        func nokta(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate { pencere.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)) }
        XCTAssertTrue(app.buttons["arac-kalem"].waitForExistence(timeout: 5), "kalem çubuğu yok")
        app.buttons["arac-kalem"].tap()
        nokta(0.45, 0.35).press(forDuration: 0.1, thenDragTo: nokta(0.75, 0.40))
        sleep(1); cek("t1-cizim")
        app.buttons["arac-kalem"].tap(); sleep(1); cek("t2-renk-paneli")
        if app.buttons["renk-2"].exists { app.buttons["renk-2"].tap() }
        app.buttons["arac-sec"].tap()
        nokta(0.60, 0.375).tap()
        sleep(1); cek("t3-secim")
        if app.buttons["secim-sil"].exists { app.buttons["secim-sil"].tap() }
        sleep(1); cek("t4-silindi")
        app.buttons["arac-metin"].tap()
        nokta(0.50, 0.60).tap()
        sleep(2)
        // Sayfa katmanı erişilebilirlikte görünmediği için klavye odağı sorgulanamaz; yalnız ekran görüntüsü alınır
        sleep(1); cek("t5-yazi-kutusu")
        XCTAssertTrue(app.buttons["arac-metin"].exists)
    }
}

// Tur 5: klasör sistemi, serbest renk, çubuğu taşıma, sayfa paneli (ad değiştir), gezin ve görsel araçları
final class Tur5Sinavi: XCTestCase {
    var app: XCUIApplication!
    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-ornek", "-tema", "acik"]
    }
    private func cek(_ ad: String) {
        let e = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); e.name = ad; e.lifetime = .keepAlways; add(e)
    }
    func testKlasorVeOkuyucu() throws {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.buttons["yeniKitap"].waitForExistence(timeout: 15))
        app.buttons["yeniKitap"].tap()
        let klasor = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Klasör'")).firstMatch
        XCTAssertTrue(klasor.waitForExistence(timeout: 5))
        cek("u0-yeni-menu")
        klasor.tap()
        let alan = app.alerts.textFields.firstMatch
        XCTAssertTrue(alan.waitForExistence(timeout: 5))
        alan.typeText("Elektronik")
        app.alerts.buttons["Tamam"].tap()
        let kitap = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'kitap-k-'")).firstMatch
        XCTAssertTrue(kitap.waitForExistence(timeout: 5))
        kitap.tap()
        XCTAssertTrue(app.buttons["klasorEkle"].waitForExistence(timeout: 10))
        cek("u1-bos-klasor")
        // alt klasör
        app.buttons["klasorEkle"].tap()
        app.buttons["Alt klasör"].tap()
        let a2 = app.alerts.textFields.firstMatch
        XCTAssertTrue(a2.waitForExistence(timeout: 5)); a2.typeText("Vize"); app.alerts.buttons["Tamam"].tap()
        // çizgili defter
        app.buttons["klasorEkle"].tap()
        app.buttons["Çizgili defter"].tap()
        let a3 = app.alerts.textFields.firstMatch
        XCTAssertTrue(a3.waitForExistence(timeout: 5)); a3.typeText("Ders notları"); app.alerts.buttons["Tamam"].tap()
        sleep(1); cek("u2-klasor-icerigi")
        let oge = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'k-'")).firstMatch
        XCTAssertTrue(oge.waitForExistence(timeout: 5))
        oge.tap()
        XCTAssertTrue(app.buttons["geri"].waitForExistence(timeout: 10))
        sleep(3)
        cek("u3-okuyucu")
        // renk paneli + serbest renk
        app.buttons["arac-kalem"].tap(); sleep(1)
        cek("u4-renk-paneli")
        if app.buttons["renk-ozel"].exists {
            app.buttons["renk-ozel"].tap(); sleep(2); cek("u5-renk-secici")
            let alan = app.descendants(matching: .any)["renk-alani"]
            if alan.exists { alan.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.25)).tap(); sleep(1); cek("u5b-renk-secildi") }
            if app.buttons["renk-tamam"].exists { app.buttons["renk-tamam"].tap(); sleep(1); cek("u5c-renk-tamam") }
        }
        // sayfaya dokununca panel kapanmalı
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap(); sleep(1)
        cek("u6-panel-kapandi")
        // çubuğu sağa taşı
        let tut = app.descendants(matching: .any)["kalemTutamac"]
        if tut.exists {
            tut.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.2, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)))
            sleep(2); cek("u7-cubuk-sagda")
            app.descendants(matching: .any)["kalemTutamac"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.2, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.05)))
            sleep(2); cek("u8-cubuk-sol-ust")
        }
        // araçlar
        if app.buttons["arac-gezin"].exists { app.buttons["arac-gezin"].tap(); sleep(1); cek("u9-gezin") }
        if app.buttons["arac-resim"].exists { app.buttons["arac-resim"].tap(); sleep(1); cek("u10-resim-araci") }
        // sayfa paneli + ad değiştir
        app.buttons["icindekiler"].tap(); sleep(1)
        app.buttons["sayfaMenu"].tap(); sleep(1)
        if app.buttons["Çizgili sayfa ekle"].exists { app.buttons["Çizgili sayfa ekle"].tap(); sleep(1) }
        cek("u11-sayfa-paneli")
        let menu = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sayfa-menu-'")).firstMatch
        if menu.exists {
            menu.tap(); sleep(1); cek("u12-sayfa-menusu")
            if app.buttons["Adı değiştir"].exists {
                app.buttons["Adı değiştir"].tap()
                let t = app.alerts.textFields.firstMatch
                if t.waitForExistence(timeout: 3) { t.clearAndTypeText("Giriş"); app.alerts.buttons["Tamam"].tap() }
                sleep(1); cek("u13-sayfa-adi")
            }
        }
    }
}

extension XCUIElement {
    func clearAndTypeText(_ metin: String) {
        guard let eski = value as? String, !eski.isEmpty else { typeText(metin); return }
        tap()
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: eski.count))
        typeText(metin)
    }
}
