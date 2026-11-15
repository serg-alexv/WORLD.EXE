import SwiftUI
import UniformTypeIdentifiers

struct BrainScreen: View {
    @ObservedObject var brain: OnDeviceBrain
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var confirmDownload = false
    @State private var confirmDelete = false
    @State private var prompt = "Мы нашли капсулу. Дай экипажу краткое приветствие."
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("БОРТОВОЙ ИНТЕЛЛЕКТ", systemImage: "cpu")
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                    Text("Настоящий GGUF → llama.cpp. Без облачного сервера и без скрытого переключения на Apple Intelligence.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(brain.backend).font(.headline).foregroundStyle(Palette.teal)
                            .accessibilityIdentifier("ggufBackend")
                        Text(brain.status).font(.callout).accessibilityIdentifier("ggufStatus")
                        if let model = brain.model {
                            Text(model.name).font(.headline)
                            Text(ByteCountFormatter.string(fromByteCount: model.bytes, countStyle: .file))
                            Text(model.source).font(.caption)
                            Text("SHA-256: \(model.sha256)").font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                        } else { Text("Модель ещё не установлена").accessibilityIdentifier("ggufNoModel") }
                        if brain.isBusy {
                            ProgressView(value: brain.progress > 0 ? brain.progress : nil)
                            Button("Остановить") { brain.cancel() }.buttonStyle(.bordered)
                                .accessibilityIdentifier("ggufStop")
                        }
                        if !brain.metrics.isEmpty { Text(brain.metrics).font(.caption).foregroundStyle(.secondary) }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
                    Button { importing = true } label: {
                        Label("Импортировать .gguf из «Файлов»", systemImage: "folder")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.bordered).disabled(brain.isBusy).accessibilityIdentifier("ggufImport")
                    Button { confirmDownload = true } label: {
                        Label("Загрузить проверенную Qwen3 0.6B", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.bordered).disabled(brain.isBusy).accessibilityIdentifier("ggufDownload")
                    Toggle("Запрашивать Metal GPU (только на устройстве)", isOn: $brain.useMetal)
                        .disabled(brain.isLoaded || brain.isBusy).font(.caption)
                    HStack {
                        Button("Загрузить в память") { Task { await brain.load() } }
                            .buttonStyle(.borderedProminent).disabled(brain.model == nil || brain.isLoaded || brain.isBusy)
                            .accessibilityIdentifier("ggufLoad")
                        Button("Выгрузить") { Task { await brain.unload() } }
                            .buttonStyle(.bordered).disabled(!brain.isLoaded && !brain.isBusy)
                            .accessibilityIdentifier("ggufUnload")
                    }.frame(minHeight: 44)
                    Text("Проверка офлайн").font(.headline)
                    Text("После установки и загрузки модели можно отключить интернет. Режим пары требует локальной сети, но не интернет-сервера.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $prompt).frame(minHeight: 96).padding(8)
                        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Запрос локальной модели").accessibilityIdentifier("ggufPrompt")
                    Button("Ответить локально") { Task { await brain.respond(to: prompt) } }
                        .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.borderedProminent)
                        .disabled(!brain.isLoaded || brain.isBusy).accessibilityIdentifier("ggufGenerate")
                    if !brain.response.isEmpty {
                        Text(brain.response).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            .padding().background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("ggufResponse")
                    }
                    Text("Модель — советник, а не источник измерений или правил. Ответ может быть ошибочным. Контекст 2048 токенов; ответы ограничены. При уходе в фон, нехватке памяти или сильном нагреве операция останавливается, модель выгружается.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Удалить файл модели", role: .destructive) { confirmDelete = true }
                        .disabled(brain.model == nil || brain.isBusy).frame(minHeight: 44)
                    Text("Runtime: llama.cpp b12398 (MIT). Рекомендуемая модель: Qwen3-0.6B Q8_0, Apache-2.0. Веса не входят в приложение. Для первого стенда поддерживаются полные GGUF-файлы до 1,3 ГБ и модели до 2 млрд параметров; совместимость произвольного файла не гарантируется.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding()
            }
            .background(Palette.background).tint(Palette.teal)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Закрыть") { dismiss() } } }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { Task { await brain.importModel(url) } }
            case .failure(let error): brain.reportImportError(error)
            }
        }
        .alert("Загрузить около 640 МБ?", isPresented: $confirmDownload) {
            Button("Загрузить по Wi-Fi") { Task { await brain.downloadRecommended() } }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Файл с официального репозитория Qwen. Версия и SHA-256 зафиксированы. Текущая модель будет заменена только после успешной проверки.") }
        .alert("Удалить модель?", isPresented: $confirmDelete) {
            Button("Удалить", role: .destructive) { Task { await brain.deleteModel() } }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Файл будет удалён из приложения. Комната и прогресс игры сохранятся.") }
    }
}
