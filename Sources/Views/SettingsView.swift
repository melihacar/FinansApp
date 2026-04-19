import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var openaiApiKey = ""
    @State private var showOpenaiKey = false
    @State private var savedOpenai = false
    @State private var showClearDataAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // OpenAI API Key Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("OpenAI API Anahtarı", systemImage: "key.fill")
                            .font(.headline)
                        Spacer()
                        Text("Aktif")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }

                    HStack {
                        if showOpenaiKey {
                            TextField("sk-...", text: $openaiApiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("sk-...", text: $openaiApiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button {
                            showOpenaiKey.toggle()
                        } label: {
                            Image(systemName: showOpenaiKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)

                        Button {
                            saveOpenaiApiKey()
                        } label: {
                            if savedOpenai {
                                Label("Kaydedildi", systemImage: "checkmark")
                            } else {
                                Text("Kaydet")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                        Label("OpenAI API anahtarı nasıl alınır?", systemImage: "arrow.up.right")
                            .font(.caption)
                    }
                }
                .padding()
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // About Section
                VStack(alignment: .leading, spacing: 12) {
                    Label("Hakkında", systemImage: "info.circle")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("FinansApp")
                                .fontWeight(.semibold)
                            Spacer()
                            Text("v1.0.0")
                                .foregroundStyle(.secondary)
                        }

                        Text("Kredi kartı ekstre analiz uygulaması")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Divider()

                        Text("Bu uygulama, kredi kartı ekstrelerinizi AI ile analiz ederek harcama alışkanlıklarınızı anlamanıza ve tasarruf fırsatlarını keşfetmenize yardımcı olur.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Bu program Fikret Tozak tarafından Claude Code kullanılarak yapılmıştır.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 4) {
                                Image(systemName: "envelope.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Link("fikret.tozak@wpokulu.co", destination: URL(string: "mailto:fikret.tozak@wpokulu.co")!)
                                    .font(.caption)
                            }
                        }
                    }
                }
                .padding()
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Data Section
                VStack(alignment: .leading, spacing: 12) {
                    Label("Veri", systemImage: "cylinder.split.1x2")
                        .font(.headline)

                    HStack {
                        VStack(alignment: .leading) {
                            Text("Veritabanı Konumu")
                                .font(.subheadline)
                            Text(databasePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Finder'da Göster") {
                            showInFinder()
                        }
                        .buttonStyle(.bordered)
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading) {
                            Text("Tüm Verileri Sil")
                                .font(.subheadline)
                            Text("Kartlar, ekstreler ve işlemler silinir. API anahtarı korunur.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Verileri Sil") {
                            showClearDataAlert = true
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .padding()
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Ayarlar")
        .onAppear {
            openaiApiKey = appState.openaiApiKey
        }
        .alert("Tüm Verileri Sil", isPresented: $showClearDataAlert) {
            Button("İptal", role: .cancel) { }
            Button("Sil", role: .destructive) {
                appState.clearAllData()
            }
        } message: {
            Text("Tüm kartlar, ekstreler ve işlemler kalıcı olarak silinecek. Bu işlem geri alınamaz.")
        }
    }

    private var databasePath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("FinansApp/finans.db").path
    }

    private func saveOpenaiApiKey() {
        appState.openaiApiKey = openaiApiKey
        savedOpenai = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            savedOpenai = false
        }
    }

    private func showInFinder() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("FinansApp")
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
