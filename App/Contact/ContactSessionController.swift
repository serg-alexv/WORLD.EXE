import Foundation
import Combine
import ARKit
import WorldCore
import EvidenceCore

@MainActor final class ContactSessionController: ObservableObject {
    enum Mode { case lobby, host, guest, demo }
    let peer = ContactPeer()
    private let evidence: EvidenceStore?
    @Published private(set) var mode: Mode = .lobby
    @Published private(set) var mission: ContactMission?
    @Published private(set) var received: ContactPublicState?
    @Published private(set) var geometry: ContactRoomDTO?
    @Published private(set) var root: [Float]?
    @Published private(set) var arAnchor: ARAnchor?
    @Published private(set) var arSession: ARSession?
    @Published private(set) var captureID: UUID?
    @Published private(set) var demoRole: ContactRole = .researcher
    @Published private(set) var localReady = false
    @Published private(set) var remoteReady = false
    @Published private(set) var tracking = false
    @Published private(set) var trackingText = "Ожидание AR"
    @Published private(set) var message = "Выберите демонстрацию или локальную пару."
    @Published private(set) var pending: ContactCommand?
    @Published var selected = 0
    @Published var capsuleSelected = false
    private var background = false
    private var timer: Timer?
    private var relay: AnyCancellable?
    private var lastSeen = Date.distantPast
    private var sentAt = Date.distantPast
    var state: ContactPublicState? { mode == .guest ? received : mission?.state }
    var role: ContactRole { mode == .guest ? .operator : mode == .demo ? demoRole : .researcher }
    var glyph: ContactGlyph? { guard role == .researcher, (0..<3).contains(selected) else { return nil }; return mission?.researcher.glyphs[selected] }
    var canAct: Bool { !background && pending == nil && root != nil && (mode == .demo || (peer.connected && localReady && remoteReady && (mode != .host || tracking))) }
    var canPlace: Bool { mode == .host && !background && tracking && localReady && remoteReady && peer.connected && root == nil }
    var canStabilize: Bool { guard let s = state, let g = glyph else { return false }; return canAct && s.phase == .active && s.poweredNode == selected && s.channel == g.channel }
    var canExtract: Bool { canAct && capsuleSelected && state?.phase == .extraction && role == .researcher }
    init(evidence: EvidenceStore? = nil) {
        self.evidence = evidence
        relay = peer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        peer.onData = { [weak self] in self?.receive($0) }; peer.onConnection = { [weak self] in self?.connection($0) }
    }
    func demo() {
        peer.stop(); timer?.invalidate(); timer = nil; mode = .demo; mission = ContactMission(seed: 7); received = nil
        geometry = .demo; root = ContactMath.identity; arSession = nil; arAnchor = nil; captureID = nil
        demoRole = .researcher; localReady = true; remoteReady = true; tracking = true; background = false
        pending = nil; selected = 0; capsuleSelected = false; message = "Осмотрите узел и сообщите символ оператору."
        if let state { evidence?.recordGame(mission: state.session, kind: .demoStarted, action: "synthetic-table", revision: state.revision, score: state.score) }
    }
    func host(room: RoomCaptureModel) {
        #if targetEnvironment(simulator)
        message = "На симуляторе доступна демонстрация без камеры."; return
        #else
        guard !room.scanning, !room.processing, let snapshot = room.snapshot, let geometry = ContactRoomDTO(snapshot: snapshot, captureID: room.observationCaptureID, capturedAt: room.observationCapturedAt),
              let session = room.contactSession, let generation = room.contactGeneration else {
            message = "Требуется новое сканирование комнаты в этой сессии."; return
        }
        if captureID != generation || mission == nil { mission = ContactMission(seed: .random(in: .min ... .max)); root = nil; arAnchor = nil }
        self.geometry = geometry; arSession = session; captureID = generation; received = nil; mode = .host
        localReady = false; remoteReady = false; tracking = false; background = false; pending = nil
        peer.host(); startClock(); message = "Назовите код оператору. Подтвердите только выбранного участника."
        #endif
    }
    func join() {
        mode = .guest; mission = nil; root = nil; arAnchor = nil; arSession = nil; captureID = nil; received = nil; geometry = nil
        localReady = false; remoteReady = false; background = false; pending = nil; peer.browse(); startClock()
    }
    func switchRole(_ role: ContactRole) { guard mode == .demo else { return }; demoRole = role; capsuleSelected = false; message = role == .researcher ? "Осмотр → сообщите символ → стабилизация." : "Руководство → питание узла → канал." }
    func replay() {
        guard mode == .host || mode == .demo else { return }
        mission = ContactMission(seed: mode == .demo ? 7 : .random(in: .min ... .max)); pending = nil; selected = 0; capsuleSelected = false
        root = mode == .demo ? ContactMath.identity : nil; arAnchor = nil; localReady = mode == .demo; remoteReady = mode == .demo
        if mode == .demo { demoRole = .researcher } else { welcome() }; message = "Новая миссия. Роли можно сменить через лобби."
    }
    func lobby() {
        pause(); peer.stop(); timer?.invalidate(); timer = nil; mode = .lobby; pending = nil
        arSession = nil; arAnchor = nil; captureID = nil; root = nil; geometry = nil; mission = nil; received = nil
    }
    func close() { pause(); timer?.invalidate(); timer = nil; peer.stop() }
    func captureChanged(_ generation: UUID?) { if mode == .host && generation != captureID { lobby(); message = "Скан изменился. Откройте новую локальную пару." } }
    func setBackground(_ value: Bool) { background = value; if value { pause() } }
    func pause() { if mode != .demo { localReady = false; beat() }; message = "Пауза. Для продолжения оба игрока нажимают «Продолжить»." }
    func resume() {
        guard mode != .demo, !background, peer.connected, state != nil, mode != .host || tracking,
              Date().timeIntervalSince(lastSeen) < 5 else { message = "Нужны связь, свежий сигнал партнёра и нормальное отслеживание у исследователя."; return }
        localReady = true; beat(); message = remoteReady ? "Можно продолжать." : "Ждём подтверждения партнёра."
    }
    func track(_ normal: Bool, _ text: String) {
        trackingText = text
        if tracking && !normal { pause() }; tracking = normal
    }
    func placed(_ anchor: ARAnchor) {
        let values = ContactMath.array(anchor.transform)
        guard canPlace, geometry?.contains(values) == true else { return }
        if let state { evidence?.recordGame(mission: state.session, kind: .placement, action: "virtual-capsule", revision: state.revision) }
        arAnchor = anchor; root = values; sendPlacement(); message = "Капсула закреплена. Коснитесь узла для осмотра."
    }
    func anchorUpdated(_ values: [Float]) {
        guard mode == .host, geometry?.contains(values) == true else { pause(); message = "Якорь вышел за границы скана. Начните новую миссию."; return }
        root = values; sendPlacement()
    }
    func selectAR(_ node: Int?) {
        guard canAct, role == .researcher else { return }
        if let node, (0..<3).contains(node) { selected = node; capsuleSelected = false; if state?.isInspected(node) == false { act(.inspect(node)) } }
        else { capsuleSelected = true; message = "Капсула выбрана. Извлечение доступно после разрешения оператора." }
    }
    func note(_ text: String) { message = text }
    func act(_ action: ContactAction) {
        guard canAct, action.role == role, let s = state else { return }
        let command = ContactCommand(session: s.session, revision: s.revision, role: role, action: action)
        if mode == .guest { pending = command; sentAt = Date(); send(ContactPacket(command: command)) }
        else { apply(command, authority: .researcher == role ? .researcher : .operator) }
    }
    private func apply(_ command: ContactCommand, authority: ContactRole) {
        guard var next = mission else { return }
        do {
            let mistakes = next.state.mistakes; try next.apply(command, authorizedRole: authority); mission = next
            evidence?.recordGame(mission: next.state.session, kind: .contactCommand, action: command.action.evidenceName, revision: next.state.revision, score: next.state.score)
            message = next.state.mistakes > mistakes ? "Неверный канал: −10 очков. Выберите другой; миссия продолжается." : "Действие принято."
            if mode == .host { var p = ContactPacket(kind: .state, state: next.state); p.state = next.state; p.commandID = command.id; send(p) }
        } catch {
            let reason = (error as? ContactError) ?? .prerequisite
            evidence?.recordGame(mission: next.state.session, kind: .rejectedCommand, action: command.action.evidenceName, revision: next.state.revision, score: next.state.score)
            message = reason == .stale ? "Устаревшая команда. Состояние обновлено; повторите действие." : "Действие отклонено: проверьте роль, осмотр, питание и канал."
            if mode == .host { var p = ContactPacket(kind: .rejected, state: next.state); p.state = next.state; p.commandID = command.id; p.error = reason; send(p) }
        }
    }
    private func connection(_ connected: Bool) {
        localReady = false; remoteReady = false; pending = nil; lastSeen = connected ? Date() : .distantPast
        if !connected, mode == .guest { geometry = nil; root = nil; received = nil }
        if connected, mode == .host { welcome() }
    }
    private func welcome() {
        guard mode == .host, let s = state, let geometry else { return }
        var p = ContactPacket(kind: .welcome, state: s); p.state = s; p.room = geometry; p.root = root; send(p)
    }
    private func sendPlacement() { guard let s = state, let root else { return }; var p = ContactPacket(kind: .placement, state: s); p.root = root; send(p) }
    private func beat() { guard let s = state else { return }; var p = ContactPacket(kind: .beat, state: s); p.ready = localReady && !background && (mode != .host || tracking); send(p) }
    private func send(_ p: ContactPacket) {
        guard mode != .demo, peer.connected else { return }
        guard let data = try? JSONEncoder().encode(p), data.count <= 256 * 1024 else { localReady = false; return }
        let accepted = peer.send(data)
        evidence?.recordTelemetry(.network(bytes: data.count, outbound: true, accepted: accepted))
        if !accepted { localReady = false; message = "Пакет не отправлен. Переподключитесь." }
    }
    private func receive(_ data: Data) {
        guard let p = try? ContactPacket.decode(data) else {
            if !data.isEmpty && data.count <= 262144 { evidence?.recordTelemetry(.network(bytes: data.count, outbound: false, accepted: false)) }
            pause(); peer.stop(); message = "Несовместимый или повреждённый пакет."; return
        }
        evidence?.recordTelemetry(.network(bytes: data.count, outbound: false, accepted: true))
        if mode == .guest, p.kind == .welcome, let s = p.state, let room = p.room {
            guard p.root.map({ room.contains($0) }) ?? true else { peer.stop(); return }
            if let captureID = room.captureID { evidence?.recordRoom(id: captureID, date: room.capturedAt, elements: room.surfaces.count, origin: .peerReport) }
            received = s; geometry = room; root = p.root; pending = nil; localReady = false; remoteReady = false; lastSeen = Date()
            message = "Получена оценка комнаты. Прочитайте руководство и нажмите «Продолжить»."; return
        }
        guard let s = state, p.session == s.session else { return }; lastSeen = Date()
        if p.kind == .beat {
            guard (mode == .host && p.revision <= s.revision) || (mode == .guest && p.revision == s.revision), let ready = p.ready else { return }
            if remoteReady && !ready { localReady = false; message = "Партнёр на паузе. Подтвердите продолжение после восстановления." }
            remoteReady = ready; return
        }
        if mode == .host { guard p.kind == .command, let command = p.command, canAct else { return }; apply(command, authority: .operator); return }
        guard mode == .guest else { return }
        if p.kind == .placement, p.revision == s.revision, let root = p.root, geometry?.contains(root) == true { self.root = root; return }
        guard p.kind == .state || p.kind == .rejected, let next = p.state, next.revision >= s.revision else { return }
        received = next
        evidence?.recordGame(mission: next.session, kind: .peerState, action: p.kind.rawValue, revision: next.revision, score: next.score)
        if pending?.id == p.commandID { pending = nil }
        if p.kind == .rejected { message = p.error == .stale ? "Устаревшая команда отклонена. Состояние синхронизировано; повторите действие." : "Команда отклонена. Состояние синхронизировано." }
        else { message = next.mistakes > s.mistakes ? "Неверный канал: −10 очков. Можно исправить." : "Состояние обновлено." }
    }
    private func startClock() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.peer.connected && Date().timeIntervalSince(self.lastSeen) >= 5 {
                self.localReady = false; self.remoteReady = false; self.message = "Нет сигнала партнёра более 5 секунд. Пауза; восстановите связь и подтвердите продолжение."
            }
            if self.pending != nil && Date().timeIntervalSince(self.sentAt) >= 5 { self.pending = nil; self.localReady = false; self.message = "Нет подтверждения команды. Переподключитесь для синхронизации." }
            self.beat()
        }
        timer = t; RunLoop.main.add(t, forMode: .common)
    }
    deinit { timer?.invalidate() }
}
