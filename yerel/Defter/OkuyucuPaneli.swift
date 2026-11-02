import SwiftUI

// Okuyucunun yan paneli (yatayda açık gelir): part içindekiler + bu part'taki yapışkan notlar.
final class PanelModeli: ObservableObject {
    struct Satir: Identifiable { let id: String; let baslik: String; let tur: String; let no: Int?; var duzenle = false }
    @Published var baslik = ""
    @Published var ust = ""
    @Published var satirlar: [Satir] = []
    @Published var notlar: [YapiskanNot] = []
    @Published var secili: String?
    @Published var siralanabilir = false     // kendi not/PDF'lerde sayfalar sürüklenerek sıralanır
    var git: ((String) -> Void)?
    var notAc: ((String) -> Void)?
    var adDegistir: ((String) -> Void)?
    var sil: ((String) -> Void)?
    var tasi: ((String, String) -> Void)?    // (sürüklenen sayfa, bırakıldığı sayfa)
}

struct OkuyucuPaneli: View {
    @ObservedObject var model: PanelModeli
    @State private var hedef: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    if !model.ust.isEmpty { Text(model.ust).font(Tema.yazi(12.5, .semibold)).foregroundStyle(Tema.soluk) }
                    Text(model.baslik).font(Tema.baslik(26, .semibold)).foregroundStyle(Tema.murekkep)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Etiket(yazi: "İçindekiler").padding(.bottom, 8)
                    ForEach(model.satirlar) { s in
                        satir(s)
                    }
                }
                if !model.notlar.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Etiket(yazi: "Notlar")
                        ForEach(model.notlar) { n in
                            Button { model.notAc?(n.id) } label: {
                                Text(n.yazi.isEmpty ? "El yazısı not" : n.yazi).font(Tema.baslik(14, .medium))
                                    .foregroundStyle(Color.black.opacity(0.8)).lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    .background(Color(NotRenk.renk(n.renk)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(22)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .trailing) { Rectangle().fill(Tema.camKenar).frame(width: 1) }
    }
    @ViewBuilder
    private func satir(_ s: PanelModeli.Satir) -> some View {
        let secili = model.secili == s.id
        let govde = HStack(spacing: 4) {
            Button { model.git?(s.id) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(s.no.map { String(format: "%02d", $0) } ?? (s.tur == "e" ? "+" : "✓"))
                        .font(Tema.yazi(12, .bold)).foregroundStyle(secili ? Tema.vurgu : Tema.soluk).frame(width: 26, alignment: .leading)
                    Text(s.baslik).font(Tema.baslik(16, secili ? .semibold : .regular))
                        .foregroundStyle(secili ? Tema.murekkep : Tema.murekkep.opacity(0.75)).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            if s.duzenle {
                Menu {
                    Button { model.adDegistir?(s.id) } label: { Label("Adı değiştir", systemImage: "pencil") }
                    Button(role: .destructive) { model.sil?(s.id) } label: { Label("Sayfayı sil", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.soluk)
                        .frame(width: 34, height: 34).contentShape(Rectangle())
                }
                .accessibilityIdentifier("sayfa-menu-" + s.id)
            }
        }
        .padding(.vertical, 5).padding(.leading, 10).padding(.trailing, s.duzenle ? 2 : 10)
        .background(secili ? Tema.camVurgu : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .top) { if hedef == s.id { Capsule().fill(Tema.vurgu).frame(height: 3).padding(.horizontal, 10) } }
        if model.siralanabilir {
            govde
                .draggable(s.id)
                .dropDestination(for: String.self, action: { liste, _ in
                    hedef = nil
                    guard let k = liste.first, k != s.id else { return false }
                    model.tasi?(k, s.id); return true
                }, isTargeted: { icinde in
                    if icinde { hedef = s.id } else if hedef == s.id { hedef = nil }
                })
        } else {
            govde
        }
    }
}
