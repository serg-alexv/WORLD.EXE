import SwiftUI
import UniformTypeIdentifiers
import FeedDomain
import FeedAdapters
import FeedStore

private struct PendingImport: Identifiable {
    let id = UUID()
    let data: Data
    let fileExtension: String
}
struct SourceDetailView: View {
    @ObservedObject var session: FeedSession
    let sourceID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var selecting = false
    @State private var reading = false
    @State private var pending: PendingImport?
    @State private var confirmDelete = false
    @State private var confirmFetch = false
    @State private var endpoint = ""
    private var source: FeedSource? { session.value.sources.first { $0.id == sourceID }?.source }
    var body: some View {
        Form {
            if let source {
                Section("Источник") {
                    Text(verbatim: source.label).font(.headline)
                    Text(source.provider.title)
                    Text(source.coverage.title).foregroundStyle(.secondary)
                    Text(SourceCapability.forProvider(source.provider).explanation).font(.caption)
                    Text("Записей в клиенте: \(session.value.items.filter { $0.key.sourceID == source.id }.count)")
                        .accessibilityIdentifier("feed.sourceCount")
                }
                if source.acquisition == .userMappedFile {
                    Section("Импорт только после предпросмотра") {
                        Button("Выбрать CSV или JSON") { selecting = true }.accessibilityIdentifier("feed.import")
                            .disabled(session.busy || session.loadFailed || reading)
                        Text("Оригинальный файл не копируется в репозиторий или журнал. В клиенте сохраняются только выбранные поля. Архив ZIP сначала нужно распаковать самостоятельно.").font(.caption)
                    }
                } else if source.acquisition == .userEndpoint {
                    Section("Ваш endpoint · Exchange v1") {
                        TextField("https://your-domain.example/feed.json", text: $endpoint)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        Text("Адрес не сохраняется. Клиент отправит один GET только после подтверждения. Пароли, токены и перенаправления не поддерживаются.").font(.caption)
                        Button("Получить записи") { confirmFetch = true }
                            .disabled(session.busy || session.loadFailed || (try? EndpointPolicy.validate(endpoint)) == nil)
                        Text("Контракт: format = personal-feed-exchange/v1; records = массив {id, text, title?, author?, timestamp?, direction?}. Это наш формат, не API Hornet.").font(.caption.monospaced())
                    }
                }
                if reading || session.busy { ProgressView() }
                Section { Text(session.message).font(.caption).accessibilityIdentifier("feed.importResult") }
                Section {
                    Button("Удалить этот источник", role: .destructive) { confirmDelete = true }
                        .disabled(session.busy).accessibilityIdentifier("feed.deleteSource")
                }
            } else { Text("Источник удалён.") }
        }
        .navigationTitle("Подключение").navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $selecting, allowedContentTypes: [.json, .commaSeparatedText], allowsMultipleSelection: false) { result in
            guard let source, session.mode == .personal else { return }
            let token = session.epoch
            switch result {
            case .failure: session.show(FeedError.malformed)
            case .success(let urls):
                guard let url = urls.first else { return }
                reading = true
                Task {
                    do {
                        let result = try await Task.detached(priority: .userInitiated) { try readSelectedFile(url) }.value
                        guard token == session.epoch, session.mode == .personal,
                              session.value.sources.contains(where: { $0.id == source.id }) else { return }
                        pending = result; reading = false
                    } catch {
                        guard token == session.epoch else { return }
                        reading = false; session.show(error)
                    }
                }
            }
        }
        .sheet(item: $pending) { selected in
            if let source { ImportWizard(session: session, source: source, pending: selected) }
        }
        .confirmationDialog("Удалить источник, записи и связанные аннотации?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить источник", role: .destructive) { Task { await session.deleteSource(sourceID); if !session.value.sources.contains(where: { $0.id == sourceID }) { dismiss() } } }
        }
        .confirmationDialog("Отправить HTTPS GET выбранному вами серверу?", isPresented: $confirmFetch, titleVisibility: .visible) {
            Button("Получить один раз") { if let source { session.fetch(source: source, endpoint: endpoint) } }
        } message: { Text("Только загрузка. Ваши имеющиеся записи не отправляются. Убедитесь, что вы доверяете адресу сервера.") }
    }
}
private func readSelectedFile(_ url: URL) throws -> PendingImport {
    guard url.isFileURL, ["csv", "json"].contains(url.pathExtension.lowercased()) else { throw FeedError.unsupportedFormat }
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else { throw FeedError.unsupportedFormat }
    if let size = values.fileSize, size > ImportTable.maxBytes { throw FeedError.tooLarge }
    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
    let data = try handle.read(upToCount: ImportTable.maxBytes + 1) ?? Data()
    guard data.count <= ImportTable.maxBytes else { throw FeedError.tooLarge }
    return PendingImport(data: data, fileExtension: url.pathExtension)
}
private struct ImportWizard: View {
    @ObservedObject var session: FeedSession
    let source: FeedSource
    let pending: PendingImport
    @Environment(\.dismiss) private var dismiss
    @State private var table: ImportTable?
    @State private var arrayKey = ""
    @State private var idColumn = ""
    @State private var bodyColumn = ""
    @State private var titleColumn = ""
    @State private var authorColumn = ""
    @State private var dateColumn = ""
    @State private var dateFormat = DateFormat.iso8601
    @State private var direction = Direction.unspecified
    @State private var preview: [IncomingItem]?
    @State private var status = ""
    @State private var parsing = false
    @State private var parseToken = UUID()
    private var mappingIdentity: String { [idColumn, bodyColumn, titleColumn, authorColumn, dateColumn, dateFormat.rawValue, direction.rawValue, arrayKey].joined(separator: "\u{1F}") }
    var body: some View {
        NavigationStack {
            Form {
                Section("1 · Структура файла") {
                    Text("Источник выбран вами: \(source.provider.title). Это не проверка происхождения сервисом.").font(.caption)
                    if pending.fileExtension.lowercased() == "json" {
                        TextField("Ключ массива, если JSON не является массивом", text: $arrayKey)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("Например, messages — только если такое поле действительно есть в вашем файле. Вложенные объекты не интерпретируются автоматически.").font(.caption)
                    }
                    Button("Прочитать структуру") { inspect() }.disabled(parsing)
                    if let table { Text("\(table.rows.count) строк · \(table.columns.count) полей · \(table.format)").font(.caption) }
                }
                if let table {
                    Section("2 · Явно выберите поля") {
                        column("Уникальный ID записи", selection: $idColumn, columns: table.columns)
                        column("Текст", selection: $bodyColumn, columns: table.columns)
                        column("Заголовок · необязательно", selection: $titleColumn, columns: table.columns)
                        column("Автор · необязательно", selection: $authorColumn, columns: table.columns)
                        column("Дата · необязательно", selection: $dateColumn, columns: table.columns)
                        if !dateColumn.isEmpty {
                            Picker("Формат даты", selection: $dateFormat) { Text("ISO 8601 с часовым поясом").tag(DateFormat.iso8601); Text("Unix-секунды").tag(DateFormat.unixSeconds) }
                        }
                        Picker("Направление всего набора", selection: $direction) {
                            Text("Неизвестно").tag(Direction.unspecified)
                            Text("Исходящие").tag(Direction.outgoing)
                            Text("Входящие").tag(Direction.incoming)
                        }
                        Button("Показать предпросмотр") { prepare() }.disabled(idColumn.isEmpty || bodyColumn.isEmpty || parsing)
                    }
                }
                if let preview {
                    Section("3 · Подтвердите \(preview.count) записей") {
                        ForEach(Array(preview.prefix(3).enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: item.key.externalID).font(.caption.monospaced())
                                Text(verbatim: item.body).lineLimit(5)
                                Text(item.occurredAt.map { $0.formatted() } ?? "Дата отсутствует — останется неизвестной").font(.caption2)
                            }
                        }
                        Text("Повторные ID обновляются в рамках этого источника. Изменённые записи снимают устаревшие заметки/AI-аннотации. Отсутствующие записи не считаются удалёнными в сервисе.").font(.caption)
                        Button("Подтвердить импорт") {
                            Task { await session.importItems(preview, source: source); dismiss() }
                        }.buttonStyle(.borderedProminent).disabled(session.busy)
                    }
                }
                if !status.isEmpty { Section { Text(status).font(.caption) } }
                if parsing { ProgressView() }
            }.navigationTitle("Предпросмотр импорта").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Отмена") { parseToken = UUID(); dismiss() } }
                .onAppear { if source.coverage == .outgoingOnly { direction = .outgoing }; inspect() }
                .onChange(of: mappingIdentity) { _, _ in preview = nil }
                .onChange(of: arrayKey) { _, _ in parseToken = UUID(); parsing = false; table = nil; preview = nil; status = "Структура изменена. Нажмите «Прочитать структуру»." }
                .onDisappear { parseToken = UUID() }
        }
    }
    private func column(_ label: String, selection: Binding<String>, columns: [String]) -> some View {
        Picker(label, selection: selection) {
            Text("Не выбрано").tag("")
            ForEach(columns, id: \.self) { Text(verbatim: $0).tag($0) }
        }
    }
    private func inspect() {
        parsing = true; preview = nil; table = nil; status = ""
        let token = UUID(); parseToken = token
        let data = pending.data, ext = pending.fileExtension, key = arrayKey.isEmpty ? nil : arrayKey
        Task {
            do {
                let parsed = try await Task.detached(priority: .userInitiated) { try ImportTable(data: data, fileExtension: ext, arrayKey: key) }.value
                guard token == parseToken else { return }
                table = parsed; idColumn = ""; bodyColumn = ""; titleColumn = ""; authorColumn = ""; dateColumn = ""; parsing = false
            } catch {
                guard token == parseToken else { return }
                parsing = false; status = (error as? FeedError)?.errorDescription ?? "Файл не распознан."
            }
        }
    }
    private func prepare() {
        guard let table else { return }
        do {
            preview = try table.map(using: .init(id: idColumn, body: bodyColumn,
                title: titleColumn.isEmpty ? nil : titleColumn, author: authorColumn.isEmpty ? nil : authorColumn,
                timestamp: dateColumn.isEmpty ? nil : dateColumn, dateFormat: dateFormat, direction: direction), source: source)
            status = "Предпросмотр готов. До подтверждения ничего не сохранено."
        } catch { preview = nil; status = (error as? FeedError)?.errorDescription ?? "Не удалось сопоставить поля." }
    }
}
