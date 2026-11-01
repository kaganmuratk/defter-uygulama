import Foundation

// Part başına kullanıcının konumu: en son çıkılan sayfa ve "Burada kaldım" ile işaretlenen sayfa (sayfa anahtarı).
// Yalnız cihazda durur (Application Support/Defter/konum.json); sunucudaki ilerleme biçimine dokunmaz. Yedeğe dahildir.
enum Konum {
    struct Kayit: Codable, Equatable {
        var son: String?       // part'tan en son çıkılan/bakılan sayfa
        var kaldim: String?    // "Burada kaldım" sayfası
    }

    static var url: URL { Depo.kok.appendingPathComponent("konum.json") }
    private static var onbellek: [String: Kayit]?

    static var tum: [String: Kayit] {
        if let o = onbellek { return o }
        let v = Depo.oku([String: Kayit].self, url) ?? [:]
        onbellek = v
        return v
    }

    static func son(_ partId: String) -> String? { tum[partId]?.son }
    static func kaldim(_ partId: String) -> String? { tum[partId]?.kaldim }

    static func sonYaz(_ partId: String, _ anahtar: String) {
        var t = tum
        var k = t[partId] ?? Kayit()
        if k.son == anahtar { return }
        k.son = anahtar
        t[partId] = k
        kaydet(t)
    }
    static func kaldimYaz(_ partId: String, _ anahtar: String?) {
        var t = tum
        var k = t[partId] ?? Kayit()
        if k.kaldim == anahtar { return }
        k.kaldim = anahtar
        t[partId] = k
        kaydet(t)
    }
    /// Silinen part'ın konumunu temizler
    static func temizle(_ partId: String) {
        var t = tum
        if t.removeValue(forKey: partId) != nil { kaydet(t) }
    }
    /// Yedekten geri yükleme sonrası diskten yeniden okunsun
    static func yenile() { onbellek = nil }

    private static func kaydet(_ t: [String: Kayit]) {
        onbellek = t
        if !Ayar.ornek { Depo.yaz(t, url) }
    }
}
