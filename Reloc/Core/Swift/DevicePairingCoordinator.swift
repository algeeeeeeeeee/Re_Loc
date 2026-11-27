import Foundation
import RelocDeviceBridge
import SwiftUI
import UIKit

private final class DevicePairingContext {
    weak var owner: DevicePairingCoordinator?
    let session: UUID

    init(owner: DevicePairingCoordinator, session: UUID) {
        self.owner = owner
        self.session = session
    }
}

private let devicePairingEventCallback: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { pointer, context in
    guard let pointer, let context else { return }
    let text = String(cString: pointer)
    DispatchQueue.main.async {
        let box = Unmanaged<DevicePairingContext>.fromOpaque(context).takeUnretainedValue()
        let event = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
        box.owner?.receive(event, session: box.session)
        if ["completed", "failed", "cancelled"].contains(event["type"] as? String ?? "") {
            Unmanaged<DevicePairingContext>.fromOpaque(context).release()
        }
    }
}

/// On-device iOS 27 Remote Pairing responder with PiP floating live guide and background keep-alive.
@MainActor
final class DevicePairingCoordinator: NSObject, ObservableObject, NetServiceDelegate {
    static let shared = DevicePairingCoordinator()

    @Published private(set) var isRunning = false
    @Published private(set) var stepIndex = 0 // 0=idle, 1=broadcasting, 2=connected/pin, 3=completed
    @Published private(set) var status = "Device pairing has not started."
    @Published private(set) var pin: String?
    @Published private(set) var error: String?

    private var service: NetService?
    private var handle: UInt64 = 0
    private var session: UUID?
    private var cancelReason: String?
    private var background: UIBackgroundTaskIdentifier = .invalid
    private var onSaveRecord: ((Data, Data, String) throws -> Void)?
    private let pip = PairingPiPPresenter.shared
    private let keepAlive = BackgroundKeepAlive()

    func start(existingRequest: [String: String] = [:], onSaveRecord: @escaping (Data, Data, String) throws -> Void) {
        guard !isRunning else { return }
        #if targetEnvironment(simulator)
        error = "On-device pairing requires a physical iPhone running iOS 27 or later."
        status = error ?? ""
        return
        #else
        guard #available(iOS 27.0, *) else {
            error = "Import an existing pairing file on this iOS version. On-device pairing requires iOS 27."
            status = error ?? ""
            return
        }

        self.onSaveRecord = onSaveRecord
        let id = UUID()
        session = id
        isRunning = true
        stepIndex = 1
        pin = nil
        error = nil
        cancelReason = nil
        status = "Preparing the on-device pairing service…"

        let deadline = Date().addingTimeInterval(300)
        keepAlive.start(useSilentAudio: true)
        pip.startSession(deadline: deadline)

        do {
            let json = String(decoding: try JSONSerialization.data(withJSONObject: existingRequest), as: UTF8.self)
            background = UIApplication.shared.beginBackgroundTask(withName: "Reloc Device Pairing") { [weak self] in
                Task { @MainActor in
                    self?.cancel(reason: "The system ended the background pairing session. Return to Reloc and try again.")
                }
            }
            let context = Unmanaged.passRetained(DevicePairingContext(owner: self, session: id)).toOpaque()
            handle = json.withCString { rl_device_pairing_start($0, devicePairingEventCallback, context) }
            if handle == 0 {
                Unmanaged<DevicePairingContext>.fromOpaque(context).release()
                finish(error: "Unable to start the device pairing service.")
            }
        } catch {
            finish(error: error.localizedDescription)
        }
        #endif
    }

    func toggleFloatingGuide() {
        pip.togglePiP()
    }

    func cancel(reason: String? = nil) {
        cancelReason = reason
        service?.stop()
        service = nil
        if handle != 0 {
            rl_device_pairing_cancel(handle)
        } else {
            finish(error: reason)
        }
    }

    fileprivate func receive(_ event: [String: Any], session id: UUID) {
        guard session == id else { return }
        switch event["type"] as? String {
        case "ready":
            guard let identifier = event["identifier"] as? String,
                  let port = event["port"] as? Int,
                  (1...65535).contains(port),
                  let txt = event["txt"] as? [String: String] else {
                cancel(reason: "The pairing service returned invalid broadcast parameters.")
                return
            }
            let netService = NetService(
                domain: "local.",
                type: "_remotepairing-pairable-host._tcp.",
                name: identifier,
                port: Int32(port)
            )
            netService.delegate = self
            netService.setTXTRecord(NetService.data(fromTXTRecord: txt.mapValues { Data($0.utf8) }))
            self.service = netService
            netService.publish()
            stepIndex = 1
            status = "Go to Settings → Privacy & Security → Developer Mode, then select “Pair with Reloc” at the bottom."
            pip.update(
                step: 1,
                headline: "① Settings → Privacy & Security → Developer Mode",
                subtitle: "Scroll to the bottom and tap “Pair with Reloc”. The pairing code will appear here."
            )

        case "connected":
            stepIndex = 2
            status = "System connected. Generating the pairing code…"
            pip.update(
                step: 2,
                headline: "② System Connected",
                subtitle: "Negotiating a secure channel and generating the 6-digit pairing code…"
            )

        case "pin":
            guard let pin = event["pin"] as? String else { return }
            self.pin = pin
            stepIndex = 2
            status = "Enter the following 6-digit pairing code in System Settings."
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            pip.update(
                step: 2,
                headline: "Enter Pairing Code",
                subtitle: "Enter the 6-digit pairing code in the System Settings prompt.",
                pin: pin
            )

        case "completed":
            guard let encoded = event["record"] as? String,
                  let record = Data(base64Encoded: encoded),
                  let irk = (event["host_irk"] as? String).flatMap({ Data(base64Encoded: $0) }),
                  irk.count == 16,
                  let save = onSaveRecord else {
                finish(error: "The system did not return a complete pairing record.")
                return
            }
            let udid = event["udid"] as? String ?? ""
            do {
                try save(record, irk, udid)
                stepIndex = 3
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                finish(error: nil, succeeded: true)
                status = "Pairing record saved automatically."
            } catch {
                finish(error: error.localizedDescription)
            }

        case "failed":
            finish(error: event["error"] as? String ?? "Device pairing was not completed.")

        case "cancelled":
            finish(error: cancelReason)

        default:
            break
        }
    }

    private func finish(error: String?, succeeded: Bool = false) {
        let englishError = error.map(RelocEnglish.translate)
        self.error = englishError
        status = englishError ?? (succeeded ? "Pairing record saved automatically." : "Pairing ended.")
        isRunning = false
        stepIndex = succeeded ? 3 : 0
        pin = nil
        handle = 0
        session = nil
        onSaveRecord = nil
        service?.delegate = nil
        service?.stop()
        service = nil
        if background != .invalid {
            UIApplication.shared.endBackgroundTask(background)
            background = .invalid
        }
        keepAlive.stop(deactivateAudioSession: false)
        let finalMessage = englishError ?? (succeeded ? "Pairing complete. Return to Reloc to start location." : "Pairing ended.")
        pip.finish(succeeded: succeeded, message: finalMessage)
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        guard sender === service else { return }
        let code = errorDict[NetService.errorCode]?.intValue ?? 0
        cancel(reason: "Unable to publish the pairing service (error code \(code)), then allow Reloc to access the local network in Settings → Privacy & Security → Local Network and try again.")
    }
}
