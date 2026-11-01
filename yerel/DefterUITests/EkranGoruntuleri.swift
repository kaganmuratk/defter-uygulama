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
        let sonuc = app.staticTexts["ocr-sonuc"]
        XCTAssertTrue(sonuc.waitForExistence(timeout: 20))
        sleep(6)
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
