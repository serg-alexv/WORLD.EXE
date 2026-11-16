import SwiftUI
import EvidenceCore

struct EvidenceScreen: View {
    @ObservedObject var store: EvidenceStore
    @Environment(\.dismiss) private var dismiss
    @State private var lane = EvidenceLane.observation
    @State private var urls: [URL] = []
    @State private var sharing = false
    @State private var exporting = false
    @State private var confirmClear = false
    private var snapshot: EvidenceSnapshot { store.snapshot }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("ТРИ НЕЗАВИСИМЫХ ЖУРНАЛА").font(.headline)
                    Text("Оценка пространства ≠ телеметрия устройства ≠ игровая выдумка. Ответ модели — интерпретация, не измерение.")
                        .font(.caption).accessibilityIdentifier("evidence.boundary")
                    Toggle("Записывать локально", isOn: $store.recording).accessibilityIdentifier("evidence.recording")
                    Text("Без кадров камеры, звука, запросов и ответов LLM. Не отправляется партнёру или на сервер. 128 записей на раздел; старые вытесняются со счётчиком.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Раздел журнала", selection: $lane) {
                        Text("Наблюдения").tag(EvidenceLane.observation)
                        Text("Телеметрия").tag(EvidenceLane.telemetry)
                        Text("Игра").tag(EvidenceLane.gameplay)
                    }.pickerStyle(.segmented).accessibilityIdentifier("evidence.lanes")
                    switch lane {
                    case .observation:
                        Text("Оценки RoomPlan/ARKit. Это не сырые или калиброванные физические измерения. Архив и сведения партнёра помечаются отдельно.").font(.caption)
                        Text("Записей: \(snapshot.observations.count) · вытеснено: \(snapshot.observationEvictions)").accessibilityIdentifier("evidence.observation.count")
                        if snapshot.observations.isEmpty { Text("Наблюдений пока нет. Игра и GGUF не создают сенсорные данные.").accessibilityIdentifier("evidence.observation.empty") }
                        ForEach(snapshot.observations.reversed(), id: \.stamp.id) { record in
                            row(observationTitle(record), detail: "\(record.source.rawValue) · \(origin(record.origin))\n\(date(record.stamp.recordedAt)) · №\(record.stamp.sequence)\nИсточник: \(record.captureID.uuidString.prefix(8))" + (record.capturedAt.map { "\nВремя исходной оценки: \(date($0))" } ?? ""))
                        }
                    case .telemetry:
                        Text("Реальные события программы: длительность запроса, токены, байты сети, нагрев. Время запроса включает обработку промпта. RAM, FPS и фактическое исполнение Metal пока не измеряются.").font(.caption)
                        Text("Записей: \(snapshot.telemetry.count) · вытеснено: \(snapshot.telemetryEvictions)").accessibilityIdentifier("evidence.telemetry.count")
                        if snapshot.telemetry.isEmpty { Text("Телеметрии пока нет.").accessibilityIdentifier("evidence.telemetry.empty") }
                        ForEach(snapshot.telemetry.reversed(), id: \.stamp.id) { record in
                            row(telemetryTitle(record.payload), detail: "\(date(record.stamp.recordedAt)) · №\(record.stamp.sequence)")
                        }
                    case .gameplay:
                        Text("Только игровые команды, ревизии и очки. «Осмотреть узел» не означает физическое наблюдение аномалии.").font(.caption)
                        Text("Записей: \(snapshot.gameplay.count) · вытеснено: \(snapshot.gameplayEvictions)").accessibilityIdentifier("evidence.gameplay.count")
                        if snapshot.gameplay.isEmpty { Text("Игровых событий пока нет.") }
                        ForEach(snapshot.gameplay.reversed(), id: \.stamp.id) { record in
                            row("ИГРА · \(record.action)", detail: "\(record.kind.rawValue) · \(date(record.stamp.recordedAt)) · №\(record.stamp.sequence)" + (record.score.map { "\nИгровые очки: \($0)" } ?? ""))
                        }
                    }
                    Divider()
                    Text(store.status).font(.caption).accessibilityIdentifier("evidence.status")
                    Button("Экспортировать три журнала") {
                        exporting = true
                        store.export { result in urls = result; sharing = !result.isEmpty; exporting = false }
                    }.disabled(exporting).buttonStyle(.borderedProminent).accessibilityIdentifier("evidence.export")
                    if FileManager.default.fileExists(atPath: store.previousURL.path) {
                        Button("Экспорт предыдущего запуска") { urls = [store.previousURL]; sharing = true }
                    }
                    Button("Очистить выбранный журнал", role: .destructive) { confirmClear = true }
                        .accessibilityIdentifier("evidence.clear")
                    Text("Сохраняется текущий и один предыдущий запуск. Прерывание приложения может потерять последнюю секунду. Геометрия комнаты и модель хранятся отдельно; очистка журнала их не удаляет.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding()
            }
            .background(Palette.background).tint(Palette.teal)
            .navigationTitle("Наблюдения и телеметрия").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Закрыть") { store.flush(); dismiss() }.accessibilityIdentifier("evidence.close") } }
        }
        .sheet(isPresented: $sharing) { ExportSheet(urls: urls) }
        .alert("Очистить текущий раздел?", isPresented: $confirmClear) {
            Button("Очистить", role: .destructive) { store.clear(lane) }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Другие журналы, комната, GGUF и игровой прогресс не изменятся. Предыдущий запуск сохраняется отдельно.") }
    }
    private func row(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.callout)
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
    }
    private func date(_ d: Date) -> String { d.formatted(date: .abbreviated, time: .standard) }
    private func origin(_ o: ObservationOrigin) -> String {
        switch o { case .localSensor: return "локальная оценка"; case .restoredArchive: return "архив, не новый скан"; case .peerReport: return "сообщение партнёра, локально не проверено" }
    }
    private func observationTitle(_ r: ObservationRecord) -> String {
        switch r.payload {
        case .roomSummary(let n): return "ОЦЕНКА · элементов комнаты: \(n)"
        case .meshSummary(let v, let t): return "ОЦЕНКА · фрагмент сетки: \(v) вершин, \(t) треугольников"
        case .tracking(let q): return "ОЦЕНКА · отслеживание: \(q.rawValue)"
        }
    }
    private func telemetryTitle(_ p: TelemetryPayload) -> String {
        switch p {
        case .inference(let i):
            let rate = i.requestTokensPerSecond.map { String(format: "%.2f токен/с", $0) } ?? "скорость не измерена"
            return "llama.cpp · \(i.outcome.rawValue)\nТокены: \(i.tokens.map(String.init) ?? "нет данных") · \(rate)\nЗапрошен: \(i.requestedBackend.rawValue); подтверждён: \(i.confirmedBackend?.rawValue ?? "нет данных")\nМодель SHA-256: \(i.modelSHA256.prefix(12))"
        case .network(let n, let outbound, let accepted): return "Сеть · \(outbound ? "отправка" : "приём") · \(n) байт · \(accepted ? "принято локально" : "отклонено локально")"
        case .runtime(let condition): return "Устройство/приложение: \(condition.rawValue)"
        case .captureDuration(let s, let result): return String(format: "Сканирование: %.2f с · %@", s, result.rawValue)
        }
    }
}
