import UserNotifications

/// Decrypts OpenCody pushes (SPEC §6.4). Anything that fails keeps the relay's generic text.
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var content: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            return contentHandler(request.content)
        }
        self.content = content

        guard let envelope = PushEnvelope(userInfo: request.content.userInfo),
              let pairing = PushPairingStore.pairing(deviceId: envelope.deviceId),
              let message = try? envelope.open(key: pairing.key), message.isDeliverable()
        else { return contentHandler(content) }

        let decrypted = content.mutableCopy() as! UNMutableNotificationContent
        message.apply(to: decrypted, serverID: pairing.serverID)
        self.content = decrypted

        // The app may already have shown this alert from its live connection; keep the
        // push quiet and drop the older copy so the list holds one.
        let key = AlertKey.forPush(message)
        UNUserNotificationCenter.current().getDeliveredNotifications { delivered in
            let twins = delivered.filter { ($0.request.content.userInfo["dedupe"] as? String).map { AlertKey.isDuplicate($0, key) } ?? false }
            if !twins.isEmpty {
                decrypted.sound = nil
                decrypted.interruptionLevel = .passive
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: twins.map(\.request.identifier))
            }
            contentHandler(decrypted)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let content { contentHandler(content) }
    }
}
