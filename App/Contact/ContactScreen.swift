import SwiftUI
import ARKit
import WorldCore

@MainActor struct ContactScreen: View {
    @ObservedObject var room: RoomCaptureModel
    @ObservedObject var brain: OnDeviceBrain
    private let evidence: EvidenceStore?
    @StateObject private var c: ContactSessionController
    init(room: RoomCaptureModel, brain: OnDeviceBrain, evidence: EvidenceStore? = nil) {
        self.room = room; self.brain = brain; self.evidence = evidence
        _c = StateObject(wrappedValue: ContactSessionController(evidence: evidence))
    }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var zoom = 1.0
    @State private var focusCapsule = true
    @State private var advice = ""
    @State private var asking = false
    private var testMode: Bool { ProcessInfo.processInfo.arguments.contains("-contact-hot-seat") }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button("Назад") { dismiss() }.accessibilityIdentifier("contact.dismiss")
                Spacer(); Text("CONTACT / Живая капсула").font(.headline); Spacer()
            }.padding(.horizontal)
            if c.mode == .demo {
                Text("Демонстрация / один экран • вымышленный стол • без соединения").font(.caption).foregroundStyle(Palette.amber).accessibilityIdentifier("contact.demo.banner")
                HStack {
                    Button("Исследователь") { c.switchRole(.researcher) }.accessibilityIdentifier("contact.role.researcher")
                    Button("Оператор") { c.switchRole(.operator) }.accessibilityIdentifier("contact.role.operator")
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(c.message).accessibilityIdentifier("contact.message")
                    if c.mode == .lobby || (c.mode == .guest && c.state == nil) { ContactLobby(c: c, peer: c.peer, room: room, testMode: testMode) }
                    else { game }
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(.white).background(Palette.background.ignoresSafeArea())
        .buttonStyle(.bordered).controlSize(.large)
        .alert("Принять выбранного оператора?", isPresented: Binding(get: { c.peer.pendingName != nil }, set: { if !$0 { c.peer.answer(false) } })) {
            Button("Отклонить", role: .cancel) { c.peer.answer(false) }; Button("Принять") { c.peer.answer(true) }
        } message: { Text("\(c.peer.pendingName ?? "Участник"). Геометрия будет передана только этому участнику. Сверьте имя лично; код не подтверждает личность.") }
        .onChange(of: scenePhase) { _, phase in c.setBackground(phase != .active) }
        .onChange(of: room.contactGeneration) { _, generation in c.captureChanged(generation) }
        .onChange(of: room.contactSession == nil) { _, missing in if missing && c.mode == .host { c.pause() } }
        .onChange(of: room.scanning || room.processing) { _, busy in if busy && c.mode == .host { c.pause() } }
        .onChange(of: c.role) { _, _ in brain.cancel(); advice = ""; asking = false }
        .onDisappear { c.close(); brain.cancel() }
    }
    @ViewBuilder private var game: some View {
        if let s = c.state, let geometry = c.geometry {
            Text(c.role == .researcher ? "Исследователь: осмотрите узел и назовите символ. После настройки оператором стабилизируйте его. В конце выберите капсулу и извлеките её." : "Оператор: найдите услышанный символ в руководстве. Выберите осмотренный узел, включите питание и задайте канал. После трёх стабилизаций разрешите извлечение.")
            Text("Узлы: \(s.stabilized.nonzeroBitCount)/3 • Ошибки: \(s.mistakes) • Очки: \(s.score)").font(.subheadline)
            if c.mode != .demo {
                Text(c.peer.status).font(.caption)
                if c.mode == .host { Text("Ваше имя: \(ContactPeer.name(c.peer.identity)) • Код: \(c.peer.code)").textSelection(.enabled) }
                Button("Продолжить") { c.resume() }.disabled(!c.peer.connected || (c.mode == .host && !c.tracking)).accessibilityIdentifier("contact.continue")
                Text(c.localReady && c.remoteReady ? "Оба игрока готовы" : "Пауза: требуется подтверждение обоих игроков").foregroundStyle(Palette.amber)
            }
            if c.mode == .host {
                Text("Источник: оценка RoomPlan • размещение: игровая модель").font(.caption)
                Text(c.trackingText).font(.caption).accessibilityIdentifier("contact.tracking")
                Text("Не бегите. Выберите свободный безопасный стол; все узлы находятся не дальше 35 см от капсулы. Геометрия приблизительная.").font(.caption)
                #if targetEnvironment(simulator)
                Text("Реальный AR недоступен на симуляторе.")
                #else
                if let session = c.arSession, room.contactSession === session, room.contactGeneration == c.captureID {
                    ContactARView(session: session, room: geometry, state: s, glyphs: c.mission?.researcher.glyphs ?? [nil,nil,nil], anchor: c.arAnchor,
                                  active: scenePhase == .active && !room.scanning && !room.processing, canPlace: c.canPlace, canTap: c.canAct,
                                  onTracking: c.track, evidence: evidence, onPlace: c.placed, onMove: c.anchorUpdated, onTap: c.selectAR, onNote: c.note)
                        .frame(height: 290).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("contact.ar")
                } else { Text("Требуется новое сканирование комнаты в этой сессии.") }
                #endif
            } else {
                Text(geometry.synthetic ? "Источник: вымышленный стол • игровая модель" : "Источник: оценка RoomPlan • узлы: игровая модель").font(.caption)
                ContactMapView(room: geometry, state: s, root: c.root, zoom: zoom, focusCapsule: focusCapsule).frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 12))
                Button(focusCapsule ? "Показать всю комнату" : "Приблизить капсулу") { focusCapsule.toggle(); zoom = 1 }
                    .accessibilityIdentifier("contact.mapFocus")
                HStack {
                    Button("− Масштаб") { zoom = max(0.5,zoom - 0.25) }.accessibilityLabel("Уменьшить карту")
                    Button("+ Масштаб") { zoom = min(3,zoom + 0.25) }.accessibilityLabel("Увеличить карту")
                    Button("Сброс") { zoom = 1 }.accessibilityLabel("Сбросить масштаб карты")
                }
            }
            if s.phase == .complete {
                Text("Капсула извлечена!").font(.title2.bold()).accessibilityIdentifier("contact.success")
                Text("Все три узла стабилизированы. Для смены ролей вернитесь в лобби: новый исследователь делает свежий скан на своём устройстве, затем создаёт пару. В демонстрации просто переключайте роли.")
                if c.mode != .guest { Button("Сыграть ещё") { c.replay() }.accessibilityIdentifier("contact.replay") }
            } else {
                if c.mode == .demo || c.role == .operator {
                    ForEach(0..<3, id: \.self) { n in
                        Button("Узел \(n+1)\(s.isStable(n) ? " • стабилен" : s.poweredNode == n ? " • питание" : "")") { c.selected = n; c.capsuleSelected = false }
                            .frame(minHeight: 44).accessibilityIdentifier("contact.node.\(n)").accessibilityAddTraits(c.selected == n ? .isSelected : [])
                    }
                }
                Text("Выбран узел \(c.selected+1)").font(.headline)
                if c.role == .researcher {
                    if let glyph = c.glyph { Text("Символ: \(glyph.title)").foregroundStyle(Palette.teal).accessibilityLabel(glyph.title).accessibilityIdentifier("contact.glyph.\(c.selected)") }
                    else { Text(c.mode == .demo ? "Нажмите «Осмотреть»." : "Коснитесь узла в AR для осмотра.") }
                    if c.mode == .demo {
                        Button("Осмотреть") { c.act(.inspect(c.selected)) }.disabled(!c.canAct || s.phase != .active || s.isInspected(c.selected)).accessibilityIdentifier("contact.inspect")
                    }
                    Button("Стабилизировать узел \(c.selected+1)") { c.act(.stabilize(c.selected)) }.disabled(!c.canStabilize).accessibilityIdentifier("contact.stabilize")
                    if c.mode == .demo { Button("Выбрать капсулу") { c.capsuleSelected = true }.accessibilityIdentifier("contact.capsule") }
                    Button("Извлечь капсулу") { c.act(.extract) }.disabled(!c.canExtract).accessibilityIdentifier("contact.extract")
                } else {
                    Text("Руководство: символ → канал").font(.headline)
                    ForEach(s.manual, id: \.glyph) { entry in Text("\(entry.glyph.title) → \(entry.channel)").accessibilityIdentifier("contact.manual.\(entry.glyph.rawValue)") }
                    Button("Подать питание на узел \(c.selected+1)") { c.act(.power(c.selected)) }
                        .disabled(!c.canAct || s.phase != .active || !s.isInspected(c.selected) || s.isStable(c.selected)).accessibilityIdentifier("contact.power")
                    ForEach(0..<3, id: \.self) { channel in
                        Button("Канал \(channel)\(s.channel == channel && s.poweredNode == c.selected ? " • выбран" : "")") { c.act(.tune(channel)) }
                            .disabled(!c.canAct || s.phase != .active || s.poweredNode != c.selected).accessibilityIdentifier("contact.channel.\(channel)")
                    }
                    Button("Разрешить извлечение") { c.act(.arm) }.disabled(!c.canAct || s.stabilized != 7 || s.phase != .active).accessibilityIdentifier("contact.arm")
                }
            }
            if c.pending != nil { Text("Ждём подтверждения ведущего…").accessibilityIdentifier("contact.pending") }
            Button("Совет модели по моей роли") { ask(s) }.disabled(!brain.isLoaded || brain.isBusy || asking)
                .accessibilityIdentifier("contact.advice")
            Text("Модель необязательна. Передаются только роль и публичный прогресс, без скана и скрытых символов. Модель оператора остаётся на его устройстве.").font(.caption)
            if !advice.isEmpty {
                Text("ИНТЕРПРЕТАЦИЯ МОДЕЛИ · НЕ НАБЛЮДЕНИЕ").font(.caption.bold()).foregroundStyle(Palette.amber)
                Text(advice).textSelection(.enabled)
            }
            if c.mode == .host && !c.peer.connected { Button("Перезапустить ожидание оператора") { c.host(room: room) } }
            if c.mode != .guest { Button("Новая миссия") { c.replay() }.disabled(c.mode == .host && !c.peer.connected) }
            Button("Лобби / переподключение") { brain.cancel(); advice = ""; c.lobby() }.accessibilityIdentifier("contact.lobby")
        }
    }
    private func ask(_ state: ContactPublicState) {
        guard brain.isLoaded, !brain.isBusy, !asking else { return }; asking = true; let role = c.role, session = state.session
        let prompt = "Краткий совет по кооперации CONTACT на русском без решения загадки. Роль: \(role == .researcher ? "исследователь: осмотр, устное сообщение, стабилизация" : "оператор: руководство, питание, канал"). Осмотрено \(state.inspected.nonzeroBitCount) из 3; стабилизировано \(state.stabilized.nonzeroBitCount); фаза \(state.phase.rawValue); ошибок \(state.mistakes). Не угадывай символы или каналы. Напомни не спешить."
        Task { await brain.respond(to: prompt); if c.role == role && c.state?.session == session { advice = String(brain.response.prefix(1200)) }; asking = false }
    }
}
@MainActor private struct ContactLobby: View {
    @ObservedObject var c: ContactSessionController
    @ObservedObject var peer: ContactPeer
    @ObservedObject var room: RoomCaptureModel
    let testMode: Bool
    @State private var consent = false
    @State private var code = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Исследователь сканирует комнату, ставит капсулу на свободный стол и сообщает символы. Оператор видит оценку той же комнаты без символов, сверяет руководство и настраивает каналы. После настройки исследователь стабилизирует каждый узел.")
            Button("Демонстрация / один экран") { c.demo() }.accessibilityIdentifier("contact.demo")
            Text("Демонстрация использует вымышленный стол. Камера, сеть и модель не нужны.").font(.caption)
            Toggle("Согласен передать обработанную геометрию комнаты только выбранному оператору. Без изображений камеры и звука.", isOn: $consent).frame(minHeight: 44).accessibilityIdentifier("contact.consent")
            Button("Исследователь / создать пару") { c.host(room: room) }.disabled(!consent || testMode).accessibilityIdentifier("contact.host")
            if room.contactSession == nil || room.contactGeneration == nil { Text("Требуется новое сканирование комнаты в этой сессии. Сохранённый архив не задаёт положение AR.").font(.caption) }
            Button("Оператор / найти ведущего") { c.join() }.disabled(testMode).accessibilityIdentifier("contact.join")
            Text(peer.status).font(.caption)
            Text("Ваше имя: \(ContactPeer.name(peer.identity))").font(.caption)
            TextField("Шестизначный код ведущего", text: $code).keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(minHeight: 44).accessibilityIdentifier("contact.code")
                .onChange(of: code) { _, next in code = String(next.filter { $0.isASCII && $0.isNumber }.prefix(6)) }
            ForEach(peer.hosts, id: \.self) { host in
                Button("Подключиться: \(ContactPeer.name(host))") { peer.invite(host, code: code) }.disabled(code.count != 6 || testMode).frame(minHeight: 44)
            }
            Text("Только локальная сеть, один партнёр. Сверьте отображаемые имена лично: код сам по себе не подтверждает личность. При потере связи игра ставится на паузу.").font(.caption)
        }
    }
}
