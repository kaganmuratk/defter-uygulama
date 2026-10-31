import SwiftUI
import UniformTypeIdentifiers

// Kitaplık: ana ekran (bölüm paneli + kitaplar) → kitap (bölümler) → bölüm (part'lar) → okuyucu (tam ekran).
// Yatayda iki sütun, dikeyde tek sütun. Cam kartlar genel atmosfer görselinin üstünde durur.

struct BolumSecimi: Hashable { let ders: Ders; let bolum: Bolum }

// "Kalınan yer": yalnız okuyucuda "Burada kaldım" ile elle işaretlenen part. İşaret yoksa kalınan yer gösterilmez;
// panel, bitmemiş ilk bölümü açar.
struct DevamYeri {
    let part: PartOzet?
    let ders: Ders
    let bolum: Bolum
    let yarim: Bool

    @MainActor static func bul(_ icerik: IcerikYonetici) -> DevamYeri? {
        guard let plan = icerik.plan else { return nil }
        var tum: [DevamYeri] = []
        for d in plan.dersler { for b in d.bolumler { for p in b.partlar where p.hazir { tum.append(DevamYeri(part: p, ders: d, bolum: b, yarim: false)) } } }
        let yarimlar = tum.filter { icerik.ilerleme[$0.part?.id ?? ""]?.durum == "yarim" }
        if let y = yarimlar.max(by: { (icerik.ilerleme[$0.part?.id ?? ""]?.guncelleme ?? 0) < (icerik.ilerleme[$1.part?.id ?? ""]?.guncelleme ?? 0) }) {
            return DevamYeri(part: y.part, ders: y.ders, bolum: y.bolum, yarim: true)
        }
        guard let ilk = tum.first(where: { icerik.ilerleme[$0.part?.id ?? ""]?.durum != "bitti" }) ?? tum.first else { return nil }
        return DevamYeri(part: nil, ders: ilk.ders, bolum: ilk.bolum, yarim: false)
    }
}

// Part içindeki bölüm başlığı sayısı (önbellekli)
@MainActor enum PartBilgisi {
    private static var sayilar: [String: Int] = [:]
    static func bolumSayisi(_ id: String) -> Int? {
        if let n = sayilar[id] { return n }
        guard let n = IcerikYonetici.ortak.part(id)?.bolumler.count else { return nil }
        sayilar[id] = n
        return n
    }
}

struct DurumDairesi: View {
    let durum: String?
    let no: Int
    var boy: CGFloat = 32
    var vurgulu = false
    var body: some View {
        ZStack {
            if durum == "bitti" {
                Circle().fill(Tema.dolgu)
                Image(systemName: "checkmark").font(.system(size: boy * 0.4, weight: .heavy)).foregroundStyle(Tema.dolguUstu)
            } else if durum == "yarim" {
                Circle().strokeBorder(Tema.vurgu, lineWidth: 1.6)
                Circle().trim(from: 0, to: 0.5).fill(Tema.vurgu).rotationEffect(.degrees(90)).padding(boy * 0.14)
            } else {
                Circle().strokeBorder(vurgulu ? Tema.kartYazi.opacity(0.55) : Tema.soluk, lineWidth: 1.5)
                Text("\(no)").font(Tema.yazi(boy * 0.4, .semibold)).foregroundStyle(vurgulu ? Tema.kartYazi.opacity(0.6) : Tema.soluk)
            }
        }
        .frame(width: boy, height: boy)
    }
}

struct IlerlemeHalkasi: View {
    let biten: Int; let toplam: Int
    var body: some View {
        let oran: CGFloat = toplam > 0 ? CGFloat(biten) / CGFloat(toplam) : 0
        ZStack {
            Circle().stroke(Tema.soluk.opacity(0.28), lineWidth: 6)
            Circle().trim(from: 0, to: max(oran, biten > 0 ? 0.04 : 0)).stroke(Tema.dolgu, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
            Text("\(biten)/\(toplam)").font(Tema.yazi(14, .semibold)).foregroundStyle(Tema.murekkep).monospacedDigit()
        }
        .frame(width: 66, height: 66)
    }
}

struct GeriDugmesi: View {
    let ad: String
    @Environment(\.dismiss) private var kapat
    var body: some View {
        Button { kapat() } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold))
                Text(ad).font(Tema.yazi(14, .semibold))
            }
            .foregroundStyle(Tema.murekkep).padding(.leading, 12).padding(.trailing, 18).padding(.vertical, 10).camYuzey(24)
        }
        .buttonStyle(.plain).accessibilityIdentifier("geri-liste")
    }
}

struct KutuphaneEkrani: View {
    @EnvironmentObject var icerik: IcerikYonetici
    @State private var acikPart: (PartOzet, Part)?
    @State private var acikHedef: String?
    @State private var ayarAcik = false
    @State private var adIstegi: AdIstegi?
    @State private var silIstegi: SilIstegi?

    var body: some View {
        NavigationStack {
            GeometryReader { g in
                let genis = g.size.width > 900 && g.size.width > g.size.height   // yatayda iki sütun, dikeyde tek sütun
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        ust
                        if genis {
                            HStack(alignment: .top, spacing: 38) {
                                bolumPaneli.frame(width: min(640, g.size.width * 0.52))
                                kitaplar
                            }
                        } else {
                            bolumPaneli
                            kitaplar
                        }
                    }
                    .padding(.horizontal, genis ? 52 : 26).padding(.vertical, 30)
                }
                .refreshable { await icerik.indir(); await Senkron.ortak.hepsi() }
            }
            .background(Atmosfer())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Ders.self) { d in KitapEkrani(ders: d, ac: ac) }
            .navigationDestination(for: BolumSecimi.self) { s in BolumEkrani(ders: s.ders, bolum: s.bolum, ac: ac) }
        }
        .sheet(isPresented: $ayarAcik) { AyarEkrani() }
        .adSorusu($adIstegi).silOnayi($silIstegi)
        .fullScreenCover(isPresented: Binding(get: { acikPart != nil }, set: { if !$0 { acikPart = nil } })) {
            if let acik = acikPart {
                OkuyucuEkrani(partOzet: acik.0, part: acik.1, kapat: { acikPart = nil; acikHedef = nil },
                              atla: { id, hedef in
                                  guard let o = partOzet(id), let p = icerik.part(id) else { return }
                                  acikHedef = hedef; acikPart = (o, p)
                              }, hedef: acikHedef)
                    .id(acik.1.id).ignoresSafeArea(.container, edges: .bottom)
            }
        }
    }

    private var ust: some View {
        HStack {
            Text("Defter").font(Tema.baslik(40, .semibold)).foregroundStyle(Tema.murekkep)
            Spacer()
            Button { ayarAcik = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 19, weight: .medium)).foregroundStyle(Tema.murekkep)
                    .frame(width: 48, height: 48).camYuzey(24)
            }
            .buttonStyle(.plain).accessibilityIdentifier("ayarlar")
        }
    }

    // Sol panel: kalınan yerin bölümü ve part listesi
    @ViewBuilder private var bolumPaneli: some View {
        if let d = DevamYeri.bul(icerik) {
            BolumPaneli(devam: d, ac: ac)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ProgressView()
                Text(icerik.hata ?? "İçerik indiriliyor…").font(Tema.yazi(15)).foregroundStyle(Tema.soluk)
            }
            .padding(28).frame(maxWidth: .infinity, alignment: .leading).camYuzey(30)
        }
    }

    private var kitaplar: some View {
        let dersler: [Ders] = icerik.dersler
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Etiket(yazi: "Kitaplar")
                Spacer()
                Button { adIstegi = AdIstegi(baslik: "Yeni kitap", ilk: "") { icerik.kitapEkle($0) } } label: { EkleDugmesi(ad: "Yeni kitap") }
                    .buttonStyle(.plain).accessibilityIdentifier("yeniKitap")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 250), spacing: 24, alignment: .top)], alignment: .leading, spacing: 28) {
                ForEach(Array(dersler.enumerated()), id: \.element.id) { i, d in
                    NavigationLink(value: d) { KitapKarti(ders: d, sira: i) }
                        .buttonStyle(.plain).accessibilityIdentifier("kitap-" + d.id)
                        .contextMenu {
                            if d.id.hasPrefix("k-") {
                                Button { adIstegi = AdIstegi(baslik: "Kitabın adı", ilk: d.baslik) { icerik.kitapAdi(d.id, $0) } } label: { Label("Adı değiştir", systemImage: "pencil") }
                                Button(role: .destructive) { silIstegi = SilIstegi(ad: d.baslik) { icerik.kitapSil(d.id) } } label: { Label("Sil", systemImage: "trash") }
                            }
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ac(_ o: PartOzet) {
        guard o.hazir, let p = icerik.part(o.id) else { return }
        acikPart = (o, p)
    }
    private func partOzet(_ id: String) -> PartOzet? { icerik.ozetBul(id) }
}

struct KitapKarti: View {
    @EnvironmentObject var icerik: IcerikYonetici
    let ders: Ders; let sira: Int
    var body: some View {
        let partlar = ders.bolumler.flatMap { $0.partlar }
        let biten = partlar.filter { icerik.ilerleme[$0.id]?.durum == "bitti" }.count
        VStack(alignment: .leading, spacing: 12) {
            KitapKapagi(ders: ders, sira: sira)
            IlerlemeCubugu(biten: biten, toplam: partlar.count)
        }
    }
}

// Sol panel: "İnsan Fizyolojisi · Silverthorn / Bölüm 1 Fizyolojiye giriş" + part listesi (kalınan part beyaz satır)
struct BolumPaneli: View {
    @EnvironmentObject var icerik: IcerikYonetici
    let devam: DevamYeri
    let ac: (PartOzet) -> Void
    var body: some View {
        let partlar = devam.bolum.partlar
        let biten = partlar.filter { icerik.ilerleme[$0.id]?.durum == "bitti" }.count
        let ustYazi = [devam.ders.baslik, devam.ders.kaynak].compactMap { $0 }.joined(separator: " · ")
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ustYazi).font(Tema.yazi(13)).foregroundStyle(Tema.soluk)
                    Text("Bölüm \(devam.bolum.no)").font(Tema.baslik(30, .semibold)).foregroundStyle(Tema.murekkep)
                    Text(devam.bolum.baslik).font(Tema.baslik(30, .semibold)).foregroundStyle(Tema.murekkep).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                IlerlemeHalkasi(biten: biten, toplam: partlar.count)
            }
            .padding(.bottom, 14)
            ForEach(partlar) { p in satir(p) }
        }
        .padding(.horizontal, 22).padding(.vertical, 26)
        .camYuzey(34)
    }

    private func satir(_ p: PartOzet) -> some View {
        let durum = icerik.ilerleme[p.id]?.durum
        let bu = p.id == devam.part?.id
        return Button { ac(p) } label: {
            HStack(spacing: 16) {
                DurumDairesi(durum: durum, no: p.no, boy: 32, vurgulu: bu)
                Text(p.baslik).font(Tema.baslik(19, .medium)).multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                satirSonu(p, durum: durum, bu: bu)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .foregroundStyle(bu ? Tema.kartYazi : Tema.murekkep)
            .background(bu ? Tema.kart : Color.clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: bu ? Color.black.opacity(0.28) : Color.clear, radius: 14, x: 0, y: 8)
            .opacity(durum == "bitti" && !bu ? 0.78 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!p.hazir).accessibilityIdentifier(bu ? "devam" : p.id)
    }

    @ViewBuilder private func satirSonu(_ p: PartOzet, durum: String?, bu: Bool) -> some View {
        if bu {
            HStack(spacing: 4) {
                Text("kalınan yer")
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
            }
            .font(Tema.yazi(12.5, .bold)).foregroundStyle(Tema.vurgu)
        } else if !p.hazir {
            Text("yazılıyor").font(Tema.yazi(12.5)).foregroundStyle(Tema.soluk)
        } else if durum == "bitti" {
            Text("tamamlandı").font(Tema.yazi(12.5)).foregroundStyle(Tema.soluk)
        }
    }
}

// Vurgulu satır beyaz kart olur, diğerleri cam
struct CamSartli: ViewModifier {
    let etkin: Bool
    let yaricap: CGFloat
    @ViewBuilder func body(content: Content) -> some View {
        if etkin { content.camYuzey(yaricap) } else { content }
    }
}

struct KitapEkrani: View {
    @EnvironmentObject var icerik: IcerikYonetici
    private let ilk: Ders
    let ac: (PartOzet) -> Void
    @State private var adIstegi: AdIstegi?
    @State private var silIstegi: SilIstegi?
    init(ders: Ders, ac: @escaping (PartOzet) -> Void) { ilk = ders; self.ac = ac }
    private var ders: Ders { icerik.dersler.first { $0.id == ilk.id } ?? ilk }   // kendi kitaplar değişince güncel hâli
    private var kendi: Bool { ilk.id.hasPrefix("k-") }
    var body: some View {
        GeometryReader { g in
            let genis = g.size.width > 900
            let partlar = ders.bolumler.flatMap { $0.partlar }
            let biten = partlar.filter { icerik.ilerleme[$0.id]?.durum == "bitti" }.count
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack { GeriDugmesi(ad: "Kitaplar"); Spacer() }
                    if genis {
                        HStack(alignment: .top, spacing: 44) {
                            sol(biten: biten, toplam: partlar.count).frame(width: 300)
                            bolumler
                        }
                    } else {
                        sol(biten: biten, toplam: partlar.count).frame(maxWidth: 420, alignment: .leading)
                        bolumler
                    }
                }
                .padding(.horizontal, genis ? 54 : 26).padding(.vertical, 30)
            }
        }
        .background(Atmosfer())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .adSorusu($adIstegi).silOnayi($silIstegi)
    }

    private func sol(biten: Int, toplam: Int) -> some View {
        let yuzde: Int = toplam > 0 ? Int((Double(biten) / Double(toplam) * 100).rounded()) : 0
        return VStack(alignment: .leading, spacing: 18) {
            KitapKapagi(ders: ders, sira: 0)
            VStack(alignment: .leading, spacing: 6) {
                Text(ders.baslik).font(Tema.baslik(34, .semibold)).foregroundStyle(Tema.murekkep).fixedSize(horizontal: false, vertical: true)
                if let k = ders.kaynak { Text(k).font(Tema.yazi(14)).foregroundStyle(Tema.soluk) }
            }
            HStack(spacing: 12) {
                istatistik("%\(yuzde)", "kitap ilerlemesi")
                istatistik("\(biten) / \(toplam)", "part bitti")
            }
        }
    }

    private func istatistik(_ sayi: String, _ ad: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(sayi).font(Tema.baslik(22, .semibold)).foregroundStyle(Tema.murekkep).monospacedDigit()
            Text(ad).font(Tema.yazi(12)).foregroundStyle(Tema.soluk)
        }
        .padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading).camYuzey(20)
    }

    private var bolumler: some View {
        let devamNo: Int? = DevamYeri.bul(icerik)?.bolum.no
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Etiket(yazi: "Bölümler")
                Spacer()
                if kendi {
                    Button { adIstegi = AdIstegi(baslik: "Yeni bölüm", ilk: "Bölüm \((ders.bolumler.map { $0.no }.max() ?? 0) + 1)") { icerik.bolumEkle(ders.id, $0) } } label: { EkleDugmesi(ad: "Bölüm ekle") }
                        .buttonStyle(.plain).accessibilityIdentifier("bolumEkle")
                } else {
                    Text("\(ders.bolumler.count) bölüm").font(Tema.yazi(13)).foregroundStyle(Tema.soluk)
                }
            }
            ForEach(ders.bolumler) { b in
                NavigationLink(value: BolumSecimi(ders: ders, bolum: b)) { BolumSatiri(bolum: b, vurgulu: b.no == devamNo) }
                    .buttonStyle(.plain).accessibilityIdentifier("bolum-\(b.no)")
                    .contextMenu {
                        if kendi {
                            Button { adIstegi = AdIstegi(baslik: "Bölümün adı", ilk: b.baslik) { icerik.bolumAdi(ders.id, b.no, $0) } } label: { Label("Adı değiştir", systemImage: "pencil") }
                            Button(role: .destructive) { silIstegi = SilIstegi(ad: b.baslik) { icerik.bolumSil(ders.id, b.no) } } label: { Label("Sil", systemImage: "trash") }
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BolumSatiri: View {
    @EnvironmentObject var icerik: IcerikYonetici
    let bolum: Bolum
    let vurgulu: Bool
    var body: some View {
        let biten = bolum.partlar.filter { icerik.ilerleme[$0.id]?.durum == "bitti" }.count
        HStack(spacing: 20) {
            Text("\(bolum.no)").font(Tema.baslik(34, .light)).foregroundStyle(vurgulu ? Tema.vurgu : Tema.soluk).frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(bolum.baslik).font(Tema.baslik(21, .semibold)).multilineTextAlignment(.leading)
                Text("\(bolum.partlar.count) part").font(Tema.yazi(13)).foregroundStyle(vurgulu ? Tema.kartYazi.opacity(0.65) : Tema.soluk)
            }
            Spacer(minLength: 10)
            VStack(alignment: .trailing, spacing: 8) {
                Text("\(biten) / \(bolum.partlar.count) part").font(Tema.yazi(13, .semibold)).foregroundStyle(vurgulu ? Tema.vurgu : Tema.soluk)
                IlerlemeCubugu(biten: biten, toplam: bolum.partlar.count, etiketGoster: false).frame(width: 120)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 18)
        .foregroundStyle(vurgulu ? Tema.kartYazi : Tema.murekkep)
        .background(vurgulu ? Tema.kart : Color.clear, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: vurgulu ? Color.black.opacity(0.28) : Color.clear, radius: 16, x: 0, y: 10)
        .modifier(CamSartli(etkin: !vurgulu, yaricap: 24))
        .contentShape(Rectangle())
    }
}

struct BolumEkrani: View {
    @EnvironmentObject var icerik: IcerikYonetici
    private let ilkDers: Ders, ilkBolum: Bolum
    let ac: (PartOzet) -> Void
    @State private var adIstegi: AdIstegi?
    @State private var silIstegi: SilIstegi?
    @State private var pdfSec = false
    init(ders: Ders, bolum: Bolum, ac: @escaping (PartOzet) -> Void) { ilkDers = ders; ilkBolum = bolum; self.ac = ac }
    private var ders: Ders { icerik.dersler.first { $0.id == ilkDers.id } ?? ilkDers }
    private var bolum: Bolum { ders.bolumler.first { $0.no == ilkBolum.no } ?? ilkBolum }
    private var kendi: Bool { ilkDers.id.hasPrefix("k-") }

    private func yeniPart(_ desen: String) {
        adIstegi = AdIstegi(baslik: "Yeni part", ilk: "Part \((bolum.partlar.map { $0.no }.max() ?? 0) + 1)") { icerik.partEkle(ders.id, bolum.no, ad: $0, desen: desen) }
    }
    private func pdfAl(_ sonuc: Result<[URL], Error>) {
        guard case .success(let l) = sonuc, let u = l.first else { return }
        let eris = u.startAccessingSecurityScopedResource()
        defer { if eris { u.stopAccessingSecurityScopedResource() } }
        icerik.partEkle(ders.id, bolum.no, ad: u.deletingPathExtension().lastPathComponent, pdf: u)
    }
    private var ekleMenusu: some View {
        Menu {
            Button { yeniPart("cizgili") } label: { Label("Çizgili sayfa", systemImage: "line.3.horizontal") }
            Button { yeniPart("kareli") } label: { Label("Kareli sayfa", systemImage: "squareshape.split.3x3") }
            Button { yeniPart("noktali") } label: { Label("Noktalı sayfa", systemImage: "circle.grid.3x3") }
            Button { yeniPart("duz") } label: { Label("Düz sayfa", systemImage: "doc") }
            Divider()
            Button { pdfSec = true } label: { Label("PDF içe aktar", systemImage: "square.and.arrow.down") }
        } label: { EkleDugmesi(ad: "Part ekle") }
        .accessibilityIdentifier("partEkle")
    }
    var body: some View {
        let biten = bolum.partlar.filter { icerik.ilerleme[$0.id]?.durum == "bitti" }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack { GeriDugmesi(ad: ders.baslik); Spacer(); if kendi { ekleMenusu } }
                HStack(alignment: .bottom, spacing: 26) {
                    Text("\(bolum.no)").font(Tema.baslik(120, .ultraLight)).foregroundStyle(Tema.soluk).minimumScaleFactor(0.5)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(bolum.baslik).font(Tema.baslik(44, .semibold)).foregroundStyle(Tema.murekkep).fixedSize(horizontal: false, vertical: true)
                        Text("Bölüm \(bolum.no) · \(bolum.partlar.count) part").font(Tema.yazi(15)).foregroundStyle(Tema.soluk)
                        IlerlemeCubugu(biten: biten, toplam: bolum.partlar.count, etiketGoster: false).frame(maxWidth: 300).padding(.top, 6)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)], spacing: 16) {
                    ForEach(bolum.partlar) { p in
                        PartKarti(part: p, ac: ac)
                            .contextMenu {
                                if kendi {
                                    Button { adIstegi = AdIstegi(baslik: "Part'ın adı", ilk: p.baslik) { icerik.partAdi(ders.id, bolum.no, p.id, $0) } } label: { Label("Adı değiştir", systemImage: "pencil") }
                                    Button(role: .destructive) { silIstegi = SilIstegi(ad: p.baslik) { icerik.partSil(ders.id, bolum.no, p.id) } } label: { Label("Sil", systemImage: "trash") }
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, 54).padding(.vertical, 30)
        }
        .background(Atmosfer())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .adSorusu($adIstegi).silOnayi($silIstegi)
        .fileImporter(isPresented: $pdfSec, allowedContentTypes: [.pdf], onCompletion: pdfAl)
    }
}

struct PartKarti: View {
    @EnvironmentObject var icerik: IcerikYonetici
    let part: PartOzet
    let ac: (PartOzet) -> Void
    var body: some View {
        let durum = icerik.ilerleme[part.id]?.durum
        let bu = durum == "yarim"
        let sag: String = part.hazir ? (durum == "bitti" ? "tamamlandı" : (bu ? "kalınan yer" : "")) : "yazılıyor"
        return Button { ac(part) } label: {
            HStack(spacing: 18) {
                DurumDairesi(durum: durum, no: part.no, boy: 44, vurgulu: bu)
                VStack(alignment: .leading, spacing: 5) {
                    Text(part.baslik).font(Tema.baslik(21, .semibold)).multilineTextAlignment(.leading)
                    if let n = PartBilgisi.bolumSayisi(part.id) {
                        Text(part.id.hasPrefix("k-") ? "\(n) sayfa" : "\(n) bölüm başlığı").font(Tema.yazi(12.5)).foregroundStyle(bu ? Tema.kartYazi.opacity(0.65) : Tema.soluk)
                    }
                }
                Spacer(minLength: 8)
                Text(sag).font(Tema.yazi(12.5, bu ? .bold : .regular)).foregroundStyle(bu ? Tema.vurgu : Tema.soluk)
            }
            .padding(.horizontal, 22).padding(.vertical, 22).frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .foregroundStyle(bu ? Tema.kartYazi : Tema.murekkep)
            .background(bu ? Tema.kart : Color.clear, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: bu ? Color.black.opacity(0.28) : Color.clear, radius: 16, x: 0, y: 10)
            .modifier(CamSartli(etkin: !bu, yaricap: 26))
            .opacity(part.hazir ? 1 : 0.6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!part.hazir).accessibilityIdentifier(part.id)
    }
}

struct AyarEkrani: View {
    @EnvironmentObject var icerik: IcerikYonetici
    @EnvironmentObject var senkron: Senkron
    @Environment(\.dismiss) private var kapat
    @AppStorage("tema") private var tema = TemaSecimi.otomatik.rawValue
    @State private var anahtar = ""
    @State private var tani: [String] = Tani.kayitlar
    var body: some View {
        NavigationStack {
            Form {
                Section("Görünüm") {
                    Picker("Tema", selection: $tema) {
                        ForEach(TemaSecimi.allCases) { t in Text(t.ad).tag(t.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
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
