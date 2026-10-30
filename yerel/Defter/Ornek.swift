import Foundation

// UI testleri ve ekran görüntüleri için örnek içerik (sunucu ve anahtar gerekmez; `-ornek` argümanıyla).
// Telifli kitap metni depoya girmesin diye kendi yazdığımız kısa bir metin.
enum Ornek {
    static let plan = Plan(dersler: [
        Ders(id: "fizyoloji", baslik: "Fizyoloji", kaynak: "Silverthorn", bolumler: [
            Bolum(no: 1, baslik: "Fizyolojiye giriş", partlar: [
                PartOzet(no: 1, baslik: "Fizyoloji nedir?", kitap: "s.38-41", id: "part-01", hazir: true),
                PartOzet(no: 2, baslik: "Dört temel tema", kitap: "s.41-45", id: "part-02", hazir: true),
                PartOzet(no: 3, baslik: "Homeostaz", kitap: "s.45-49", id: "part-03", hazir: false),
            ]),
            Bolum(no: 2, baslik: "Moleküller ve hücreler", partlar: [
                PartOzet(no: 8, baslik: "Kimyasal bağlar", kitap: "s.66-70", id: "part-08", hazir: false),
            ]),
        ]),
        Ders(id: "anatomi", baslik: "Anatomi", kaynak: "Örnek kitap", bolumler: [
            Bolum(no: 1, baslik: "Giriş", partlar: [PartOzet(no: 1, baslik: "Vücut düzlemleri", kitap: nil, id: "anat-01", hazir: false)]),
        ]),
    ])

    static func part(_ id: String) -> Part? {
        let p = """
        <p><strong>Fizyoloji (physiology)</strong>, canlı bir organizmanın ve onu oluşturan parçaların normal işleyişini inceleyen bilimdir.</p>
        <p>Bu metin yalnızca uygulama testleri için yazılmış örnek bir sayfadır. Sayfa kenarlarına, boşluklara ve metnin üzerine kalemle yazılabilir.</p>
        <ul><li>Organizasyon düzeyleri</li><li>Organ sistemleri</li><li>İşlev ve mekanizma</li></ul>
        <blockquote><p>Ortaya çıkan özellik: parçalar bir araya gelince, hiçbir parçada tek başına bulunmayan yeni bir yetenek belirir.</p></blockquote>
        <div class="tablo"><table><thead><tr><th>Sistem</th><th>İşlev</th></tr></thead><tbody><tr><td>Dolaşım</td><td>Taşıma</td></tr><tr><td>Sinir</td><td>Eşgüdüm</td></tr></tbody></table></div>
        """
        let sorular = """
        <ol><li>Fizyolojiyi tanımlayınız.</li><li>İki organ sistemi sayınız.</li></ol>
        <details class="cevaplar"><summary>Cevapları göster</summary><ol><li>Canlının normal işleyişini inceleyen bilim.</li><li>Dolaşım ve sinir sistemi.</li></ol></details>
        """
        return Part(id: id, no: 1, baslik: "Fizyoloji nedir?", kitap: "s.38-41", giris: nil, bolumler: [
            PartBolum(id: "s1", baslik: "Fizyoloji nedir?", kisa: "Fizyoloji nedir?", html: p),
            PartBolum(id: "s2", baslik: "Organizasyon düzeyleri", kisa: "Organizasyon düzeyleri", html: p),
            PartBolum(id: "s3", baslik: "Değerlendirme soruları", kisa: "Değerlendirme soruları", html: sorular),
        ])
    }
}
