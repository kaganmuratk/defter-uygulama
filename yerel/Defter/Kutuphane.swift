import SwiftUI

// Kitaplık: kitaplar → bölümler → partlar. Part açılınca okuyucu tam ekran gelir.
// Yatayda iki sütun: solda "kaldığın yer" + istatistik, sağda kitaplar ve son notlar (kenarlar boş kalmasın).
struct KutuphaneEkrani: View {
    @EnvironmentObject var icerik: IcerikYonetici
    @State private var acikPart: (PartOzet, Part)?
    @State private var ayarAcik = false
    @State private var ozet = Ozet()

    var body: some View {
        NavigationStack {
            GeometryReader { g in
                let genis = g.size.width > 900 && g.size.width > g.size.height   // yatayda iki sütun, dikeyde tek sütun
                ScrollView {
                    Group {
                        if genis {
                            HStack(alignment: .top, spacing: 44) {
                                VStack(alignment: .leading, spacing: 28) { ust; devamBolumu; istatistik }.frame(width: min(440, g.size.width * 0.4))
                                VStack(alignment: .leading, spacing: 28) { kitaplar; sonNotlar }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 28) { ust; devamBolumu; istatistik; kitaplar; sonNotlar }
                        }
                    }
                    .padding(.horizontal, genis ? 48 : 28).padding(.top, 8).padding(.bottom, 40)
                }
                .refreshable { await icerik.indir(); await Senkron.ortak.hepsi(); ozet = Ozet.hesapla(icerik) }
            }
            .background(NoktaliZemin())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { ayarAcik = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityIdentifier("ayarlar")
                }
            }
            .navigationDestination(for: Ders.self) { d in KitapEkrani(ders: d, ac: ac) }
            .navigationDestination(for: BolumSecimi.self) { s in BolumEkrani(ders: s.ders, bolum: s.bolum, ac: ac) }
        }
        .onAppear { ozet = Ozet.hesapla(icerik) }
        .onChange(of: acikPart == nil) { _, kapandi in if kapandi { ozet = Ozet.hesapla(icerik) } }
        .sheet(isPresented: $ayarAcik) { AyarEkrani() }
        .fullScreenCover(isPresented: Binding(get: { acikPart != nil }, set: { if !$0 { acikPart = nil } })) {
            if let acik = acikPart {
                OkuyucuEkrani(partOzet: acik.0, part: acik.1) { acikPart = nil }.ignoresSafeArea(.container, edges: .bottom)
            }
        }
    }

    private var ust: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.tarih()).font(Tema.etiket(12)).tracking(1.6).foregroundStyle(Tema.soluk)
            Text("Defter").font(Tema.baslik(64, .heavy)).tracking(-1.5).foregroundStyle(Tema.murekkep)
            Text("Kitabın üstüne yaz, kenarına not al, kaldığın yerden devam et.").font(.callout).foregroundStyle(Tema.soluk)
        }
    }

    @ViewBuilder private var devamBolumu: some View {
        if let d = devamEdilecek() {
            Button { ac(d.0) } label: { DevamKarti(part: d.0, ders: d.1, bolumNo: d.2, yarim: d.3, ilerleme: icerik.ilerleme[d.0.id]) }
                .buttonStyle(.plain).accessibilityIdentifier("devam")
        } else if icerik.plan == nil {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView()
                Text(icerik.hata ?? "İçerik indiriliyor…").foregroundStyle(Tema.soluk)
            }
        }
    }

    private var istatistik: some View {
        HStack(spacing: 12) {
            IstatistikKutusu(sayi: "\(ozet.bitenPart)", ust: "/\(ozet.toplamPart)", ad: "Biten part")
            IstatistikKutusu(sayi: "\(ozet.notSayisi)", ust: nil, ad: "Yapışkan not")
            IstatistikKutusu(sayi: "\(ozet.cizilenSayfa)", ust: nil, ad: "Notlu sayfa")
        }
    }

    private var kitaplar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Etiket(yazi: "Kitaplar")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 22, alignment: .top)], alignment: .leading, spacing: 26) {
                ForEach(Array((icerik.plan?.dersler ?? []).enumerated()), id: \.element.id) { i, d in
                    NavigationLink(value: d) {
                        let partlar = d.bolumler.flatMap { $0.partlar }
                        VStack(alignment: .leading, spacing: 10) {
                            KitapKapagi(ders: d, sira: i)
                            Text("\(d.bolumler.count) bölüm · \(partlar.count) part").font(Tema.etiket(11)).foregroundStyle(Tema.soluk)
                            IlerlemeCubugu(biten: partlar.filter { icerik.ilerleme[$0.id]?.durum == "bitti" }.count, toplam: partlar.count)
                        }
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("kitap-" + d.id)
                }
            }
        }
    }

    @ViewBuilder private var sonNotlar: some View {
        if !ozet.sonNotlar.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Etiket(yazi: "Son notlar")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], alignment: .leading, spacing: 16) {
                    ForEach(ozet.sonNotlar) { s in
                        Button { if let o = partOzet(s.part) { ac(o) } } label: { NotKarti(not: s.not, partAdi: partAdi(s.part)) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func ac(_ o: PartOzet) {
        guard o.hazir, let p = icerik.part(o.id) else { return }
        acikPart = (o, p)
    }
    private func partOzet(_ id: String) -> PartOzet? { icerik.plan?.dersler.flatMap { $0.bolumler.flatMap { $0.partlar } }.first { $0.id == id } }
    private func partAdi(_ id: String) -> String { partOzet(id).map { "Part \($0.no) · \($0.baslik)" } ?? id }

    // Yarım kalan en son part; yoksa sıradaki başlanmamış part
    private func devamEdilecek() -> (PartOzet, Ders, Int, Bool)? {
        guard let plan = icerik.plan else { return nil }
        let tum = plan.dersler.flatMap { d in d.bolumler.flatMap { b in b.partlar.map { ($0, d, b.no) } } }
        if let y = tum.filter({ icerik.ilerleme[$0.0.id]?.durum == "yarim" && $0.0.hazir })
            .max(by: { (icerik.ilerleme[$0.0.id]?.guncelleme ?? 0) < (icerik.ilerleme[$1.0.id]?.guncelleme ?? 0) }) { return (y.0, y.1, y.2, true) }
        if let s = tum.first(where: { $0.0.hazir && icerik.ilerleme[$0.0.id]?.durum != "bitti" }) { return (s.0, s.1, s.2, false) }
        return nil
    }

    static func tarih() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "EEEE · d MMMM"
        return f.string(from: Date()).uppercased(with: Locale(identifier: "tr_TR"))
    }
}

// Kütüphane özeti: kayıt dosyalarından notlar ve çizimler
struct Ozet {
    var bitenPart = 0, toplamPart = 0, notSayisi = 0, cizilenSayfa = 0
    struct SonNot: Identifiable { let not: YapiskanNot; let part: String; var id: String { not.id } }
    var sonNotlar: [SonNot] = []
    @MainActor static func hesapla(_ icerik: IcerikYonetici) -> Ozet {
        var o = Ozet()
        let partlar = icerik.plan?.dersler.flatMap { $0.bolumler.flatMap { $0.partlar } } ?? []
        o.toplamPart = partlar.filter { $0.hazir }.count
        o.bitenPart = partlar.filter { icerik.ilerleme[$0.id]?.durum == "bitti" }.count
        var notlar: [(YapiskanNot, String)] = []
        if Ayar.ornek {
            notlar = [(YapiskanNot(sayfa: "b0", x: 0, y: 0, yazi: "Ortaya çıkan özellik ≠ parçaların toplamı. Sınavda araba örneği!"), "part-01"),
                      (YapiskanNot(sayfa: "b1", x: 0, y: 0, renk: "mavi", yazi: "Organ sistemleri tablosunu ezberle: 10 sistem"), "part-01")]
            o.cizilenSayfa = 3
        } else {
            for p in partlar {
                let k = Depo.partKaydi(p.id)
                o.cizilenSayfa += k.cizimler.count
                notlar += k.notlar.map { ($0, p.id) }
            }
        }
        o.notSayisi = notlar.count
        o.sonNotlar = notlar.sorted { $0.0.zaman > $1.0.zaman }.prefix(6).map { SonNot(not: $0.0, part: $0.1) }
        return o
    }
}

struct BolumSecimi: Hashable { let ders: Ders; let bolum: Bolum }

struct DevamKarti: View {
    let part: PartOzet; let ders: Ders; let bolumNo: Int; let yarim: Bool; let ilerleme: Ilerleme?
    @State private var onizleme: UIImage?
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Color.white)
                if let r = onizleme { Image(uiImage: r).resizable().scaledToFit().padding(2) }
                else { VStack(spacing: 5) { ForEach(0..<9, id: \.self) { i in Capsule().fill(Color.black.opacity(0.08)).frame(height: 3).padding(.trailing, CGFloat(i % 3) * 14) } }.padding(14) }
            }
            .frame(width: 112, height: 150)
            .shadow(color: .black.opacity(0.15), radius: 8, x: 2, y: 5)
            .rotationEffect(.degrees(-2.5))
            VStack(alignment: .leading, spacing: 8) {
                Etiket(yazi: yarim ? "Kaldığın yer" : "Sıradaki", renk: Tema.vurgu)
                Text(part.baslik).font(Tema.baslik(28, .bold)).foregroundStyle(Tema.murekkep).lineLimit(2)
                Text("\(ders.baslik) · Bölüm \(bolumNo) · Part \(part.no)\(part.kitap.map { " · " + $0 } ?? "")")
                    .font(Tema.etiket(11)).foregroundStyle(Tema.soluk)
                Spacer(minLength: 6)
                HStack(spacing: 8) {
                    Text(yarim ? "Devam et" : "Başla").font(.headline)
                    Image(systemName: "arrow.right").font(.headline)
                }
                .foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 11)
                .background(Tema.vurgu, in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .background(Tema.kart, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Tema.cizgi, lineWidth: 1))
        .onAppear { onizleme = SayfaOnizleme.resim(partId: part.id, bolumSira: ilerleme?.sayfa, boy: CGSize(width: 220, height: 300)) }
    }
}

struct IstatistikKutusu: View {
    let sayi: String; let ust: String?; let ad: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(sayi).font(Tema.baslik(34, .heavy)).foregroundStyle(Tema.murekkep).monospacedDigit()
                if let u = ust { Text(u).font(Tema.etiket(13, .bold)).foregroundStyle(Tema.soluk) }
            }
            Text(ad.uppercased(with: Locale(identifier: "tr_TR"))).font(Tema.etiket(10, .bold)).tracking(1.2).foregroundStyle(Tema.soluk)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.kart.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Tema.cizgi, lineWidth: 1))
    }
}

struct NotKarti: View {
    let not: YapiskanNot; let partAdi: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(not.yazi.isEmpty ? "El yazısı not" : not.yazi).font(.system(size: 16, weight: .medium, design: .serif))
                .foregroundStyle(Color.black.opacity(0.8)).lineLimit(4).frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
            Text(partAdi.uppercased(with: Locale(identifier: "tr_TR"))).font(Tema.etiket(9, .bold)).tracking(1).foregroundStyle(Color.black.opacity(0.45)).lineLimit(1)
        }
        .padding(16)
        .background(Color(NotRenk.renk(not.renk)), in: RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.12), radius: 6, x: 1, y: 4)
        .rotationEffect(.degrees(not.id.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 2 == 0 ? -1.2 : 1.0))
    }
}

struct IlerlemeCubugu: View {
    let biten: Int; let toplam: Int
    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tema.cizgi)
                    Capsule().fill(Tema.vurgu).frame(width: toplam > 0 ? max(4, g.size.width * CGFloat(biten) / CGFloat(toplam)) : 0).opacity(biten > 0 ? 1 : 0)
                }
            }.frame(height: 4)
            Text("\(biten)/\(toplam)").font(Tema.etiket(11, .bold)).foregroundStyle(Tema.soluk).monospacedDigit()
        }
    }
}

struct KitapEkrani: View {
    @EnvironmentObject var icerik: IcerikYonetici
    let ders: Ders
    let ac: (PartOzet) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .bottom, spacing: 26) {
                    KitapKapagi(ders: ders, sira: 0).frame(width: 150)
                    VStack(alignment: .leading, spacing: 8) {
                        Etiket(yazi: "Kitap")
                        Text(ders.baslik).font(Tema.baslik(48, .heavy)).foregroundStyle(Tema.murekkep)
                        if let k = ders.kaynak { Text(k).font(Tema.etiket(13)).foregroundStyle(Tema.soluk) }
                        let partlar = ders.bolumler.flatMap { $0.partlar }
                        IlerlemeCubugu(biten: partlar.filter { icerik.ilerleme[$0.id]?.durum == "bitti" }.count, toplam: partlar.count).frame(maxWidth: 280).padding(.top, 6)
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    Etiket(yazi: "Bölümler")
                    VStack(spacing: 0) {
                        ForEach(ders.bolumler) { b in
                            NavigationLink(value: BolumSecimi(ders: ders, bolum: b)) {
                                let biten = b.partlar.filter { icerik.ilerleme[$0.id]?.durum == "bitti" }.count
                                HStack(alignment: .center, spacing: 22) {
                                    Text(String(format: "%02d", b.no)).font(Tema.etiket(30, .bold)).foregroundStyle(Tema.vurgu).frame(width: 64, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(b.baslik).font(Tema.baslik(24, .bold)).foregroundStyle(Tema.murekkep).multilineTextAlignment(.leading)
                                        IlerlemeCubugu(biten: biten, toplam: b.partlar.count).frame(maxWidth: 260)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right").font(.title3).foregroundStyle(Tema.soluk)
                                }
                                .padding(.vertical, 22).padding(.horizontal, 6).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).accessibilityIdentifier("bolum-\(b.no)")
                            Rectangle().fill(Tema.cizgi).frame(height: 1)
                        }
                    }
                    .overlay(alignment: .top) { Rectangle().fill(Tema.murekkep).frame(height: 2) }
                }
            }
            .padding(.horizontal, 48).padding(.vertical, 20).frame(maxWidth: 980, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(NoktaliZemin())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct BolumEkrani: View {
    @EnvironmentObject var icerik: IcerikYonetici
    let ders: Ders; let bolum: Bolum
    let ac: (PartOzet) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    Etiket(yazi: "\(ders.baslik) · Bölüm \(String(format: "%02d", bolum.no))")
                    Text(bolum.baslik).font(Tema.baslik(46, .heavy)).foregroundStyle(Tema.murekkep)
                    IlerlemeCubugu(biten: bolum.partlar.filter { icerik.ilerleme[$0.id]?.durum == "bitti" }.count, toplam: bolum.partlar.count)
                        .frame(maxWidth: 320).padding(.top, 4)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(bolum.partlar.enumerated()), id: \.element.id) { i, p in
                        let durum = icerik.ilerleme[p.id]?.durum
                        Button { ac(p) } label: {
                            HStack(alignment: .top, spacing: 18) {
                                VStack(spacing: 0) {
                                    Rectangle().fill(i == 0 ? Color.clear : Tema.cizgi).frame(width: 2, height: 22)
                                    ZStack {
                                        Circle().fill(durum == "bitti" ? Tema.vurgu : Tema.kart)
                                        Circle().strokeBorder(durum == nil ? Tema.murekkep.opacity(p.hazir ? 0.7 : 0.25) : Tema.vurgu, lineWidth: 2)
                                        if durum == "bitti" { Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white) }
                                        else if durum == "yarim" { Circle().trim(from: 0, to: 0.5).fill(Tema.vurgu).rotationEffect(.degrees(90)).padding(4) }
                                    }.frame(width: 24, height: 24)
                                    Rectangle().fill(i == bolum.partlar.count - 1 ? Color.clear : Tema.cizgi).frame(width: 2).frame(maxHeight: .infinity)
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("P\(String(format: "%02d", p.no))").font(Tema.etiket(11, .bold)).foregroundStyle(p.hazir ? Tema.vurgu : Tema.soluk)
                                    Text(p.baslik).font(Tema.baslik(22, .bold)).foregroundStyle(p.hazir ? Tema.murekkep : Tema.soluk)
                                    Text([p.hazir ? (durum == "bitti" ? "Bitti" : durum == "yarim" ? "Yarım" : "Başlamadı") : "Yazılıyor", p.kitap].compactMap { $0 }.joined(separator: " · ").uppercased(with: Locale(identifier: "tr_TR")))
                                        .font(Tema.etiket(10, .semibold)).tracking(1).foregroundStyle(Tema.soluk)
                                }
                                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                .background(p.hazir ? Tema.kart : Color.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Tema.cizgi, style: StrokeStyle(lineWidth: 1, dash: p.hazir ? [] : [5, 4])))
                                .padding(.vertical, 6)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .buttonStyle(.plain).disabled(!p.hazir).accessibilityIdentifier(p.id)
                    }
                }
            }
            .padding(.horizontal, 48).padding(.vertical, 20).frame(maxWidth: 860, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(NoktaliZemin())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct AyarEkrani: View {
    @EnvironmentObject var icerik: IcerikYonetici
    @EnvironmentObject var senkron: Senkron
    @Environment(\.dismiss) private var kapat
    @State private var anahtar = ""
    @State private var tani: [String] = Tani.kayitlar
    var body: some View {
        NavigationStack {
            Form {
                Section("Eşitleme") {
                    LabeledContent("Durum", value: senkron.durum)
                    Button("Şimdi eşitle") { Task { await icerik.indir(); await senkron.hepsi() } }
                }
                Section("Çevrimdışı kopya") {
                    Text(icerik.indirme.isEmpty ? (UserDefaults.standard.string(forKey: "indirme") ?? "Henüz indirilmedi; internet olunca kendiliğinden iner.") : icerik.indirme)
                }
                Section("Anahtar") {
                    SecureField("Yeni anahtar", text: $anahtar).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Kaydet") { Ayar.anahtar = anahtar; anahtar = ""; Task { await icerik.indir() } }.disabled(anahtar.isEmpty)
                }
                Section("Tanı kaydı") {
                    if tani.isEmpty { Text("Kayıt yok").foregroundStyle(.secondary) }
                    ForEach(tani, id: \.self) { Text($0).font(.caption.monospaced()) }
                    if !tani.isEmpty { Button("Kaydı temizle", role: .destructive) { Tani.temizle(); tani = [] } }
                }
            }
            .navigationTitle("Ayarlar")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { kapat() } } }
        }
    }
}
