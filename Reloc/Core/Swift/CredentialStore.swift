import CryptoKit
import Foundation
import Security
import SwiftUI

public enum AppAppearanceMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "Follow System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

public enum MapSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case appleNative
    case globalStreet
    case globalOSM
    case globalSatellite

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .appleNative: return "Apple Maps (System Default)"
        case .globalStreet: return "Global Streets (Esri · WGS-84)"
        case .globalOSM: return "OpenStreetMap (Open Source · WGS-84)"
        case .globalSatellite: return "Global Satellite (Esri · WGS-84)"
        }
    }

    public var shortTitle: String {
        switch self {
        case .appleNative: return "Apple Maps"
        case .globalStreet: return "Global Streets"
        case .globalOSM: return "OSM Map"
        case .globalSatellite: return "Global Satellite"
        }
    }

    /// True when the tile source uses pure WGS-84 coordinates (no GCJ-02 shift in Mainland China).
    public var isPureWGS84: Bool {
        self != .appleNative
    }
}

public enum MapDisplayStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case standard
    case satellite
    case hybrid

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: return "Standard"
        case .satellite: return "Satellite"
        case .hybrid: return "Hybrid"
        }
    }
}

public struct FavoriteLocation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var subtitle: String?
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double

    public init(
        id: UUID = UUID(),
        name: String,
        subtitle: String? = nil,
        latitude: Double,
        longitude: Double,
        altitude: Double = 10.0
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }
}

public struct RecentLocation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var subtitle: String?
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double
    public var usedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        subtitle: String? = nil,
        latitude: Double,
        longitude: Double,
        altitude: Double = 10.0,
        usedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.usedAt = usedAt
    }
}

public struct InterruptedSessionRecord: Codable, Equatable, Sendable {
    public var placeName: String
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double
    public var savedAt: Date

    public init(
        placeName: String,
        latitude: Double,
        longitude: Double,
        altitude: Double,
        savedAt: Date = Date()
    ) {
        self.placeName = placeName
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.savedAt = savedAt
    }
}

public enum PairingKind: String, Equatable, Sendable {
    case remotePairing = "Remote Pairing"
    case lockdown = "Lockdown"
}

public enum SavedPairing: @unchecked Sendable {
    case remotePairing(data: Data, identifier: String)
    case lockdown(record: RLPairingRecord)

    public var kind: PairingKind {
        switch self {
        case .remotePairing: return .remotePairing
        case .lockdown: return .lockdown
        }
    }
}

public struct PairingStatus: Equatable {
    public var isLoaded: Bool
    public var kind: PairingKind?
    public var summaryID: String?
    public var errorMessage: String?
}

public enum PairingImportError: LocalizedError {
    case oversized
    case invalidFormat(String)

    public var errorDescription: String? {
        switch self {
        case .oversized:
            return "The pairing file has an invalid size."
        case .invalidFormat(let detail):
            return detail
        }
    }
}

/// Persists device pairing records, loopback settings, favorites, recent 30 history items,
/// speed/unit/appearance preferences, and interrupted-session recovery snapshots.
public final class CredentialStore {
    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let host = "reloc.host"
        static let remotePort = "reloc.remotePort"
        static let lockdownPort = "reloc.port"
        static let serviceName = "reloc.serviceName"
        static let deviceUDID = "reloc.deviceUDID"
        static let interval = "reloc.interval"
        static let duration = "reloc.duration"
        static let gcj02Correction = "reloc.gcj02Correction"
        static let backgroundKeepAlive = "reloc.backgroundKeepAlive"
        static let microJitter = "reloc.microJitter"
        static let appearance = "reloc.appearance"
        static let mapStyle = "reloc.mapStyle"
        static let mapSource = "reloc.mapSource"
        static let favorites = "reloc.favorites"
        static let recents = "reloc.recents"
        static let interruptedSession = "reloc.interruptedSession"
        static let lastLatitude = "reloc.lastLat"
        static let lastLongitude = "reloc.lastLon"
        static let lastAltitude = "reloc.lastAlt"
    }

    private enum Keychain {
        static let service = "dev.reloc.ios.pairing"
        static let account = "active_device_pairing"
    }

    private var appSupportDir: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Reloc", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDir = dir
        try? mutableDir.setResourceValues(values)
        return dir
    }

    public var documentsDir: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private var pairingURL: URL {
        appSupportDir.appendingPathComponent("device.pairing.plist")
    }

    private var legacyPairingURL: URL {
        appSupportDir.appendingPathComponent("pairing.mobiledevicepairing")
    }

    // MARK: - Connection & Behavior Settings

    public var host: String {
        get { defaults.string(forKey: Keys.host) ?? "10.7.0.1" }
        set { defaults.set(newValue, forKey: Keys.host) }
    }

    public var remotePort: UInt16 {
        get {
            let saved = defaults.integer(forKey: Keys.remotePort)
            return saved > 0 && saved <= 65535 ? UInt16(saved) : 49152
        }
        set { defaults.set(Int(newValue), forKey: Keys.remotePort) }
    }

    public var lockdownPort: UInt16 {
        get {
            let saved = defaults.integer(forKey: Keys.lockdownPort)
            return saved > 0 && saved <= 65535 ? UInt16(saved) : 62078
        }
        set { defaults.set(Int(newValue), forKey: Keys.lockdownPort) }
    }

    public var serviceName: String {
        get { defaults.string(forKey: Keys.serviceName) ?? "com.apple.carkit.service" }
        set { defaults.set(newValue, forKey: Keys.serviceName) }
    }

    public var deviceUDID: String {
        get { defaults.string(forKey: Keys.deviceUDID) ?? "" }
        set { defaults.set(newValue, forKey: Keys.deviceUDID) }
    }

    public var intervalSeconds: Double {
        get {
            let v = defaults.double(forKey: Keys.interval)
            return v >= 1.0 ? v : 1.0
        }
        set { defaults.set(max(1.0, newValue), forKey: Keys.interval) }
    }

    public var durationSeconds: Double {
        get { max(0.0, defaults.double(forKey: Keys.duration)) }
        set { defaults.set(max(0.0, newValue), forKey: Keys.duration) }
    }

    public var gcj02CorrectionEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.gcj02Correction) == nil { return true }
            return defaults.bool(forKey: Keys.gcj02Correction)
        }
        set { defaults.set(newValue, forKey: Keys.gcj02Correction) }
    }

    public var backgroundKeepAliveEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.backgroundKeepAlive) == nil { return true }
            return defaults.bool(forKey: Keys.backgroundKeepAlive)
        }
        set { defaults.set(newValue, forKey: Keys.backgroundKeepAlive) }
    }

    public var microJitterEnabled: Bool {
        get { defaults.bool(forKey: Keys.microJitter) }
        set { defaults.set(newValue, forKey: Keys.microJitter) }
    }

    public var appearanceMode: AppAppearanceMode {
        get { defaults.string(forKey: Keys.appearance).flatMap(AppAppearanceMode.init) ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Keys.appearance) }
    }

    public var mapStyle: MapDisplayStyle {
        get { defaults.string(forKey: Keys.mapStyle).flatMap(MapDisplayStyle.init) ?? .standard }
        set { defaults.set(newValue.rawValue, forKey: Keys.mapStyle) }
    }

    public var mapSource: MapSource {
        get { defaults.string(forKey: Keys.mapSource).flatMap(MapSource.init) ?? .appleNative }
        set { defaults.set(newValue.rawValue, forKey: Keys.mapSource) }
    }

    public var lastTargetLocation: TargetLocation {
        get {
            if defaults.object(forKey: Keys.lastLatitude) == nil {
                return TargetLocation(latitude: 37.334606, longitude: -122.009102, altitude: 20.0)
            }
            return TargetLocation(
                latitude: defaults.double(forKey: Keys.lastLatitude),
                longitude: defaults.double(forKey: Keys.lastLongitude),
                altitude: defaults.object(forKey: Keys.lastAltitude) != nil ? defaults.double(forKey: Keys.lastAltitude) : 10.0
            )
        }
        set {
            defaults.set(newValue.latitude, forKey: Keys.lastLatitude)
            defaults.set(newValue.longitude, forKey: Keys.lastLongitude)
            defaults.set(newValue.altitude, forKey: Keys.lastAltitude)
        }
    }

    // MARK: - Favorites, Recents (max 30), and Interrupted Session Recovery

    public func loadFavorites() -> [FavoriteLocation] {
        guard let data = defaults.data(forKey: Keys.favorites),
              let decoded = try? JSONDecoder().decode([FavoriteLocation].self, from: data) else {
            return [
                FavoriteLocation(name: "Apple Park", subtitle: "Cupertino, CA", latitude: 37.334606, longitude: -122.009102, altitude: 20.0),
                FavoriteLocation(name: "Tokyo Station", subtitle: "Chiyoda, Tokyo, Japan", latitude: 35.681236, longitude: 139.767125, altitude: 10.0),
                FavoriteLocation(name: "Taipei 101", subtitle: "Xinyi District, Taipei, Taiwan", latitude: 25.033964, longitude: 121.564468, altitude: 12.0),
            ]
        }
        return decoded
    }

    public func saveFavorites(_ favorites: [FavoriteLocation]) {
        if let encoded = try? JSONEncoder().encode(favorites) {
            defaults.set(encoded, forKey: Keys.favorites)
        }
    }

    public func loadRecents() -> [RecentLocation] {
        guard let data = defaults.data(forKey: Keys.recents),
              let decoded = try? JSONDecoder().decode([RecentLocation].self, from: data) else {
            return []
        }
        return decoded
    }

    public func saveRecents(_ recents: [RecentLocation]) {
        let trimmed = Array(recents.prefix(30))
        if let encoded = try? JSONEncoder().encode(trimmed) {
            defaults.set(encoded, forKey: Keys.recents)
        }
    }

    public func loadInterruptedSession() -> InterruptedSessionRecord? {
        guard let data = defaults.data(forKey: Keys.interruptedSession) else { return nil }
        return try? JSONDecoder().decode(InterruptedSessionRecord.self, from: data)
    }

    public func saveInterruptedSession(_ record: InterruptedSessionRecord?) {
        guard let record else {
            defaults.removeObject(forKey: Keys.interruptedSession)
            return
        }
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: Keys.interruptedSession)
        }
    }

    // MARK: - Pairing Validation & Storage (Remote Pairing + Lockdown)

    public static func validatePairingData(_ raw: Data) throws -> (normalizedXML: Data, pairing: SavedPairing) {
        guard raw.count > 0 && raw.count < 2_000_000 else {
            throw PairingImportError.oversized
        }
        guard let dict = try PropertyListSerialization.propertyList(from: raw, format: nil) as? [String: Any] else {
            throw PairingImportError.invalidFormat("The pairing file must be a valid plist.")
        }
        let xml = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)

        if let privateKey = dict["private_key"] as? Data,
           let publicKey = dict["public_key"] as? Data,
           let identifier = dict["identifier"] as? String,
           !identifier.isEmpty {
            guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKey),
                  key.publicKey.rawRepresentation == publicKey else {
                throw PairingImportError.invalidFormat("The Ed25519 public and private keys in the Remote Pairing file do not match.")
            }
            return (xml, .remotePairing(data: xml, identifier: identifier))
        }

        let lockdown = try RLPairingRecord(plistData: xml)
        return (xml, .lockdown(record: lockdown))
    }

    @discardableResult
    public func importPairingFile(from url: URL) throws -> SavedPairing {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        if url.hasDirectoryPath || ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true) {
            throw PairingImportError.invalidFormat("Select a pairing file, not a folder.")
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            var coordError: NSError?
            var readResult: Result<Data, Error>?
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordError) { coordinatedURL in
                readResult = Result { try Data(contentsOf: coordinatedURL) }
            }
            if let readResult {
                data = try readResult.get()
            } else if let coordError {
                throw coordError
            } else {
                throw error
            }
        }
        return try importPairingData(data)
    }

    @discardableResult
    public func importPairingData(_ raw: Data) throws -> SavedPairing {
        let (xml, pairing) = try Self.validatePairingData(raw)
        try savePairingBytes(xml)
        try? fileManager.removeItem(at: legacyPairingURL)
        return pairing
    }

    private func savePairingBytes(_ xml: Data) throws {
        let status = writePairingToKeychain(xml)
        if status == errSecSuccess {
            try? fileManager.removeItem(at: pairingURL)
            return
        }
        if status == errSecMissingEntitlement {
            // Unsigned simulator / test-host fallback with backup exclusion.
            var target = pairingURL
            try xml.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? target.setResourceValues(values)
            return
        }
        throw PairingImportError.invalidFormat("Unable to write to the system Keychain (OSStatus \(status)）。")
    }

    private func writePairingToKeychain(_ data: Data) -> OSStatus {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Keychain.service,
            kSecAttrAccount: Keychain.account,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData] = data
        attrs[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attrs as CFDictionary, nil)
    }

    private func readPairingFromKeychain() -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Keychain.service,
            kSecAttrAccount: Keychain.account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func deletePairingFromKeychain() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Keychain.service,
            kSecAttrAccount: Keychain.account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    @discardableResult
    public func saveOnDevicePairedIdentity(_ rawRecord: Data, hostIRK: Data, udid: String) throws -> SavedPairing {
        guard hostIRK.count == 16 else {
            throw PairingImportError.invalidFormat("The pairing host identity is invalid.")
        }
        var dict = (try PropertyListSerialization.propertyList(from: rawRecord, format: nil) as? [String: Any]) ?? [:]
        dict["reloc_host_irk"] = hostIRK
        let xml = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        let pairing = try importPairingData(xml)
        if !udid.isEmpty {
            deviceUDID = udid
        }
        return pairing
    }

    /// Builds the optional `record` + `host_irk` request payload so re-pairing reuses the existing host identity.
    public func loadOnDeviceRepairingRequest() -> [String: String] {
        guard case .remotePairing(let xmlData, _) = loadPairing().0,
              let dict = try? PropertyListSerialization.propertyList(from: xmlData, format: nil) as? [String: Any] else {
            return [:]
        }
        var req: [String: String] = ["record": xmlData.base64EncodedString()]
        if let irk = dict["reloc_host_irk"] as? Data, irk.count == 16 {
            req["host_irk"] = irk.base64EncodedString()
        }
        return req
    }

    public func importDiscoveredPairingInDocuments() -> SavedPairing? {
        if loadPairing().0 != nil { return nil }
        guard let files = try? fileManager.contentsOfDirectory(
            at: documentsDir,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        ) else { return nil }

        let validExts: Set<String> = ["mobiledevicepairing", "mobilepair", "rppairing", "plist"]
        let candidates: [(url: URL, date: Date, data: Data)] = files.prefix(100).compactMap { url in
            guard validExts.contains(url.pathExtension.lowercased()),
                  let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]),
                  vals.isRegularFile == true,
                  vals.isSymbolicLink != true,
                  (vals.fileSize ?? Int.max) < 2_000_000,
                  let data = try? Data(contentsOf: url),
                  (try? Self.validatePairingData(data)) != nil else {
                return nil
            }
            return (url, vals.contentModificationDate ?? .distantPast, data)
        }

        guard let newest = candidates.max(by: { $0.date < $1.date }),
              let imported = try? importPairingData(newest.data) else {
            return nil
        }
        // Remove plaintext pairing file from shared Documents once safely imported.
        try? fileManager.removeItem(at: newest.url)
        return imported
    }

    public func loadPairing() -> (SavedPairing?, PairingStatus) {
        let keychainData = readPairingFromKeychain()
        let diskURL = fileManager.fileExists(atPath: pairingURL.path) ? pairingURL : legacyPairingURL
        let rawData: Data
        let loadedFromDisk: Bool

        if let keychainData {
            rawData = keychainData
            loadedFromDisk = false
        } else if fileManager.fileExists(atPath: diskURL.path) {
            do {
                rawData = try Data(contentsOf: diskURL)
                loadedFromDisk = true
            } catch {
                return (nil, PairingStatus(isLoaded: false, kind: nil, summaryID: nil, errorMessage: error.localizedDescription))
            }
        } else {
            return (nil, PairingStatus(isLoaded: false, kind: nil, summaryID: nil, errorMessage: nil))
        }

        do {
            let (xml, pairing) = try Self.validatePairingData(rawData)
            if loadedFromDisk && writePairingToKeychain(xml) == errSecSuccess {
                try? fileManager.removeItem(at: pairingURL)
                try? fileManager.removeItem(at: legacyPairingURL)
            }
            let summary: String
            switch pairing {
            case .remotePairing(_, let identifier):
                summary = identifier
            case .lockdown(let record):
                summary = record.hostID
            }
            return (pairing, PairingStatus(isLoaded: true, kind: pairing.kind, summaryID: summary, errorMessage: nil))
        } catch {
            return (nil, PairingStatus(isLoaded: false, kind: nil, summaryID: nil, errorMessage: error.localizedDescription))
        }
    }

    public func removePairingFile() {
        deletePairingFromKeychain()
        try? fileManager.removeItem(at: pairingURL)
        try? fileManager.removeItem(at: legacyPairingURL)
        deviceUDID = ""
    }

    // MARK: - Internal Bundled MFi Signer

    public func loadBundledMFiSigner() -> RLMFiSigner? {
        let bundle = Bundle.main
        guard let certURL = bundle.url(forResource: "certificate", withExtension: "p7b", subdirectory: "MFi")
                ?? bundle.url(forResource: "certificate", withExtension: "p7b"),
              let keyURL = bundle.url(forResource: "identity", withExtension: "pk8", subdirectory: "MFi")
                ?? bundle.url(forResource: "identity", withExtension: "pk8"),
              let certData = try? Data(contentsOf: certURL),
              let keyData = try? Data(contentsOf: keyURL) else {
            return nil
        }
        return try? RLMFiSigner(certificateData: certData, privateKeyData: keyData)
    }
}
