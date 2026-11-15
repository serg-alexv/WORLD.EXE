import SwiftUI
import FeedDomain
import FeedAdapters
import FeedStore

struct FeedRootView: View {
    @StateObject private var session = FeedSession()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        ZStack {
            Group {
                if session.isOpen { FeedWorkspace(session: session).id(session.epoch) }
                else { welcome }
            }
            if scenePhase != .active {
                Color(.systemBackground).ignoresSafeArea()
                Label("Личная лента скрыта", systemImage: "lock.shield.fill").font(.headline)
            }
        }
        .tint(.indigo)
        .onChange(of: scenePhase) { _, phase in if phase == .background { session.lock() } }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Image(systemName: "rectangle.stack.badge.person.crop").font(.system(size: 58)).foregroundStyle(.indigo)
            Text("Личная лента").font(.largeTitle.bold())
            Text("Ваши записи. Их источники. Ваше устройство.").font(.title3)
            Text("Отдельный клиент: без игры, рекламной аналитики и автоматической отправки переписок в AI.")
                .foregroundStyle(.secondary)
            Button { session.startDemo() } label: {
                Label("Открыть демонстрацию", systemImage: "play.rectangle").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("feed.demo")
            Button { Task { await session.unlock() } } label: {
                Label("Открыть личное пространство", systemImage: "lock.open").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).controlSize(.large).accessibilityIdentifier("feed.unlock")
            Text("Демо содержит только вымышленные карточки. Для личных данных потребуется подтверждение владельца iPhone.")
                .font(.caption).foregroundStyle(.secondary)
            if !session.message.isEmpty { Text(session.message).font(.caption).accessibilityIdentifier("feed.message") }
            if session.busy { ProgressView() }
            Spacer()
            Text("IMPORT FIRST · READ ONLY · NO ACCOUNT SCRAPING").font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
        }.padding(26).disabled(session.busy)
    }
}

private struct FeedWorkspace: View {
    @ObservedObject var session: FeedSession
    var body: some View {
        TabView {
            NavigationStack { TimelineView(session: session) }.tabItem { Label("Лента", systemImage: "rectangle.stack") }
            NavigationStack { SourcesView(session: session) }.tabItem { Label("Источники", systemImage: "square.and.arrow.down") }
            NavigationStack { PrivacyView(session: session) }.tabItem { Label("Контроль", systemImage: "lock.shield") }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Text(session.mode == .demo ? "ДЕМО · ВЫМЫШЛЕННЫЕ ДАННЫЕ" : "ЛОКАЛЬНО · ТОЛЬКО ЧТЕНИЕ")
                    .font(.system(.caption2, design: .monospaced)).accessibilityIdentifier("feed.mode")
                Spacer()
                Button { session.lock() } label: { Image(systemName: "lock.fill") }
                    .accessibilityLabel("Заблокировать").accessibilityIdentifier("feed.lock")
            }.padding(.horizontal).padding(.vertical, 9).background(.thinMaterial)
        }
    }
}
private struct TimelineView: View {
    @ObservedObject var session: FeedSession
    @State private var query = ""
    @State private var sourceID: UUID?
    private var feed: [FeedItem] { session.value.feed(sourceID: sourceID, query: query) }
    var body: some View {
        List {
            Section {
                if session.loadFailed { Text(session.message).foregroundStyle(.red) }
                Picker("Источник", selection: $sourceID) {
                    Text("Все источники").tag(UUID?.none)
                    ForEach(session.value.sources) { Text($0.source.label).tag(Optional($0.id)) }
                }
                Text("Записей: \(feed.count)").font(.caption).accessibilityIdentifier("feed.count")
                Text("Нет входящих в архиве ≠ нет входящих в сервисе. Состояние аккаунтов не синхронизируется автоматически.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if feed.isEmpty {
                ContentUnavailableView("Записей пока нет", systemImage: "tray", description: Text("Создайте источник и подтвердите импорт. Пустая лента не означает отсутствие сообщений в сервисе."))
            } else {
                ForEach(feed) { item in
                    NavigationLink { ItemDetailView(session: session, key: item.key) } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(verbatim: session.value.sources.first { $0.id == item.key.sourceID }?.source.label ?? "Источник")
                                    .font(.caption.bold()).foregroundStyle(.indigo)
                                Spacer()
                                Text(origin(item.acquisition)).font(.caption2).foregroundStyle(.secondary)
                            }
                            if !item.title.isEmpty { Text(verbatim: item.title).font(.headline).lineLimit(2) }
                            Text(verbatim: item.body).lineLimit(3)
                            Text(item.occurredAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Время источника не указано")
                                .font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 5)
                    }.accessibilityIdentifier("feed.item.\(item.key.externalID)")
                }
            }
        }
        .navigationTitle("Личная лента")
        .searchable(text: $query, prompt: "Поиск по исходным записям")
    }
}
private func origin(_ value: Acquisition) -> String {
    switch value { case .userMappedFile: return "РУЧНОЙ ИМПОРТ"; case .userEndpoint: return "ВАШ ENDPOINT"; case .syntheticDemo: return "ВЫМЫШЛЕНО" }
}
private struct ItemDetailView: View {
    @ObservedObject var session: FeedSession
    let key: ItemKey
    @State private var note = ""
    private var item: FeedItem? { session.value.items.first { $0.key == key } }
    var body: some View {
        List {
            if let item {
                Section("Исходная запись · ревизия \(item.revision)") {
                    if !item.title.isEmpty { Text(verbatim: item.title).font(.headline) }
                    Text(verbatim: item.body).textSelection(.enabled)
                    if let author = item.author { LabeledContent("Автор") { Text(verbatim: author) } }
                    LabeledContent("Происхождение", value: origin(item.acquisition))
                    LabeledContent("Дата источника", value: item.occurredAt.map { $0.formatted() } ?? "Не указана")
                    LabeledContent("Получено клиентом", value: item.importedAt.formatted())
                    Text("При импорте провайдер и поля выбираются пользователем. Это не подтверждение подлинности сообщения сервисом.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Мои заметки — не сообщения сервиса") {
                    ForEach(session.value.annotations.filter { $0.references.contains { $0.key == key } }) { annotation in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(annotation.kind == .personalNote ? "Личная заметка" : "AI-интерпретация").font(.caption.bold())
                            Text(verbatim: annotation.text)
                            Button("Удалить заметку", role: .destructive) { Task { await session.deleteNote(annotation.id) } }
                        }
                    }
                    TextField("Новая личная заметка", text: $note).accessibilityIdentifier("feed.note")
                    Button("Сохранить заметку") {
                        let text = note
                        Task { if await session.addNote(text, item: item) { note = "" } }
                    }.disabled(session.busy || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("feed.saveNote")
                    if !session.message.isEmpty { Text(session.message).font(.caption).accessibilityIdentifier("feed.noteStatus") }
                }
                Section {
                    Text("Автоматическая отправка текста в Qwen или облачную модель отключена. Контракт AI-аннотаций отделён от записей; генератор к личной ленте ещё не подключён.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else { Text("Исходная запись удалена.") }
        }.navigationTitle("Запись").navigationBarTitleDisplayMode(.inline)
    }
}
private struct SourcesView: View {
    @ObservedObject var session: FeedSession
    @State private var adding = false
    var body: some View {
        List {
            Section {
                Text(session.mode == .demo ? "Демо не подключено к вашим аккаунтам." : "Импортируйте только данные, которыми вы вправе пользоваться. Логины и пароли здесь не запрашиваются.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Добавить источник") { adding = true }.disabled(session.mode != .personal || session.loadFailed || session.busy)
                    .accessibilityIdentifier("feed.addSource")
            }
            ForEach(session.value.sources) { state in
                NavigationLink { SourceDetailView(session: session, sourceID: state.id) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: state.source.label).font(.headline)
                        Text("\(state.source.provider.title) · \(state.source.coverage.title)").font(.caption)
                        Text(state.lastImportedAt.map { "Последнее получение: \($0.formatted())" } ?? "Данные ещё не получены")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("feed.source.\(state.source.provider.rawValue)")
            }
            Section("Hornet") {
                Text(SourceCapability.forProvider(.hornet).explanation).font(.caption)
                Link("Как запросить личный архив Hornet", destination: URL(string: "https://hornetnetworks.zendesk.com/hc/en-us/articles/31333277569810-How-do-I-request-a-copy-of-my-personal-data")!)
                Text("Нативный адаптер будет проверен на реальном формате выгрузки. Пока CSV/JSON импортируется только с предпросмотром и ручным выбором полей.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Источники")
            .sheet(isPresented: $adding) { AddSourceView(session: session) }
    }
}
private struct AddSourceView: View {
    @ObservedObject var session: FeedSession
    @Environment(\.dismiss) private var dismiss
    @State private var provider = Provider.hornet
    @State private var label = ""
    @State private var coverage = Coverage.unknown
    @State private var endpoint = false
    var body: some View {
        NavigationStack {
            Form {
                Picker("Сервис", selection: $provider) {
                    ForEach([Provider.hornet, .grindr, .other], id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Название локального источника", text: $label).accessibilityIdentifier("feed.sourceLabel")
                Picker("Доступная история", selection: $coverage) {
                    ForEach(Coverage.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if provider == .other { Toggle("Мой HTTPS Exchange v1 endpoint", isOn: $endpoint) }
                Text(SourceCapability.forProvider(provider).explanation).font(.caption)
                Button("Создать источник") {
                    let source = FeedSource(provider: provider, label: label.isEmpty ? provider.title : label,
                                            acquisition: provider == .other && endpoint ? .userEndpoint : .userMappedFile, coverage: coverage)
                    Task { await session.addSource(source); if session.value.sources.contains(where: { $0.id == source.id }) { dismiss() } }
                }.disabled(session.busy).accessibilityIdentifier("feed.createSource")
                if !session.message.isEmpty { Text(session.message).font(.caption) }
            }.navigationTitle("Новый источник").toolbar { Button("Отмена") { dismiss() } }
        }
    }
}
private struct PrivacyView: View {
    @ObservedObject var session: FeedSession
    @State private var confirmErase = false
    var body: some View {
        List {
            Section("Границы") {
                Label("Отдельное приложение и контейнер", systemImage: "square.stack.3d.up")
                Label("Личные записи не доступны игре и NPC", systemImage: "lock.shield")
                Label("Нет облачной синхронизации и контентных логов", systemImage: "icloud.slash")
                Text("Личный архив шифруется AES-GCM. Ключ хранится в Keychain этого устройства. Файлы используют полную защиту iOS и исключены из резервного копирования.").font(.caption)
                Text("При переходе в фон клиент блокируется и скрывает содержимое. Это не запрет пользователю делать скриншоты.").font(.caption)
            }
            Section("Демо и возможности") {
                Text("Работают: импорт с предпросмотром, поиск, личные заметки, удаление источника и ручное получение вашего HTTPS JSON-feed.")
                Text("Не подключены: живой Hornet/Grindr API, входящие уведомления других приложений, отправка сообщений и Qwen-анализ личных текстов.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Text(session.message).font(.caption).accessibilityIdentifier("feed.message")
                Button("Удалить все локальные данные", role: .destructive) { confirmErase = true }
                    .disabled(session.busy).accessibilityIdentifier("feed.erase")
                Text("Это не удаляет данные в Hornet/Grindr и исходные файлы в «Файлах». Физическое стирание всех следов из флеш-памяти не обещается.").font(.caption)
            }
        }.navigationTitle("Контроль данных")
            .confirmationDialog("Удалить архив и заметки этого клиента?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Удалить локальный архив", role: .destructive) { Task { await session.eraseAll() } }
            }
    }
}
