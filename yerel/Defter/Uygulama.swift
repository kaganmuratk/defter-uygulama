import SwiftUI
import UIKit

@main
struct DefterUygulamasi: App {
    @StateObject private var icerik = IcerikYonetici.ortak
    @StateObject private var senkron = Senkron.ortak
    @Environment(\.scenePhase) private var evre

    var body: some Scene {
        WindowGroup {
            KokEkran()
                .environmentObject(icerik)
                .environmentObject(senkron)
                .tint(Tema.vurgu)
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
            Text("Defter").font(.system(size: 52, weight: .heavy)).tracking(-1.5)
            Text("İçeriği indirmek için anahtarı girin. Bir kez girmek yeterli; sonra internetsiz de çalışır.")
                .foregroundStyle(.secondary)
            SecureField("Anahtar", text: $anahtar)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(14).background(Tema.kart, in: RoundedRectangle(cornerRadius: 14))
            if let h = icerik.hata { Text(h).foregroundStyle(.red).font(.callout.weight(.semibold)) }
            Button {
                bekliyor = true
                Ayar.anahtar = anahtar
                Task { await icerik.indir(); bekliyor = false }
            } label: {
                HStack { Text(bekliyor ? "İndiriliyor…" : "Devam").font(.headline); Spacer(); Image(systemName: "arrow.right") }
                    .padding(18).foregroundStyle(.white).background(Tema.vurgu, in: RoundedRectangle(cornerRadius: 16))
            }
            .disabled(anahtar.isEmpty || bekliyor)
        }
        .padding(32).frame(maxWidth: 520).frame(maxWidth: .infinity, maxHeight: .infinity).background(Tema.zemin)
    }
}
