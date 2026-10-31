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
}
