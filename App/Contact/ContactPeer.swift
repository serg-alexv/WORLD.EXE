import Foundation
import Combine
import MultipeerConnectivity

final class ContactPeer: NSObject, ObservableObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    static let service = "world-contact"
    let identity = MCPeerID(displayName: "CONTACT-" + String(UUID().uuidString.prefix(6)))
    @Published private(set) var hosts: [MCPeerID] = []
    @Published private(set) var connected = false
    @Published private(set) var status = "Соединение не запущено"
    @Published private(set) var code = ""
    @Published private(set) var pendingName: String?
    var onData: ((Data) -> Void)?
    var onConnection: ((Bool) -> Void)?
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var chosen: MCPeerID?
    private var pending: (peer: MCPeerID, handler: (Bool, MCSession?) -> Void, until: Date)?
    private var timer: Timer?
    private var hosting = false
    private var packetWindow = Date.distantPast
    private var packetCount = 0
    private struct Invitation: Codable { let version: Int; let code: String }
    static func name(_ peer: MCPeerID) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-_"))
        let text = String(String.UnicodeScalarView(peer.displayName.unicodeScalars.filter { allowed.contains($0) })).prefix(32)
        return text.isEmpty ? "Участник" : String(text)
    }
    private func prepare() {
        stop(); let next = MCSession(peer: identity, securityIdentity: nil, encryptionPreference: .required)
        next.delegate = self; session = next
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let pending = self.pending, pending.until <= Date() else { return }; self.answer(false)
        }
        timer = t; RunLoop.main.add(t, forMode: .common)
    }
    func host() {
        dispatchPrecondition(condition: .onQueue(.main)); prepare(); hosting = true
        code = String(format: "%06d", Int.random(in: 0...999999))
        let a = MCNearbyServiceAdvertiser(peer: identity, discoveryInfo: nil, serviceType: Self.service)
        advertiser = a; a.delegate = self; a.startAdvertisingPeer(); status = "Ожидание выбранного оператора"
    }
    func browse() {
        dispatchPrecondition(condition: .onQueue(.main)); prepare(); hosting = false
        let b = MCNearbyServiceBrowser(peer: identity, serviceType: Self.service)
        browser = b; b.delegate = self; b.startBrowsingForPeers(); status = "Выберите ведущего и введите его код"
    }
    func invite(_ host: MCPeerID, code: String) {
        guard !hosting, !connected, chosen == nil, hosts.contains(host), Self.validCode(code), let browser, let session,
              let data = try? JSONEncoder().encode(Invitation(version: 1, code: code)), data.count <= 512 else { status = "Нужен шестизначный код и выбранный ведущий"; return }
        chosen = host; browser.invitePeer(host, to: session, withContext: data, timeout: 15); status = "Ждём явного согласия ведущего"
    }
    private static func validCode(_ code: String) -> Bool { code.utf8.count == 6 && code.utf8.allSatisfy { (48...57).contains($0) } }
    func answer(_ accept: Bool) {
        guard let p = pending else { return }; pending = nil; pendingName = nil
        let yes = accept && p.until > Date() && !connected && chosen == nil && session?.connectedPeers.isEmpty == true
        if yes { chosen = p.peer; status = "Подключение выбранного оператора" }
        p.handler(yes, yes ? session : nil)
    }
    @discardableResult func send(_ data: Data) -> Bool {
        guard connected, let chosen, let session, session.connectedPeers == [chosen], !data.isEmpty, data.count <= 256 * 1024 else { return false }
        do { try session.send(data, toPeers: [chosen], with: .reliable); return true }
        catch { status = "Отправка прервана"; stop(); return false }
    }
    func stop() {
        pending?.handler(false, nil); pending = nil; pendingName = nil; timer?.invalidate(); timer = nil
        advertiser?.stopAdvertisingPeer(); advertiser?.delegate = nil; advertiser = nil
        browser?.stopBrowsingForPeers(); browser?.delegate = nil; browser = nil
        session?.delegate = nil; session?.disconnect(); session = nil; chosen = nil
        connected = false; hosts = []; code = ""; status = "Соединение остановлено"; onConnection?(false)
    }
    deinit { timer?.invalidate(); advertiser?.stopAdvertisingPeer(); browser?.stopBrowsingForPeers(); pending?.handler(false,nil); session?.disconnect() }
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.advertiser === advertiser, self.hosting, !self.connected, self.chosen == nil, self.pending == nil,
                  let context, context.count <= 512, let invitation = try? JSONDecoder().decode(Invitation.self, from: context),
                  invitation.version == 1, Self.validCode(invitation.code), invitation.code == self.code else { invitationHandler(false,nil); return }
            self.pending = (peerID, invitationHandler, Date().addingTimeInterval(15)); self.pendingName = Self.name(peerID)
        }
    }
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async { [weak self] in guard let self, self.advertiser === advertiser else { return }; self.status = "Не удалось начать поиск. Проверьте доступ к локальной сети." }
    }
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        DispatchQueue.main.async { [weak self] in guard let self, self.browser === browser, self.hosts.count < 16, !self.hosts.contains(peerID) else { return }; self.hosts.append(peerID) }
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in guard let self, self.browser === browser else { return }; self.hosts.removeAll { $0 == peerID } }
    }
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async { [weak self] in guard let self, self.browser === browser else { return }; self.status = "Поиск недоступен. Проверьте доступ к локальной сети." }
    }
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.session === session else { return }
            guard self.chosen == peerID else { session.cancelConnectPeer(peerID); return }
            if state == .connected {
                guard session.connectedPeers.count == 1 else { self.stop(); return }
                self.connected = true; self.advertiser?.stopAdvertisingPeer(); self.browser?.stopBrowsingForPeers()
                self.status = "Подключён: \(Self.name(peerID))"; self.onConnection?(true)
            } else if state == .notConnected {
                self.connected = false; self.chosen = nil; self.status = "Связь потеряна. Переподключитесь явно."; self.onConnection?(false)
            }
        }
    }
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard !data.isEmpty, data.count <= 256 * 1024 else { session.cancelConnectPeer(peerID); return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.session === session, self.connected, self.chosen == peerID else { return }
            let now = Date()
            if now.timeIntervalSince(self.packetWindow) >= 1 { self.packetWindow = now; self.packetCount = 0 }
            self.packetCount += 1
            guard self.packetCount <= 30 else { self.stop(); return }
            self.onData?(data)
        }
    }
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) { stream.close() }
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) { progress.cancel() }
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
