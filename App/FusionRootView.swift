import SwiftUI
import PersonalFeedFeature

/// One active workspace at a time. This is a module boundary, not a separate OS sandbox.
/// The personal feature exports only a View, never its records/session to the game.
struct FusionRootView: View {
    private enum Workspace { case hub, expedition, sensors, personal }
    @State private var workspace: Workspace = .hub
    private var legacyUITest: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("-ui-testing") &&
            !ProcessInfo.processInfo.arguments.contains("-fusion-ui-testing")
        #else
        return false
        #endif
    }
    var body: some View {
        Group {
            if legacyUITest { HomeView() }
            else {
                switch workspace {
                case .hub: hub
                case .expedition: HomeView(onExit: { workspace = .hub })
                case .sensors: HomeView(initialMode: 1, onExit: { workspace = .hub })
                case .personal:
                    VStack(spacing: 0) {
                        HStack {
                            Button { workspace = .hub } label: {
                                Label("WORLD.EXE", systemImage: "square.grid.2x2")
                            }.accessibilityIdentifier("fusion.feedClose")
                            Spacer()
                            Text("PRIVATE WORKSPACE").font(.system(.caption2, design: .monospaced))
                        }.padding(.horizontal).padding(.vertical, 10)
                        FeedRootView(presentation: .combined)
                    }.background(Palette.background)
                }
            }
        }.tint(Palette.teal)
    }
    private var hub: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "viewfinder").font(.system(size: 30)).foregroundStyle(Palette.teal)
                    Spacer()
                    Text("FUSION / 0.4.0").font(.system(.caption, design: .monospaced)).foregroundStyle(Palette.amber)
                }
                Text("WORLD.EXE").font(.system(size: 38, weight: .black, design: .monospaced))
                    .accessibilityIdentifier("fusion.title")
                Text("Исследуй. Играй. Сохраняй своё.").font(.title3.weight(.medium))
                Text("Один стенд — разные источники истины.")
                    .font(.subheadline).foregroundStyle(.secondary)
                card("Экспедиции", subtitle: "Signal Siege · CONTACT вдвоём · изометрия",
                     detail: "Тактика с укрытиями, вымышленная Кира, чёрный юмор и локальный Top 10. GGUF загружается отдельно по вашему выбору.",
                     symbol: "hexagon.fill", badge: "ИГРА / ВЫМЫСЕЛ", id: "fusion.game") { workspace = .expedition }
                card("Пространственная лаборатория", subtitle: "LiDAR · RoomPlan · AR-капсула в CONTACT",
                     detail: "Реальная реконструкция на совместимом iPhone. Наблюдения, техническая телеметрия и игровые события разделены.",
                     symbol: "cube.transparent", badge: "СЕНСОРЫ / ОЦЕНКА ГЕОМЕТРИИ", id: "fusion.sensors") { workspace = .sensors }
                card("Личная лента", subtitle: "Импорт · поиск · заметки · защищённый архив",
                     detail: "Демо на вымышленных данных и ручной CSV/JSON-импорт. Живой Hornet/Grindr не подключён. Тексты не отправляются NPC или модели.",
                     symbol: "lock.rectangle.stack", badge: "ЛИЧНЫЕ ДАННЫЕ / БЕЗ LLM", id: "fusion.feed") { workspace = .personal }
                VStack(alignment: .leading, spacing: 7) {
                    Label("Первый запуск", systemImage: "play.circle").font(.headline)
                    Text("Экспедиции → Signal Siege: забери R и вернись на E. Для пары — CONTACT. Для ленты — «Открыть демонстрацию».")
                    Text("Локальный Qwen: Экспедиции → GGUF → загрузить файл → загрузить в память → ответить локально.")
                }.font(.caption).padding(14).background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
                Text("Личная лента — отдельный модуль и зашифрованный архив в том же приложении, не отдельная песочница iOS. При выходе она блокируется. Игровой мир не получает переписки.")
                    .font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("fusion.boundary")
            }.padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
        }.background(Palette.background).accessibilityIdentifier("fusion.hub")
    }
    private func card(_ title: String, subtitle: String, detail: String, symbol: String,
                      badge: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: symbol).font(.title2).foregroundStyle(Palette.teal)
                    Text(title).font(.title3.bold())
                    Spacer()
                    Image(systemName: "arrow.up.right").foregroundStyle(Palette.teal)
                }
                Text(subtitle).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(badge).font(.system(.caption2, design: .monospaced)).foregroundStyle(Palette.amber)
            }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.teal.opacity(0.22)))
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
}
