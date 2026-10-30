import SwiftUI

// Kitaplık: kitaplar → bölümler (kutucuk) → partlar (liste). Part açılınca okuyucu tam ekran gelir.
struct KutuphaneEkrani: View {
    @EnvironmentObject var icerik: IcerikYonetici
    @State private var acikPart: (PartOzet, Part)?
    @State private var ayarAcik = false
    @State private var yol = NavigationPath()

    var body: some View {
        NavigationStack(path: $yol) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let devam = devamEdilecek() {
                        Button { ac(devam.0) } label: { DevamKarti(part: devam.0, ders: devam.1, yarim: devam.2) }
                            .buttonStyle(.plain).accessibilityIdentifier("devam")
                    }
                    Text("Kitaplar").font(.title3.weight(.bold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 18)], spacing: 18) {
                        ForEach(icerik.plan?.dersler ?? []) { d in
                            NavigationLink(value: d) { KitapKarti(ders: d, ilerleme: icerik.ilerleme) }.buttonStyle(.plain).accessibilityIdentifier("kitap-" + d.id)
                        }
                    }
                    if icerik.plan == nil {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(icerik.hata ?? "İçerik indiriliyor…").foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.top, 60)
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 20)
                .frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }
            .background(Tema.zemin)
            .navigationTitle("Defter")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { ayarAcik = true } label: { Image(systemName: "gearshape") }.accessibilityIdentifier("ayarlar")
                }
            }
            .navigationDestination(for: Ders.self) { d in KitapEkrani(ders: d, ac: ac) }
            .navigationDestination(for: BolumSecimi.self) { s in BolumEkrani(ders: s.ders, bolum: s.bolum, ac: ac) }
            .refreshable { await icerik.indir(); await Senkron.ortak.hepsi() }
        }
        .sheet(isPresented: $ayarAcik) { AyarEkrani() }
        .fullScreenCover(isPresented: Binding(get: { acikPart != nil }, set: { if !$0 { acikPart = nil } })) {
            if let acik = acikPart {
                OkuyucuEkrani(partOzet: acik.0, part: acik.1) { acikPart = nil }.ignoresSafeArea(.container, edges: .bottom)
            }
        }
    }

    private func ac(_ o: PartOzet) {
        guard o.hazir, let p = icerik.part(o.id) else { return }
        acikPart = (o, p)
    }

    // Yarım kalan en son part; yoksa sıradaki başlanmamış part
    private func devamEdilecek() -> (PartOzet, Ders, Bool)? {
        guard let plan = icerik.plan else { return nil }
        let tum = plan.dersler.flatMap { d in d.bolumler.flatMap { b in b.partlar.map { ($0, d) } } }
        if let y = tum.filter({ icerik.ilerleme[$0.0.id]?.durum == "yarim" && $0.0.hazir })
            .max(by: { (icerik.ilerleme[$0.0.id]?.guncelleme ?? 0) < (icerik.ilerleme[$1.0.id]?.guncelleme ?? 0) }) { return (y.0, y.1, true) }
        if let s = tum.first(where: { $0.0.hazir && icerik.ilerleme[$0.0.id]?.durum != "bitti" }) { return (s.0, s.1, false) }
        return nil
    }
}

struct BolumSecimi: Hashable { let ders: Ders; let bolum: Bolum }

struct DevamKarti: View {
    let part: PartOzet; let ders: Ders; let yarim: Bool
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(yarim ? "Kaldığın yerden devam" : "Başla").font(.title3.weight(.bold))
                Text("\(ders.baslik) · Part \(part.no): \(part.baslik)").font(.callout).opacity(0.9)
            }
            Spacer()
            Image(systemName: "arrow.right").font(.title2.weight(.semibold))
        }
        .foregroundStyle(.white).padding(22)
        .background(Tema.vurgu, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct IlerlemeCubugu: View {
    let biten: Int; let toplam: Int
    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(Tema.vurgu).frame(width: toplam > 0 ? g.size.width * CGFloat(biten) / CGFloat(toplam) : 0)
                }
            }.frame(height: 6)
            Text("\(biten)/\(toplam)").font(.footnote.weight(.bold)).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

struct KitapKarti: View {
    let ders: Ders; let ilerleme: [String: Ilerleme]
    var body: some View {
        let partlar = ders.bolumler.flatMap { $0.partlar }
        let biten = partlar.filter { ilerleme[$0.id]?.durum == "bitti" }.count
        HStack(spacing: 0) {
            Rectangle().fill(Tema.vurgu).frame(width: 10)
            VStack(alignment: .leading, spacing: 6) {
                Text(ders.baslik).font(.title2.weight(.heavy))
                if let k = ders.kaynak { Text(k).font(.callout.weight(.semibold)).foregroundStyle(.secondary) }
                Text("\(ders.bolumler.count) bölüm · \(partlar.count) part").font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 18)
                IlerlemeCubugu(biten: biten, toplam: partlar.count)
            }.padding(20)
        }
        .frame(minHeight: 190)
        .background(Tema.kart, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 14, y: 6)
    }
}

struct KitapEkrani: View {
    @EnvironmentObject var icerik: IcerikYonetici
    let ders: Ders
    let ac: (PartOzet) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let k = ders.kaynak { Text("Kaynak: " + k).foregroundStyle(.secondary) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 18)], spacing: 18) {
                    ForEach(ders.bolumler) { b in
                        NavigationLink(value: BolumSecimi(ders: ders, bolum: b)) {
                            let biten = b.partlar.filter { icerik.ilerleme[$0.id]?.durum == "bitti" }.count
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(b.no)").font(.system(size: 40, weight: .heavy)).foregroundStyle(Tema.vurgu)
                                Text(b.baslik).font(.title3.weight(.bold)).multilineTextAlignment(.leading)
                                Text("\(b.partlar.count) part").font(.callout).foregroundStyle(.secondary)
                                Spacer(minLength: 10)
                                IlerlemeCubugu(biten: biten, toplam: b.partlar.count)
                            }
                            .padding(20).frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
                            .background(Tema.kart, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .shadow(color: .black.opacity(0.07), radius: 14, y: 6)
                        }.buttonStyle(.plain).accessibilityIdentifier("bolum-\(b.no)")
                    }
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 20).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .background(Tema.zemin)
        .navigationTitle(ders.baslik)
    }
}

struct BolumEkrani: View {
    @EnvironmentObject var icerik: IcerikYonetici
    let ders: Ders; let bolum: Bolum
    let ac: (PartOzet) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                IlerlemeCubugu(biten: bolum.partlar.filter { icerik.ilerleme[$0.id]?.durum == "bitti" }.count, toplam: bolum.partlar.count)
                    .frame(maxWidth: 380).padding(.bottom, 10)
                ForEach(bolum.partlar) { p in
                    let durum = icerik.ilerleme[p.id]?.durum
                    Button { ac(p) } label: {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle().strokeBorder(durum == nil ? Color.primary.opacity(0.6) : Tema.vurgu, lineWidth: 2)
                                    .background(Circle().fill(durum == "bitti" ? Tema.vurgu : .clear))
                                if durum == "bitti" { Image(systemName: "checkmark").font(.caption.weight(.heavy)).foregroundStyle(.white) }
                                else if durum == "yarim" { Circle().trim(from: 0, to: 0.5).fill(Tema.vurgu).rotationEffect(.degrees(90)).padding(2) }
                            }.frame(width: 26, height: 26)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Part \(p.no): \(p.baslik)").font(.title3.weight(.bold)).foregroundStyle(p.hazir ? .primary : .secondary)
                                Text([p.hazir ? (durum == "bitti" ? "Bitti" : durum == "yarim" ? "Yarım" : "Başlamadı") : "Yazılıyor", p.kitap].compactMap { $0 }.joined(separator: " · "))
                                    .font(.callout).foregroundStyle(durum == nil ? Color.secondary : Tema.vurgu)
                            }
                            Spacer()
                            if p.hazir { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                        }
                        .padding(18)
                        .background(p.hazir ? Tema.kart : Color.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.secondary.opacity(p.hazir ? 0.12 : 0.3), style: StrokeStyle(lineWidth: 1, dash: p.hazir ? [] : [5, 4])))
                    }
                    .buttonStyle(.plain).disabled(!p.hazir).accessibilityIdentifier(p.id)
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 20).frame(maxWidth: 820).frame(maxWidth: .infinity)
        }
        .background(Tema.zemin)
        .navigationTitle("Bölüm \(bolum.no): \(bolum.baslik)")
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
