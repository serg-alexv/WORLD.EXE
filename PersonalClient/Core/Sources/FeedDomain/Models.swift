import Foundation

public enum FeedError: Error, Equatable, LocalizedError {
    case malformed, unsupportedFormat, tooLarge, missingColumn, invalidDate
    case invalidRecord, duplicateConflict, sourceMismatch, unsupportedSource
    case staleReference, invalidAnnotation, capacity, invalidArchive, insecureEndpoint
    public var errorDescription: String? {
        switch self {
        case .malformed: return "Файл повреждён или не соответствует выбранному формату."
        case .unsupportedFormat: return "Поддерживаются UTF-8 CSV и JSON-массив объектов. ZIP и неизвестные схемы не импортируются автоматически."
        case .tooLarge: return "Превышен допустимый размер файла или поля."
        case .missingColumn: return "Выберите разные поля идентификатора и текста."
        case .invalidDate: return "Дата не распознана. Выберите ISO 8601, Unix-секунды или не импортируйте это поле."
        case .invalidRecord: return "Некорректная запись. Импорт остановлен целиком."
        case .duplicateConflict: return "В одном импорте есть разные записи с одинаковым ID. Ничего не сохранено."
        case .sourceMismatch: return "Запись принадлежит другому источнику."
        case .unsupportedSource: return "Этот способ подключения источника пока не поддерживается."
        case .staleReference: return "Исходная запись изменилась или удалена. Создайте аннотацию заново."
        case .invalidAnnotation: return "Аннотация не соответствует выбранным исходным записям."
        case .capacity: return "Лимит локального стенда: 2 000 записей и 32 источника. Удалите ненужный источник."
        case .invalidArchive: return "Локальный архив не прошёл проверку. Он не будет перезаписан автоматически."
        case .insecureEndpoint: return "Нужен HTTPS-адрес без логина, пароля, query-параметров и фрагмента."
        }
    }
}
public enum Provider: String, Codable, CaseIterable, Sendable {
    case hornet, grindr, other, demonstration
    public var title: String {
        switch self { case .hornet: return "Hornet"; case .grindr: return "Grindr"; case .other: return "Другой источник"; case .demonstration: return "Демонстрация" }
    }
}
public enum Acquisition: String, Codable, Sendable { case userMappedFile, userEndpoint, syntheticDemo }
public enum Coverage: String, Codable, CaseIterable, Sendable {
    case unknown, partial, outgoingOnly
    public var title: String {
        switch self { case .unknown: return "Полнота неизвестна"; case .partial: return "Частичная история"; case .outgoingOnly: return "Только исходящие" }
    }
}
public enum Direction: String, Codable, Sendable { case incoming, outgoing, unspecified }
public enum AnnotationKind: String, Codable, Sendable { case personalNote, modelInterpretation }

public struct FeedSource: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let provider: Provider
    public let label: String
    public let acquisition: Acquisition
    public let coverage: Coverage
    public init(id: UUID = UUID(), provider: Provider, label: String, acquisition: Acquisition, coverage: Coverage = .unknown) {
        self.id = id; self.provider = provider; self.label = label; self.acquisition = acquisition; self.coverage = coverage
    }
    public var isValid: Bool {
        guard id != zeroID, validText(label, maximum: 240, allowEmpty: false) else { return false }
        if provider == .demonstration { return acquisition == .syntheticDemo }
        if acquisition == .syntheticDemo { return false }
        // A custom endpoint must never masquerade as an approved Hornet/Grindr API.
        return acquisition != .userEndpoint || provider == .other
    }
}
public struct ItemKey: Codable, Hashable, Sendable {
    public let sourceID: UUID
    public let externalID: String
    public init(sourceID: UUID, externalID: String) { self.sourceID = sourceID; self.externalID = externalID }
    public var isValid: Bool { sourceID != zeroID && validText(externalID, maximum: 512, allowEmpty: false) }
}
public struct IncomingItem: Equatable, Sendable {
    public let key: ItemKey
    public let title: String
    public let body: String
    public let author: String?
    public let occurredAt: Date?
    public let direction: Direction
    public init(key: ItemKey, title: String = "", body: String, author: String? = nil, occurredAt: Date? = nil, direction: Direction = .unspecified) {
        self.key = key; self.title = title; self.body = body; self.author = author; self.occurredAt = occurredAt; self.direction = direction
    }
    public var isValid: Bool {
        key.isValid && validText(title, maximum: 768) && validText(body, maximum: 16_384, allowEmpty: false) &&
        (author.map { validText($0, maximum: 512) } ?? true) && (occurredAt.map(validDate) ?? true)
    }
}
public struct FeedItem: Codable, Equatable, Identifiable, Sendable {
    public var id: ItemKey { key }
    public let key: ItemKey
    public let title: String
    public let body: String
    public let author: String?
    public let occurredAt: Date?
    public let direction: Direction
    public let revision: UInt64
    public let importedAt: Date
    public let acquisition: Acquisition
    public init(_ value: IncomingItem, revision: UInt64, importedAt: Date, acquisition: Acquisition) {
        key = value.key; title = value.title; body = value.body; author = value.author; occurredAt = value.occurredAt
        direction = value.direction; self.revision = revision; self.importedAt = importedAt; self.acquisition = acquisition
    }
    public var incoming: IncomingItem { .init(key: key, title: title, body: body, author: author, occurredAt: occurredAt, direction: direction) }
    public var isValid: Bool { incoming.isValid && revision > 0 && validDate(importedAt) }
}
public struct ItemReference: Codable, Equatable, Sendable {
    public let key: ItemKey
    public let revision: UInt64
    public init(_ item: FeedItem) { key = item.key; revision = item.revision }
}
public struct FeedAnnotation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: AnnotationKind
    public let text: String
    public let references: [ItemReference]
    public let engine: String?
    public init(id: UUID = UUID(), kind: AnnotationKind, text: String, references: [ItemReference], engine: String? = nil) {
        self.id = id; self.kind = kind; self.text = text; self.references = references; self.engine = engine
    }
    public var isValid: Bool {
        guard id != zeroID, validText(text, maximum: 8_192, allowEmpty: false), (1...20).contains(references.count),
              Set(references.map(\.key)).count == references.count,
              references.allSatisfy({ $0.key.isValid && $0.revision > 0 }) else { return false }
        return kind == .personalNote ? engine == nil : engine.map { validText($0, maximum: 256, allowEmpty: false) } ?? false
    }
}
public let zeroID = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
public func validDate(_ date: Date) -> Bool {
    let value = date.timeIntervalSince1970
    return value.isFinite && (0...253_402_300_799).contains(value)
}
public func validText(_ text: String, maximum: Int, allowEmpty: Bool = true) -> Bool {
    text.utf8.count <= maximum && !text.unicodeScalars.contains(where: { $0.value == 0 }) &&
    (allowEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}
