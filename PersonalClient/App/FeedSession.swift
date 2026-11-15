import Foundation
import Combine
import LocalAuthentication
import FeedDomain
import FeedAdapters
import FeedStore

@MainActor final class FeedSession: ObservableObject {
    enum Mode { case locked, demo, personal }
    @Published private(set) var mode: Mode = .locked
    @Published private(set) var value = FeedVault()
    @Published private(set) var busy = false
    @Published private(set) var message = ""
    @Published private(set) var loadFailed = false
    @Published private(set) var epoch = UUID()
    private let disk: PrivateVault
    private var auth: LAContext?
    private var transport: FeedTransport?
    private var operation: Task<Void, Never>?
    init(disk: PrivateVault = PrivateVault()) { self.disk = disk }
    var isOpen: Bool { mode != .locked }
    func startDemo() {
        guard !busy else { return }
        do { value = try SyntheticDemo.vault(); mode = .demo; message = "Демо: все записи вымышленные и существуют только в памяти." }
        catch { message = "Не удалось открыть демонстрацию." }
    }
    func unlock() async {
        guard !busy else { return }
        busy = true; message = ""; let token = epoch
        var authorized = false
        #if DEBUG && targetEnvironment(simulator)
        authorized = ProcessInfo.processInfo.arguments.contains("-feed-ui-testing")
        #endif
        if !authorized {
            let context = LAContext(); auth = context
            do {
                authorized = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                    localizedReason: "Открыть локальные личные записи. Данные не передаются на сервер.")
            } catch { authorized = false }
            auth = nil
        }
        guard token == epoch else { return }
        guard authorized else { busy = false; message = "Личное пространство не открыто. Доступна демонстрация."; return }
        do {
            let loaded = try await disk.load()
            guard token == epoch else { return }
            value = loaded; mode = .personal; loadFailed = false; busy = false
        } catch {
            guard token == epoch else { return }
            value = FeedVault(); mode = .personal; loadFailed = true; busy = false
            message = "Защищённый архив не прочитан. Импорт заблокирован, чтобы не перезаписать данные. Можно повторно разблокировать или явно удалить локальный архив."
        }
    }
    func lock() {
        epoch = UUID(); auth?.invalidate(); auth = nil; transport?.cancel(); transport = nil
        operation?.cancel(); operation = nil; value = FeedVault(); mode = .locked; busy = false; message = ""; loadFailed = false
    }
    @discardableResult private func commit(_ candidate: FeedVault, success: String) async -> Bool {
        guard isOpen, !busy, !loadFailed else { return false }
        busy = true; let token = epoch, privateMode = mode == .personal
        do {
            if privateMode { try await disk.save(candidate) }
            guard token == epoch else { return false }
            value = candidate; message = success; busy = false
            return true
        } catch {
            guard token == epoch else { return false }
            message = (error as? PrivateVault.VaultFailure)?.errorDescription ?? "Не удалось сохранить. Изменение не применено."; busy = false
            return false
        }
    }
    func addSource(_ source: FeedSource) async {
        guard mode == .personal else { message = "Для личных источников откройте защищённое пространство."; return }
        do { var next = value; try next.addSource(source); await commit(next, success: "Источник создан. Данные ещё не загружены.") }
        catch { show(error) }
    }
    func importItems(_ batch: [IncomingItem], source: FeedSource) async {
        do {
            var next = value
            let receipt = try next.ingest(batch, sourceID: source.id)
            await commit(next, success: "Добавлено: \(receipt.inserted), обновлено: \(receipt.updated), без изменений: \(receipt.unchanged). Снято устаревших аннотаций: \(receipt.invalidatedAnnotations).")
        } catch { show(error) }
    }
    @discardableResult func addNote(_ text: String, item: FeedItem) async -> Bool {
        do {
            var next = value
            try next.annotate(.init(kind: .personalNote, text: text, references: [.init(item)]))
            return await commit(next, success: "Заметка сохранена отдельно от исходной записи.")
        } catch { show(error); return false }
    }
    func deleteSource(_ id: UUID) async {
        var next = value; next.deleteSource(id)
        await commit(next, success: "Источник, его записи и зависимые заметки удалены из клиента. Оригинальный сервис не изменён.")
    }
    func deleteNote(_ id: UUID) async {
        var next = value; next.deleteAnnotation(id); await commit(next, success: "Заметка удалена.")
    }
    func eraseAll() async {
        guard !busy, isOpen else { return }
        busy = true; let token = epoch
        do {
            if mode == .personal { try await disk.erase() }
            guard token == epoch else { return }
            value = FeedVault(); loadFailed = false; busy = false; message = "Локальные данные удалены. Сервисы и исходные файлы не изменены."
        } catch { guard token == epoch else { return }; busy = false; message = "Удаление не подтверждено. Повторите после разблокировки устройства." }
    }
    func fetch(source: FeedSource, endpoint: String) {
        guard mode == .personal, !busy, !loadFailed, source.provider == .other, source.acquisition == .userEndpoint else { return }
        do {
            let url = try EndpointPolicy.validate(endpoint)
            let token = epoch, client = FeedTransport(); transport = client; busy = true
            operation = Task {
                do {
                    let data = try await client.get(url)
                    try Task.checkCancellation()
                    let rows = try ExchangeDocument.decode(data, source: source)
                    guard epoch == token else { return }
                    busy = false; transport = nil
                    await importItems(rows, source: source)
                } catch {
                    guard epoch == token else { return }
                    busy = false; transport = nil
                    message = "Запрос не выполнен. Проверьте HTTPS, контракт Exchange v1 и доступность источника. Личные данные и адрес запроса в журнал не записаны."
                }
            }
        } catch { show(error) }
    }
    func show(_ error: Error) {
        // Never stringify decoder/URL/file errors containing private source content or paths.
        message = (error as? FeedError)?.errorDescription ?? "Операция не выполнена. Данные не изменены."
    }
}
