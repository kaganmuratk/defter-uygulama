import SwiftUI

// Yan yana görünüm (Kağan 2026-11-17): iki sayfa/kitap aynı anda; yan yana ya da üst üste, ortadaki tutamaçla boyut ayarlanır.
// Basit tutuldu: her bölme sıradan bir okuyucudur. İkinci bölme kendi "Kapat" düğmesiyle kapanır; ana bölmenin "Geri"si ikisini de kapatır.
struct BolunmusEkran: View {
    let ana: AnyView
    let ikinci: AnyView?
    @AppStorage("bolmeYanYana") private var yanYana = true      // true: yan yana, false: üst üste
    @AppStorage("bolmeOran") private var oran: Double = 0.5     // ana bölmenin payı

    var body: some View {
        GeometryReader { g in
            let toplam = yanYana ? g.size.width : g.size.height
            let enAz: CGFloat = 260
            let anaBoy = ikinci == nil ? toplam : min(max(toplam * CGFloat(oran), enAz), max(toplam - enAz, enAz))
            let duzen = yanYana ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            duzen {
                ana.frame(width: yanYana ? anaBoy : nil, height: yanYana ? nil : anaBoy)
                if let ikinci {
                    ayirici(toplam: toplam)
                    ikinci
                }
            }
            .coordinateSpace(name: "bolme")
        }
    }

    private func ayirici(toplam: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(Tema.camKenar.opacity(0.9))
            Capsule().fill(Tema.murekkep.opacity(0.35))
                .frame(width: yanYana ? 5 : 54, height: yanYana ? 54 : 5)
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { yanYana.toggle() }
            } label: {
                Image(systemName: yanYana ? "rectangle.split.1x2" : "rectangle.split.2x1")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Tema.murekkep)
                    .frame(width: 34, height: 34).camYuzey(17)
            }
            .buttonStyle(.plain)
            .offset(x: yanYana ? 0 : 60, y: yanYana ? 60 : 0)
            .accessibilityIdentifier("bolmeYonu").accessibilityLabel(yanYana ? "Üst üste yap" : "Yan yana yap")
        }
        .frame(width: yanYana ? 14 : nil, height: yanYana ? nil : 14)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .named("bolme")).onChanged { v in
                let konum = yanYana ? v.location.x : v.location.y
                oran = Double(min(max(konum / max(toplam, 1), 0.2), 0.8))
            }
        )
        .accessibilityIdentifier("bolmeAyirici")
        .zIndex(1)
    }
}

// Yan yana açılacak sayfayı seçtirir: bütün kitaplar (hazır kitap + kendi defter/PDF/klasörler), bölüm bölüm
struct YanYanaSecici: View {
    @ObservedObject var icerik: IcerikYonetici
    let haric: [String]
    let sec: (PartOzet) -> Void
    @Environment(\.dismiss) private var kapat

    var body: some View {
        NavigationStack {
            List {
                ForEach(icerik.dersler) { d in
                    Section(d.baslik) {
                        ForEach(d.bolumler) { b in
                            ForEach(b.partlar.filter { $0.hazir && !haric.contains($0.id) }) { o in
                                Button { sec(o) } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(o.id.hasPrefix("k-") ? o.baslik : "Part \(o.no) · \(o.baslik)")
                                            .font(Tema.yazi(16, .semibold)).foregroundStyle(Tema.murekkep)
                                        if !o.id.hasPrefix("k-") || b.no != 0 {
                                            Text(b.baslik).font(Tema.yazi(13)).foregroundStyle(Tema.soluk)
                                        }
                                    }
                                }
                                .accessibilityIdentifier("yanyana-" + o.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Yan yana aç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } } }
        }
    }
}
