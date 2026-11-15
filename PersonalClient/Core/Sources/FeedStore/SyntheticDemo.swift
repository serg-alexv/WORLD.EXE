import Foundation
import FeedDomain

/// Entirely fictional. No sample is represented as an actual Hornet/Grindr export.
public enum SyntheticDemo {
    public static let source = FeedSource(id: UUID(uuidString: "B02E1E11-0000-4000-8000-000000000001")!, provider: .demonstration,
                                         label: "Вымышленная лента", acquisition: .syntheticDemo, coverage: .partial)
    public static func vault() throws -> FeedVault {
        var value = FeedVault(); try value.addSource(source)
        let date = Date(timeIntervalSince1970: 1_794_700_800)
        let records = [
            IncomingItem(key: .init(sourceID: source.id, externalID: "demo-01"), title: "Совместный проект", body: "Вымышленная запись: обсудим прототип после прогулки?", author: "Демо-участник А", occurredAt: date, direction: .incoming),
            IncomingItem(key: .init(sourceID: source.id, externalID: "demo-02"), title: "Моя отправленная запись", body: "Вымышленная запись: договорились проверить локальный поиск.", author: "Демо-владелец", occurredAt: date.addingTimeInterval(-3600), direction: .outgoing),
            IncomingItem(key: .init(sourceID: source.id, externalID: "demo-03"), title: "Дата отсутствует", body: "Эта карточка показывает неизвестное время, а не подставляет дату импорта.", direction: .unspecified)
        ]
        try value.ingest(records, sourceID: source.id, at: date.addingTimeInterval(600))
        return value
    }
}
