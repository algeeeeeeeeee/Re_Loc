import Foundation
import RelocDeviceBridge

public struct ProtocolEvent: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let name: String
    public let detail: String
    public let isError: Bool

    public init(timestamp: Date = Date(), name: String, detail: String, isError: Bool = false) {
        self.timestamp = timestamp
        self.name = name
        self.detail = detail
        self.isError = isError
    }
}

public struct SessionSnapshot: Equatable, Sendable {
    public var isRunning: Bool = false
    public var mode: SessionMode = .send
    public var lockdownConnected: Bool = false
    public var linkReady: Bool = false
    public var identified: Bool = false
    public var authenticated: Bool = false
    public var activeSentences: [UInt16] = []
    public var packetsAcknowledged: Int = 0
    public var lastError: String? = nil

    public init() {}
}

public enum SessionMode: String, Sendable {
    case probe
    case send
}

public struct SessionConfiguration: Sendable {
    public var host: String
    public var remotePort: UInt16
    public var lockdownPort: UInt16
    public var serviceName: String
    public var mode: SessionMode
    public var intervalSeconds: TimeInterval
    /// 0 means run continuously until stopped manually.
    public var durationSeconds: TimeInterval

    public init(
        host: String = "10.7.0.1",
        remotePort: UInt16 = 49152,
        lockdownPort: UInt16 = 62078,
        serviceName: String = "com.apple.carkit.service",
        mode: SessionMode = .send,
        intervalSeconds: TimeInterval = 1.0,
        durationSeconds: TimeInterval = 0
    ) {
        self.host = host
        self.remotePort = remotePort
        self.lockdownPort = lockdownPort
        self.serviceName = serviceName
        self.mode = mode
        self.intervalSeconds = max(1.0, intervalSeconds)
        self.durationSeconds = max(0, durationSeconds)
    }
}

public struct ConnectionCheckResult: Sendable {
    public let udid: String
    public let port: UInt16
    public let carkitService: String?
}

public enum ConnectionCheckError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

/// Thread-safe holder for live target coordinates while a session is streaming.
public final class LiveLocationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: TargetLocation

    public init(_ initial: TargetLocation) {
        self.current = initial
    }

    public func get() -> TargetLocation {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func set(_ location: TargetLocation) {
        lock.lock()
        current = location
        lock.unlock()
    }
}

/// Manages an iAP2 accessory-location session over either:
/// 1) Remote Pairing + RSD tunnel on 10.7.0.1:<discoveredPort> (iOS 17–27, Retools-style), OR
/// 2) Traditional Lockdown pairing on 10.7.0.1:62078, OR
/// 3) An injected RLTLSSocket (for unit tests).
public final class AccessoryLocationSession {
    public typealias EventCallback = @Sendable (ProtocolEvent) -> Void
    public typealias SnapshotCallback = @Sendable (SessionSnapshot) -> Void

    public let id: UUID
    private let queue = DispatchQueue(label: "com.reloc.session", qos: .userInitiated)
    private let stateLock = NSLock()
    private var cancelled = false
    private var runGeneration: UInt64 = 0
    private var activeLockdown: RLLockdownClient?
    private var activeTunnelHandle: UInt64 = 0
    private var activeLink: IAP2Link?
    private var activeSocket: RLTLSSocket?
    private var coreLocationConfirmed = false
    private var fastBurstUntil: CFAbsoluteTime = 0
    private var pendingKalmanReset = false
    private var burstMotionPacketsRemaining = 0
    private var pendingReconnectReason: String?
    private var fallbackRealLocation: TargetLocation?

    public let locationBox: LiveLocationBox
    private let onEvent: EventCallback
    private let onSnapshot: SnapshotCallback
    private let onAuthenticated: (@Sendable () -> Void)?
    private let onLocationRequested: (@Sendable () -> Void)?
    private let onLocationStopped: (@Sendable () -> Void)?
    private let onSubscriptionRestarted: (@Sendable () -> Void)?
    private let onDiscoveredPort: (@Sendable (UInt16) -> Void)?

    public init(
        id: UUID = UUID(),
        initialLocation: TargetLocation,
        onEvent: @escaping EventCallback,
        onSnapshot: @escaping SnapshotCallback,
        onAuthenticated: (@Sendable () -> Void)? = nil,
        onLocationRequested: (@Sendable () -> Void)? = nil,
        onLocationStopped: (@Sendable () -> Void)? = nil,
        onSubscriptionRestarted: (@Sendable () -> Void)? = nil,
        onDiscoveredPort: (@Sendable (UInt16) -> Void)? = nil
    ) {
        self.id = id
        self.locationBox = LiveLocationBox(initialLocation)
        self.onEvent = onEvent
        self.onSnapshot = onSnapshot
        self.onAuthenticated = onAuthenticated
        self.onLocationRequested = onLocationRequested
        self.onLocationStopped = onLocationStopped
        self.onSubscriptionRestarted = onSubscriptionRestarted
        self.onDiscoveredPort = onDiscoveredPort
    }

    /// Updates whether iOS CoreLocation has confirmed `isProducedByAccessory == true` for the target.
    public func markCoreLocationConfirmed(_ confirmed: Bool) {
        stateLock.lock()
        coreLocationConfirmed = confirmed
        stateLock.unlock()
    }

    /// Stores the most recent known internal real location so stop-time accuracy degradation
    /// can gently hand control back to `locationd` indoors without user intervention.
    public func setFallbackRealLocation(_ location: TargetLocation?) {
        stateLock.lock()
        fallbackRealLocation = location
        stateLock.unlock()
    }

    /// Requests a temporary high-cadence NMEA acquisition burst (5 Hz)
    /// so `locationd` locks onto the external accessory GPS as rapidly as possible.
    public func triggerFastBurst(seconds: TimeInterval = 15.0) {
        stateLock.lock()
        fastBurstUntil = max(fastBurstUntil, CFAbsoluteTimeGetCurrent() + seconds)
        stateLock.unlock()
    }

    /// Wakes the streaming loop immediately on coordinate change, optionally emitting a brief
    /// void-fix pulse and micro-motion burst to reset `locationd`'s Kalman filter.
    public func notifyLocationUpdated(resetKalman: Bool = true, burstSeconds: TimeInterval = 10.0) {
        stateLock.lock()
        coreLocationConfirmed = false
        if resetKalman {
            pendingKalmanReset = true
            burstMotionPacketsRemaining = max(burstMotionPacketsRemaining, 2)
        }
        fastBurstUntil = max(fastBurstUntil, CFAbsoluteTimeGetCurrent() + burstSeconds)
        let sock = activeSocket
        stateLock.unlock()
        sock?.nudge()
    }

    /// Requests a clean iAP2 link reset & immediate reconnect (e.g. if `0xFFFA` or lock stalls).
    public func requestLinkReconnect(reason: String) {
        stateLock.lock()
        pendingReconnectReason = reason
        let sock = activeSocket
        stateLock.unlock()
        sock?.nudge()
    }

    private func consumeReconnectReason() -> String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        let reason = pendingReconnectReason
        pendingReconnectReason = nil
        return reason
    }

    private func isFastBurstActive(now: CFAbsoluteTime) -> Bool {
        stateLock.lock()
        let confirmed = coreLocationConfirmed
        let burstDeadline = fastBurstUntil
        stateLock.unlock()
        return !confirmed && now < burstDeadline
    }

    /// Verifies device loopback connectivity and reads device identity (modeled on Reukix/retools).
    public static func verifyConnection(
        host: String,
        remotePort: UInt16,
        lockdownPort: UInt16,
        pairing: SavedPairing
    ) async throws -> ConnectionCheckResult {
        switch pairing {
        case .remotePairing(let data, _):
            let discovered = await RemotePairingDiscovery.discoverPort(record: data)
            let port = discovered ?? remotePort
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let ptr = data.withUnsafeBytes { bytes in
                        host.withCString { ip in
                            rl_device_pairing_verify(
                                bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                                bytes.count,
                                ip,
                                port
                            )
                        }
                    }
                    guard let ptr else {
                        continuation.resume(throwing: ConnectionCheckError.message("Device connection verification returned no result."))
                        return
                    }
                    defer { rl_string_free(ptr) }
                    let jsonText = String(cString: ptr)
                    let obj = (try? JSONSerialization.jsonObject(with: Data(jsonText.utf8))) as? [String: Any] ?? [:]
                    if obj["ok"] as? Bool == true {
                        let udid = obj["udid"] as? String ?? ""
                        let carkit = obj["carkit_service"] as? String
                        continuation.resume(returning: ConnectionCheckResult(udid: udid, port: port, carkitService: carkit))
                    } else {
                        let err = obj["error"] as? String ?? "Device connection verification failed."
                        continuation.resume(throwing: ConnectionCheckError.message(err))
                    }
                }
            }

        case .lockdown(let record):
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let client = try RLLockdownClient(
                            connectedToHost: host,
                            port: lockdownPort,
                            pairingRecord: record,
                            timeout: 10.0,
                            logHandler: nil
                        )
                        let udid = record.udid ?? record.hostID
                        client.close()
                        continuation.resume(returning: ConnectionCheckResult(udid: udid, port: lockdownPort, carkitService: "com.apple.carkit.service"))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    /// Starts a session using the saved pairing (Remote Pairing or Lockdown).
    public func start(
        configuration: SessionConfiguration,
        pairing: SavedPairing,
        discoveredRemotePort: UInt16? = nil,
        mfiSigner: RLMFiSigner
    ) {
        resetCancellation()
        switch pairing {
        case .remotePairing(let data, _):
            Task { [weak self] in
                guard let self else { return }
                let port: UInt16
                let usedCachedPort: Bool
                if let discoveredRemotePort {
                    port = discoveredRemotePort
                    usedCachedPort = true
                } else if let discovered = await RemotePairingDiscovery.discoverPort(record: data) {
                    port = discovered
                    usedCachedPort = false
                    self.onDiscoveredPort?(discovered)
                } else {
                    port = configuration.remotePort
                    usedCachedPort = false
                }
                self.queue.async {
                    self.runOverRemotePairing(
                        configuration: configuration,
                        recordData: data,
                        port: port,
                        usedCachedPort: usedCachedPort,
                        mfiSigner: mfiSigner
                    )
                }
            }

        case .lockdown(let record):
            queue.async { [weak self] in
                self?.runOverLockdown(
                    configuration: configuration,
                    pairingRecord: record,
                    mfiSigner: mfiSigner
                )
            }
        }
    }

    /// Starts directly over an already-connected socket (used for loopback unit testing).
    public func start(
        socket: RLTLSSocket,
        configuration: SessionConfiguration,
        mfiSigner: RLMFiSigner,
        completion: (() -> Void)? = nil
    ) {
        resetCancellation()
        queue.async { [weak self] in
            defer { completion?() }
            self?.runOnSocket(
                socket: socket,
                configuration: configuration,
                mfiSigner: mfiSigner,
                initialSnapshot: SessionSnapshot()
            )
        }
    }

    public func stop() {
        stateLock.lock()
        cancelled = true
        let stopGeneration = runGeneration
        let hasActiveLink = (activeLink != nil)
        let sock = activeSocket
        stateLock.unlock()

        sock?.nudge()

        if !hasActiveLink {
            forceCloseActiveTransports()
            return
        }

        // Give `runOnSocket` up to 0.9s to flush degraded/void NMEA and an iAP2 RST control packet
        // so iOS immediately detaches the external GPS accessory, then force-close as a failsafe.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let sameRunAndCancelled = (self.runGeneration == stopGeneration && self.cancelled)
            self.stateLock.unlock()
            if sameRunAndCancelled {
                self.forceCloseActiveTransports()
            }
        }
    }

    private func forceCloseActiveTransports() {
        stateLock.lock()
        let link = activeLink
        let lockdown = activeLockdown
        let tunnelHandle = activeTunnelHandle
        activeTunnelHandle = 0
        stateLock.unlock()

        link?.close()
        lockdown?.cancel()
        if tunnelHandle != 0 {
            rl_rppairing_close_service(tunnelHandle)
        }
    }

    private func resetCancellation() {
        stateLock.lock()
        cancelled = false
        pendingKalmanReset = false
        burstMotionPacketsRemaining = 0
        pendingReconnectReason = nil
        runGeneration &+= 1
        stateLock.unlock()
    }

    private func isCancelled() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cancelled
    }

    private func emitEvent(_ name: String, details: [String: Any] = [:], isError: Bool = false) {
        var payload = details
        payload["event"] = name
        let detailText: String
        if let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let str = String(data: jsonData, encoding: .utf8) {
            detailText = str
        } else {
            detailText = "{\"event\":\"\(name)\"}"
        }
        onEvent(ProtocolEvent(name: name, detail: detailText, isError: isError))
    }

    private enum SocketRunOutcome {
        case completed(packetCount: Int)
        case reconnectRequested(String, packetCount: Int)
        case recoverableError(String, didSendPackets: Bool, packetCount: Int)
        case fatalError(String)
    }

    private func sleepCancellable(_ seconds: TimeInterval, deadline: CFAbsoluteTime?) {
        let end = CFAbsoluteTimeGetCurrent() + seconds
        while !isCancelled() {
            let now = CFAbsoluteTimeGetCurrent()
            if now >= end { return }
            if let deadline, now >= deadline { return }
            let slice = min(0.1, end - now)
            Thread.sleep(forTimeInterval: max(0.01, slice))
        }
    }

    private func discoverRemotePortSync(recordData: Data) -> UInt16? {
        let sem = DispatchSemaphore(value: 0)
        final class PortBox: @unchecked Sendable { var value: UInt16? }
        let box = PortBox()
        Task { @MainActor in
            box.value = await RemotePairingDiscovery.discoverPort(record: recordData)
            sem.signal()
        }
        let end = CFAbsoluteTimeGetCurrent() + 6.0
        while !isCancelled() && CFAbsoluteTimeGetCurrent() < end {
            if sem.wait(timeout: .now() + 0.15) == .success {
                return box.value
            }
        }
        return nil
    }

    private static func isFatalPairingError(_ message: String) -> Bool {
        message.contains("配对记录校验未通过")
            || message.contains("公私钥不匹配")
            || message.contains("配对身份格式无效")
            || message.contains("配对数据为空")
    }

    private func runOverRemotePairing(
        configuration: SessionConfiguration,
        recordData: Data,
        port initialPort: UInt16,
        usedCachedPort: Bool,
        mfiSigner: RLMFiSigner
    ) {
        let overallDeadline: CFAbsoluteTime? = configuration.durationSeconds > 0
            ? CFAbsoluteTimeGetCurrent() + configuration.durationSeconds
            : nil

        var snapshot = SessionSnapshot()
        snapshot.isRunning = true
        snapshot.mode = configuration.mode
        onSnapshot(snapshot)

        var currentPort = initialPort
        var cachedPortPendingRefresh = usedCachedPort
        var reconnectAttempt = 0
        var cumulativePackets = 0

        while !isCancelled() {
            if let overallDeadline, CFAbsoluteTimeGetCurrent() >= overallDeadline {
                break
            }

            if reconnectAttempt > 0 {
                if let freshPort = discoverRemotePortSync(recordData: recordData) {
                    currentPort = freshPort
                    cachedPortPendingRefresh = false
                    onDiscoveredPort?(freshPort)
                }
                if isCancelled() { break }
            }

            emitEvent("rppairing_connecting", details: [
                "host": configuration.host,
                "port": Int(currentPort),
                "attempt": reconnectAttempt + 1,
            ])

            let ptr = recordData.withUnsafeBytes { bytes in
                configuration.host.withCString { ip in
                    configuration.serviceName.withCString { svc in
                        rl_rppairing_open_service(
                            bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                            bytes.count,
                            ip,
                            currentPort,
                            svc
                        )
                    }
                }
            }

            guard let ptr else {
                let err = "Unable to establish the device service channel through Remote Pairing."
                if configuration.mode != .send || isCancelled() {
                    if !isCancelled() {
                        snapshot.lastError = err
                        emitEvent("error", details: ["detail": err], isError: true)
                    }
                    break
                }
                reconnectAttempt += 1
                let delay = min(5.0, pow(1.5, Double(reconnectAttempt - 1)))
                snapshot.lockdownConnected = false
                snapshot.linkReady = false
                snapshot.identified = false
                snapshot.authenticated = false
                snapshot.activeSentences = []
                snapshot.packetsAcknowledged = cumulativePackets
                snapshot.lastError = "Channel establishment failed, \(String(format: "%.1f", delay)) sec until automatic reconnection (attempt \(reconnectAttempt))"
                onSnapshot(snapshot)
                emitEvent("reconnecting", details: ["attempt": reconnectAttempt, "delay_s": delay, "reason": err], isError: true)
                sleepCancellable(delay, deadline: overallDeadline)
                continue
            }

            let jsonText = String(cString: ptr)
            rl_string_free(ptr)

            let obj = (try? JSONSerialization.jsonObject(with: Data(jsonText.utf8))) as? [String: Any] ?? [:]
            guard obj["ok"] as? Bool == true,
                  let fdNum = obj["fd"] as? Int,
                  let handleNum = obj["handle"] as? UInt64 else {
                let err = obj["error"] as? String ?? "Failed to open the Remote Pairing service."
                if configuration.mode != .send || isCancelled() || Self.isFatalPairingError(err) {
                    if !isCancelled() {
                        snapshot.lastError = err
                        emitEvent("error", details: ["detail": err], isError: true)
                    }
                    break
                }
                reconnectAttempt += 1
                let delay = cachedPortPendingRefresh ? 0.25 : min(5.0, pow(1.5, Double(reconnectAttempt - 1)))
                cachedPortPendingRefresh = false
                snapshot.lockdownConnected = false
                snapshot.linkReady = false
                snapshot.identified = false
                snapshot.authenticated = false
                snapshot.activeSentences = []
                snapshot.packetsAcknowledged = cumulativePackets
                snapshot.lastError = "Tunnel interrupted, \(String(format: "%.1f", delay)) sec until automatic reconnection (attempt \(reconnectAttempt))"
                onSnapshot(snapshot)
                emitEvent("reconnecting", details: ["attempt": reconnectAttempt, "delay_s": delay, "reason": err], isError: true)
                sleepCancellable(delay, deadline: overallDeadline)
                continue
            }

            cachedPortPendingRefresh = false

            let usedService = obj["service"] as? String ?? configuration.serviceName
            let usedPort = obj["port"] as? Int ?? 0

            stateLock.lock()
            activeTunnelHandle = handleNum
            stateLock.unlock()

            func closeCurrentTunnel() {
                stateLock.lock()
                let h = activeTunnelHandle
                activeTunnelHandle = 0
                stateLock.unlock()
                if h != 0 {
                    rl_rppairing_close_service(h)
                }
            }

            if isCancelled() {
                Darwin.close(Int32(fdNum))
                closeCurrentTunnel()
                break
            }

            emitEvent("rppairing_service_connected", details: [
                "service": usedService,
                "service_port": usedPort,
                "rp_port": Int(currentPort),
            ])

            let serviceSocket = RLTLSSocket(fileDescriptor: Int32(fdNum))
            var attemptSnapshot = SessionSnapshot()
            attemptSnapshot.isRunning = true
            attemptSnapshot.mode = configuration.mode
            attemptSnapshot.lockdownConnected = true
            attemptSnapshot.packetsAcknowledged = cumulativePackets
            onSnapshot(attemptSnapshot)

            let outcome = runOnSocket(
                socket: serviceSocket,
                configuration: configuration,
                mfiSigner: mfiSigner,
                initialSnapshot: attemptSnapshot,
                overallDeadline: overallDeadline,
                keepRunningOnExit: configuration.mode == .send
            )
            closeCurrentTunnel()

            switch outcome {
            case .completed(let packetCount):
                cumulativePackets = packetCount
                snapshot = attemptSnapshot
                snapshot.packetsAcknowledged = cumulativePackets
                snapshot.isRunning = false
                onSnapshot(snapshot)
                return

            case .fatalError(let err):
                snapshot.lastError = err
                snapshot.isRunning = false
                onSnapshot(snapshot)
                return

            case .reconnectRequested(let reason, let packetCount):
                cumulativePackets = packetCount
                if isCancelled() { break }
                if let overallDeadline, CFAbsoluteTimeGetCurrent() >= overallDeadline {
                    break
                }
                reconnectAttempt = 0
                snapshot = SessionSnapshot()
                snapshot.isRunning = true
                snapshot.mode = configuration.mode
                snapshot.packetsAcknowledged = cumulativePackets
                onSnapshot(snapshot)
                emitEvent("reconnecting", details: ["attempt": 1, "delay_s": 0.35, "reason": reason])
                sleepCancellable(0.35, deadline: overallDeadline)

            case .recoverableError(let err, let didSend, let packetCount):
                cumulativePackets = packetCount
                if configuration.mode != .send || isCancelled() {
                    snapshot.lastError = isCancelled() ? nil : err
                    break
                }
                if let overallDeadline, CFAbsoluteTimeGetCurrent() >= overallDeadline {
                    break
                }
                if didSend {
                    reconnectAttempt = 0
                }
                reconnectAttempt += 1
                let delay = min(5.0, pow(1.5, Double(reconnectAttempt - 1)))
                snapshot = SessionSnapshot()
                snapshot.isRunning = true
                snapshot.mode = configuration.mode
                snapshot.packetsAcknowledged = cumulativePackets
                snapshot.lastError = "Connection lost, \(String(format: "%.1f", delay)) sec until automatic reconnection (attempt \(reconnectAttempt))"
                onSnapshot(snapshot)
                emitEvent("reconnecting", details: ["attempt": reconnectAttempt, "delay_s": delay, "reason": err], isError: true)
                sleepCancellable(delay, deadline: overallDeadline)
            }
        }

        snapshot.packetsAcknowledged = cumulativePackets
        snapshot.isRunning = false
        onSnapshot(snapshot)
    }

    private func runOverLockdown(
        configuration: SessionConfiguration,
        pairingRecord: RLPairingRecord,
        mfiSigner: RLMFiSigner
    ) {
        let overallDeadline: CFAbsoluteTime? = configuration.durationSeconds > 0
            ? CFAbsoluteTimeGetCurrent() + configuration.durationSeconds
            : nil

        var snapshot = SessionSnapshot()
        snapshot.isRunning = true
        snapshot.mode = configuration.mode
        onSnapshot(snapshot)

        var reconnectAttempt = 0
        var cumulativePackets = 0

        while !isCancelled() {
            if let overallDeadline, CFAbsoluteTimeGetCurrent() >= overallDeadline {
                break
            }

            var lockdown: RLLockdownClient?
            func closeLockdown() {
                lockdown?.close()
                lockdown = nil
                stateLock.lock()
                activeLockdown = nil
                stateLock.unlock()
            }

            do {
                let client = try RLLockdownClient(
                    connectedToHost: configuration.host,
                    port: configuration.lockdownPort,
                    pairingRecord: pairingRecord,
                    timeout: 10.0,
                    logHandler: { [weak self] event, details in
                        self?.emitEvent(event, details: details)
                    }
                )
                lockdown = client
                stateLock.lock()
                activeLockdown = client
                stateLock.unlock()

                if isCancelled() {
                    closeLockdown()
                    break
                }

                let serviceSocket = try client.startService(configuration.serviceName, timeout: 10.0)
                var attemptSnapshot = SessionSnapshot()
                attemptSnapshot.isRunning = true
                attemptSnapshot.mode = configuration.mode
                attemptSnapshot.lockdownConnected = true
                attemptSnapshot.packetsAcknowledged = cumulativePackets
                onSnapshot(attemptSnapshot)

                let outcome = runOnSocket(
                    socket: serviceSocket,
                    configuration: configuration,
                    mfiSigner: mfiSigner,
                    initialSnapshot: attemptSnapshot,
                    overallDeadline: overallDeadline,
                    keepRunningOnExit: configuration.mode == .send
                )
                closeLockdown()

                switch outcome {
                case .completed(let packetCount):
                    cumulativePackets = packetCount
                    snapshot.packetsAcknowledged = cumulativePackets
                    snapshot.isRunning = false
                    onSnapshot(snapshot)
                    return

                case .fatalError(let err):
                    snapshot.lastError = err
                    snapshot.isRunning = false
                    onSnapshot(snapshot)
                    return

                case .reconnectRequested(let reason, let packetCount):
                    cumulativePackets = packetCount
                    if isCancelled() { break }
                    if let overallDeadline, CFAbsoluteTimeGetCurrent() >= overallDeadline {
                        break
                    }
                    reconnectAttempt = 0
                    snapshot = SessionSnapshot()
                    snapshot.isRunning = true
                    snapshot.mode = configuration.mode
                    snapshot.packetsAcknowledged = cumulativePackets
                    onSnapshot(snapshot)
                    emitEvent("reconnecting", details: ["attempt": 1, "delay_s": 0.35, "reason": reason])
                    sleepCancellable(0.35, deadline: overallDeadline)
                    continue

                case .recoverableError(let err, let didSend, let packetCount):
                    cumulativePackets = packetCount
                    if configuration.mode != .send || isCancelled() {
                        snapshot.lastError = isCancelled() ? nil : err
                        break
                    }
                    if let overallDeadline, CFAbsoluteTimeGetCurrent() >= overallDeadline {
                        break
                    }
                    if didSend {
                        reconnectAttempt = 0
                    }
                    reconnectAttempt += 1
                    let delay = min(5.0, pow(1.5, Double(reconnectAttempt - 1)))
                    snapshot = SessionSnapshot()
                    snapshot.isRunning = true
                    snapshot.mode = configuration.mode
                    snapshot.packetsAcknowledged = cumulativePackets
                    snapshot.lastError = "Connection lost, \(String(format: "%.1f", delay)) sec until automatic reconnection (attempt \(reconnectAttempt))"
                    onSnapshot(snapshot)
                    emitEvent("reconnecting", details: ["attempt": reconnectAttempt, "delay_s": delay, "reason": err], isError: true)
                    sleepCancellable(delay, deadline: overallDeadline)
                    continue
                }
                break
            } catch {
                closeLockdown()
                if isCancelled() {
                    emitEvent("stopped", details: ["reason": "user_cancelled"])
                    break
                }
                let message = error.localizedDescription
                if configuration.mode != .send {
                    snapshot.lastError = message
                    emitEvent("error", details: ["detail": message], isError: true)
                    break
                }
                reconnectAttempt += 1
                let delay = min(5.0, pow(1.5, Double(reconnectAttempt - 1)))
                snapshot = SessionSnapshot()
                snapshot.isRunning = true
                snapshot.mode = configuration.mode
                snapshot.packetsAcknowledged = cumulativePackets
                snapshot.lastError = "Lockdown interrupted, \(String(format: "%.1f", delay)) sec until automatic reconnection (attempt \(reconnectAttempt))"
                onSnapshot(snapshot)
                emitEvent("reconnecting", details: ["attempt": reconnectAttempt, "delay_s": delay, "reason": message], isError: true)
                sleepCancellable(delay, deadline: overallDeadline)
            }
        }

        snapshot.packetsAcknowledged = cumulativePackets
        snapshot.isRunning = false
        onSnapshot(snapshot)
    }

    @discardableResult
    private func runOnSocket(
        socket: RLTLSSocket,
        configuration: SessionConfiguration,
        mfiSigner: RLMFiSigner,
        initialSnapshot: SessionSnapshot,
        overallDeadline: CFAbsoluteTime? = nil,
        keepRunningOnExit: Bool = false
    ) -> SocketRunOutcome {
        var snapshot = initialSnapshot
        snapshot.isRunning = true
        snapshot.mode = configuration.mode
        let initialPacketCount = snapshot.packetsAcknowledged
        onSnapshot(snapshot)

        let link = IAP2Link(socket: socket) { [weak self] event, details in
            self?.emitEvent(event, details: details)
        }

        stateLock.lock()
        activeLink = link
        activeSocket = socket
        stateLock.unlock()

        defer {
            link.close()
            stateLock.lock()
            activeLink = nil
            activeSocket = nil
            stateLock.unlock()
        }

        do {
            try link.handshake()
            snapshot.linkReady = true
            onSnapshot(snapshot)

            let startTime = CFAbsoluteTimeGetCurrent()
            let deadline: CFAbsoluteTime? = overallDeadline ?? (
                configuration.durationSeconds > 0
                    ? startTime + configuration.durationSeconds
                    : nil
            )

            var activeSentences = Set<UInt16>()
            var lastSent: [UInt16: CFAbsoluteTime] = [:]
            var minIntervals: [UInt16: TimeInterval] = [:]
            var sawLocationStopped = false

            while !isCancelled() {
                if let reconnectReason = consumeReconnectReason() {
                    if snapshot.authenticated {
                        if !activeSentences.isEmpty {
                            let voidMap = NMEAGenerator.voidLocationSentences()
                            let voidOutgoing = activeSentences.sorted().compactMap { voidMap[$0] }
                            if !voidOutgoing.isEmpty, let voidMsg = try? NMEAGenerator.locationMessage(sentences: voidOutgoing) {
                                link.sendBestEffort(voidMsg, timeout: 0.2)
                            }
                        }
                        link.sendReset()
                        emitEvent("iap2_link_reset_sent", details: ["reason": reconnectReason])
                        Thread.sleep(forTimeInterval: 0.05)
                    }
                    return .reconnectRequested(reconnectReason, packetCount: snapshot.packetsAcknowledged)
                }

                let now = CFAbsoluteTimeGetCurrent()
                if let deadline, now >= deadline {
                    break
                }

                var pollSlice: TimeInterval = 0.15
                if configuration.mode == .send,
                   snapshot.identified,
                   snapshot.authenticated,
                   !activeSentences.isEmpty {
                    let burstActive = isFastBurstActive(now: now)
                    stateLock.lock()
                    let hasKalmanReset = pendingKalmanReset
                    stateLock.unlock()
                    if hasKalmanReset {
                        pollSlice = 0.01
                    } else {
                        let nextDue = activeSentences.map { id -> CFAbsoluteTime in
                            let last = lastSent[id] ?? -.infinity
                            let required = burstActive ? 0.2 : max(configuration.intervalSeconds, minIntervals[id] ?? 0.25)
                            return last.isFinite ? (last + required) : now
                        }.min() ?? (now + 0.15)
                        pollSlice = min(pollSlice, max(0.01, nextDue - now))
                    }
                }
                if let deadline {
                    pollSlice = min(pollSlice, max(0.01, deadline - now))
                }

                if let message = try link.receive(timeout: pollSlice) {
                    let fields = try RLIAP2Parameter.parseParameters(from: message.body)
                    emitEvent("message", details: [
                        "identifier": String(format: "0x%04x", message.identifier),
                        "parameters": fields.map { ["id": Int($0.identifier), "bytes": $0.data.count] },
                    ])

                    switch message.identifier {
                    case 0x1D00: // StartIdentification
                        let idMsg = try NMEAGenerator.identificationMessage()
                        try link.send(idMsg)

                    case 0x1D02: // IdentificationAccepted
                        snapshot.identified = true
                        onSnapshot(snapshot)
                        emitEvent("identification_accepted")

                    case 0x1D03: // IdentificationRejected
                        let rejectedIds = fields.map { Int($0.identifier) }
                        throw IAP2LinkError.protocolError("Identification rejected: \(rejectedIds)")

                    case 0xAA00: // RequestAuthenticationCertificate
                        let certBody = RLIAP2Parameter.encode(0, data: mfiSigner.certificateContainerData)
                        try link.send(RLIAP2Message(identifier: 0xAA01, body: certBody))

                    case 0xAA02: // RequestAuthenticationChallengeResponse
                        let challenges = fields.filter { $0.identifier == 0 }.map(\.data)
                        guard challenges.count == 1 else {
                            throw IAP2LinkError.protocolError("Invalid authentication challenge parameters")
                        }
                        let signature = try mfiSigner.signChallenge(challenges[0])
                        let sigBody = RLIAP2Parameter.encode(0, data: signature)
                        try link.send(RLIAP2Message(identifier: 0xAA03, body: sigBody))

                    case 0xAA05: // AuthenticationSucceeded
                        snapshot.authenticated = true
                        snapshot.lastError = nil
                        onSnapshot(snapshot)
                        emitEvent("authentication_succeeded")
                        onAuthenticated?()

                    case 0xAA04: // AuthenticationFailed
                        throw IAP2LinkError.protocolError("Accessory authentication failed (0xAA04)")

                    case 0xFFFA: // StartLocationInformation
                        activeSentences = Set(
                            fields
                                .filter { ($0.identifier == 1 || $0.identifier == 2) && $0.data.isEmpty }
                                .map(\.identifier)
                        )
                        minIntervals.removeAll()
                        var minIntervalsMsLog: [String: Int] = [:]
                        for field in fields where (field.identifier == 0x8001 || field.identifier == 0x8002) && field.data.count == 4 {
                            let ms = field.data.withUnsafeBytes { ptr -> UInt32 in
                                let raw = ptr.load(as: UInt32.self)
                                return UInt32(bigEndian: raw)
                            }
                            let sid = field.identifier - 0x8000
                            minIntervals[sid] = max(0.2, Double(ms) / 1000.0)
                            minIntervalsMsLog["\(sid)"] = Int(ms)
                        }
                        lastSent.removeAll()
                        triggerFastBurst(seconds: 15.0)
                        snapshot.activeSentences = activeSentences.sorted()
                        onSnapshot(snapshot)
                        emitEvent("location_requested", details: [
                            "sentences": snapshot.activeSentences.map(Int.init),
                            "min_intervals_ms": minIntervalsMsLog,
                        ])
                        onLocationRequested?()
                        if sawLocationStopped {
                            sawLocationStopped = false
                            onSubscriptionRestarted?()
                        }

                    case 0xFFFC: // StopLocationInformation
                        sawLocationStopped = true
                        activeSentences.removeAll()
                        snapshot.activeSentences = []
                        onSnapshot(snapshot)
                        emitEvent("location_stopped")
                        onLocationStopped?()

                    default:
                        break
                    }
                }

                if configuration.mode == .send,
                   snapshot.identified,
                   snapshot.authenticated,
                   !activeSentences.isEmpty,
                   !isCancelled() {
                    stateLock.lock()
                    let shouldResetKalman = pendingKalmanReset
                    pendingKalmanReset = false
                    stateLock.unlock()

                    if shouldResetKalman {
                        lastSent.removeAll()
                        let voidMap = NMEAGenerator.voidLocationSentences()
                        let voidOutgoing = activeSentences.sorted().compactMap { voidMap[$0] }
                        if !voidOutgoing.isEmpty, let voidMsg = try? NMEAGenerator.locationMessage(sentences: voidOutgoing) {
                            link.sendBestEffort(voidMsg, timeout: 0.2)
                            emitEvent("kalman_reset_void_sent")
                            Thread.sleep(forTimeInterval: 0.05)
                        }
                    }

                    let tickNow = CFAbsoluteTimeGetCurrent()
                    var target = locationBox.get()
                    let burstActive = isFastBurstActive(now: tickNow)
                    let due = activeSentences.sorted().filter { id in
                        let last = lastSent[id] ?? -.infinity
                        let required = burstActive ? 0.2 : max(configuration.intervalSeconds, minIntervals[id] ?? 0.25)
                        return tickNow - last >= required
                    }
                    if !due.isEmpty {
                        stateLock.lock()
                        if burstMotionPacketsRemaining > 0 {
                            burstMotionPacketsRemaining -= 1
                            if target.speedKnots == 0 {
                                target.speedKnots = 0.4
                            }
                        }
                        stateLock.unlock()

                        let sentenceMap = try NMEAGenerator.locationSentences(for: target, hdop: 0.5, fixQuality: 2)
                        let outgoing = due.compactMap { sentenceMap[$0] }
                        let locMsg = try NMEAGenerator.locationMessage(sentences: outgoing)
                        try link.send(locMsg)

                        for id in due {
                            lastSent[id] = tickNow
                        }
                        snapshot.packetsAcknowledged += 1
                        snapshot.lastError = nil
                        onSnapshot(snapshot)

                        if snapshot.packetsAcknowledged == 1 || snapshot.packetsAcknowledged % 10 == 0 {
                            emitEvent("location_link_acknowledged", details: [
                                "count": snapshot.packetsAcknowledged,
                                "lat": String(format: "%.6f", target.latitude),
                                "lon": String(format: "%.6f", target.longitude),
                            ])
                        }
                    }
                }
            }

            if isCancelled() && snapshot.authenticated {
                // Step 1: Degrade cached accessory accuracy (HDOP 35.0) toward fallback real coordinate
                // so indoor Wi-Fi/Cell positioning immediately outranks the accessory cache.
                if !activeSentences.isEmpty {
                    stateLock.lock()
                    let degradeLoc = fallbackRealLocation ?? locationBox.get()
                    stateLock.unlock()
                    if let degradedMap = try? NMEAGenerator.locationSentences(for: degradeLoc, hdop: 35.0, fixQuality: 1) {
                        let degradedOutgoing = activeSentences.sorted().compactMap { degradedMap[$0] }
                        if !degradedOutgoing.isEmpty,
                           let degradedMsg = try? NMEAGenerator.locationMessage(sentences: degradedOutgoing) {
                            link.sendBestEffort(degradedMsg, timeout: 0.2)
                            Thread.sleep(forTimeInterval: 0.04)
                        }
                    }

                    // Step 2: Emit invalid/void NMEA fix (GGA quality=0 / RMC status=V).
                    let voidMap = NMEAGenerator.voidLocationSentences()
                    let voidOutgoing = activeSentences.sorted().compactMap { voidMap[$0] }
                    if !voidOutgoing.isEmpty, let voidMsg = try? NMEAGenerator.locationMessage(sentences: voidOutgoing) {
                        link.sendBestEffort(voidMsg, timeout: 0.2)
                        emitEvent("location_void_sent", details: ["sentences": activeSentences.sorted().map(Int.init)])
                        Thread.sleep(forTimeInterval: 0.04)
                    }
                }
                // Step 3: Send iAP2 RST control packet so iOS detaches the accessory immediately.
                link.sendReset()
                emitEvent("iap2_link_reset_sent")
                Thread.sleep(forTimeInterval: 0.04)
            }

            emitEvent("finished", details: [
                "identified": snapshot.identified,
                "authenticated": snapshot.authenticated,
                "location_packets_acknowledged": snapshot.packetsAcknowledged,
            ])
            if !keepRunningOnExit {
                snapshot.isRunning = false
                onSnapshot(snapshot)
            }
            return .completed(packetCount: snapshot.packetsAcknowledged)
        } catch {
            if isCancelled() {
                emitEvent("stopped", details: ["reason": "user_cancelled"])
                if !keepRunningOnExit {
                    snapshot.isRunning = false
                    onSnapshot(snapshot)
                }
                return .completed(packetCount: snapshot.packetsAcknowledged)
            }
            let message = error.localizedDescription
            let isFatal = message.contains("0xAA04") || message.contains("Identification rejected")
            if isFatal || !keepRunningOnExit {
                snapshot.lastError = message
                emitEvent("error", details: ["detail": message], isError: true)
                snapshot.isRunning = false
                onSnapshot(snapshot)
                return isFatal ? .fatalError(message) : .recoverableError(
                    message,
                    didSendPackets: snapshot.packetsAcknowledged > initialPacketCount,
                    packetCount: snapshot.packetsAcknowledged
                )
            }
            return .recoverableError(
                message,
                didSendPackets: snapshot.packetsAcknowledged > initialPacketCount,
                packetCount: snapshot.packetsAcknowledged
            )
        }
    }
}
