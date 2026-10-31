import SwiftUI

// Okuyucunun yan paneli (yatayda açık gelir): part içindekiler + bu part'taki yapışkan notlar.
final class PanelModeli: ObservableObject {
    struct Satir: Identifiable { let id: String; let baslik: String; let tur: String; let no: Int? }
    @Published var baslik = ""
    @Published var ust = ""
    @Published var satirlar: [Satir] = []
    @Published var notlar: [YapiskanNot] = []
    @Published var secili: String?
    var git: ((String) -> Void)?
    var notAc: ((String) -> Void)?
}

struct OkuyucuPaneli: View {
    @ObservedObject var model: PanelModeli
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.ust).font(Tema.yazi(12.5, .semibold)).foregroundStyle(Tema.soluk)
                    Text(model.baslik).font(Tema.baslik(26, .semibold)).foregroundStyle(Tema.murekkep)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Etiket(yazi: "İçindekiler").padding(.bottom, 8)
                    ForEach(model.satirlar) { s in
                        Button { model.git?(s.id) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(s.no.map { String(format: "%02d", $0) } ?? (s.tur == "e" ? "+" : "✓"))
                                    .font(Tema.yazi(12, .bold)).foregroundStyle(model.secili == s.id ? Tema.vurgu : Tema.soluk).frame(width: 26, alignment: .leading)
                                Text(s.baslik).font(Tema.baslik(16, model.secili == s.id ? .semibold : .regular))
                                    .foregroundStyle(model.secili == s.id ? Tema.murekkep : Tema.murekkep.opacity(0.75)).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 9).padding(.horizontal, 10)
                            .background(model.secili == s.id ? Tema.camVurgu : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Etiket(yazi: "Bu part'taki notlar")
                    if model.notlar.isEmpty {
                        Text("Henüz yapışkan not yok. Üst çubuktaki not düğmesiyle sayfaya not iliştirilebilir.")
                            .font(Tema.yazi(13)).foregroundStyle(Tema.soluk)
                    }
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
            .padding(22)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .trailing) { Rectangle().fill(Tema.camKenar).frame(width: 1) }
    }
}
