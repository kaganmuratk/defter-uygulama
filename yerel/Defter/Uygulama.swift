import SwiftUI
import UIKit

@main
struct DefterUygulamasi: App {
    @StateObject private var icerik = IcerikYonetici.ortak
    @StateObject private var senkron = Senkron.ortak
    @Environment(\.scenePhase) private var evre
    @AppStorage("tema") private var tema = TemaSecimi.otomatik.rawValue

    var body: some Scene {
        WindowGroup {
            KokEkran()
                .environmentObject(icerik)
                .environmentObject(senkron)
                .tint(Tema.vurgu)
                .preferredColorScheme(TemaSecimi(rawValue: tema)?.sema)
        }
        .onChange(of: evre) { _, yeni in
            guard yeni == .active else { return }
            Task { await icerik.indir(); await senkron.hepsi() }
        }
    }
}

struct KokEkran: View {
    @EnvironmentObject var icerik: IcerikYonetici
    var body: some View {
        Group {
            if icerik.anahtarGerekli && !Ayar.ornek { AnahtarEkrani() }
            else { KutuphaneEkrani() }
        }
        .task { await icerik.indir(); await Senkron.ortak.hepsi() }
    }
}

struct AnahtarEkrani: View {
    @EnvironmentObject var icerik: IcerikYonetici
    @State private var anahtar = ""
    @State private var bekliyor = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Defter").font(Tema.baslik(52, .semibold)).foregroundStyle(Tema.murekkep)
            Text("İçeriği indirmek için anahtarı girin. Bir kez girmek yeterli; sonra internetsiz de çalışır.")
                .font(Tema.yazi(16)).foregroundStyle(Tema.soluk)
            SecureField("Anahtar", text: $anahtar)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(16).foregroundStyle(Tema.murekkep).camYuzey(18)
            if let h = icerik.hata { Text(h).foregroundStyle(.red).font(.callout.weight(.semibold)) }
            Button {
                bekliyor = true
                Ayar.anahtar = anahtar
                Task { await icerik.indir(); bekliyor = false }
            } label: {
                HStack { Text(bekliyor ? "İndiriliyor…" : "Devam").font(Tema.yazi(17, .semibold)); Spacer(); Image(systemName: "arrow.right") }
                    .padding(18).foregroundStyle(Tema.dolguUstu).background(Tema.dolgu, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .disabled(anahtar.isEmpty || bekliyor)
        }
        .padding(32).frame(maxWidth: 520).frame(maxWidth: .infinity, maxHeight: .infinity).background(Atmosfer())
    }
}
