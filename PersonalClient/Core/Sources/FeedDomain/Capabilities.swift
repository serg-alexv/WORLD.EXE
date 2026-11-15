import Foundation

public struct SourceCapability: Sendable {
    public let provider: Provider
    public let fileImport: Bool
    public let manualFetch: Bool
    public var liveSync: Bool { false }
    public let explanation: String
    public static func forProvider(_ provider: Provider) -> Self {
        switch provider {
        case .hornet:
            return .init(provider: provider, fileImport: true, manualFetch: false,
                         explanation: "Hornet: доступен ручной импорт CSV/JSON с сопоставлением полей. Нативная схема архива и API не подтверждены. Beta Tester не считается API-разрешением.")
        case .grindr:
            return .init(provider: provider, fileImport: true, manualFetch: false,
                         explanation: "Grindr: ручной импорт. Официальная выгрузка сообщений не включает полученные сообщения; не считайте её полной перепиской.")
        case .other:
            return .init(provider: provider, fileImport: true, manualFetch: true,
                         explanation: "Ваш HTTPS JSON-источник по открытому контракту PersonalFeed Exchange v1. Только по кнопке; без аккаунтных токенов и фонового опроса.")
        case .demonstration:
            return .init(provider: provider, fileImport: false, manualFetch: false,
                         explanation: "Только вымышленные записи. Не подключено к аккаунтам и не подтверждает совместимость с экспортом Hornet.")
        }
    }
}
public enum EndpointPolicy {
    public static func validate(_ string: String) throws -> URL {
        guard string.utf8.count <= 2048, let c = URLComponents(string: string),
              c.scheme?.lowercased() == "https", let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.fragment == nil, c.query == nil,
              let url = c.url else { throw FeedError.insecureEndpoint }
        return url
    }
}
