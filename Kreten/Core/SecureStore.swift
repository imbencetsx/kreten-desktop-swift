import CryptoKit
import Foundation
import Security

/// AES-GCM encrypted state file whose 256-bit key lives in the login keychain.
/// Tokens and school data are never written to disk in plaintext.
struct SecureStore: Sendable {
    private static let magic = Data("KRETEN-MAC-1\0".utf8)
    private static let service = "app.kreten.desktop.mac"
    private static let keyAccount = "store-key"

    let directory: URL
    private let key: SymmetricKey

    init() throws {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        directory = support.appendingPathComponent("KRETEN", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        key = try Self.loadOrCreateKey(storeExists: FileManager.default.fileExists(atPath: directory.appendingPathComponent("store.enc").path))
    }

    private var file: URL { directory.appendingPathComponent("store.enc") }

    func read() throws -> StoreState {
        guard FileManager.default.fileExists(atPath: file.path) else { return StoreState() }
        let bytes = try Data(contentsOf: file)
        guard bytes.starts(with: Self.magic) else { throw KretaError.storage }
        do {
            let box = try AES.GCM.SealedBox(combined: bytes.dropFirst(Self.magic.count))
            let plain = try AES.GCM.open(box, using: key, authenticating: Self.magic)
            return try JSONDecoder.store.decode(StoreState.self, from: plain)
        } catch {
            throw KretaError.storage
        }
    }

    func write(_ state: StoreState) throws {
        do {
            let plain = try JSONEncoder.store.encode(state)
            let sealed = try AES.GCM.seal(plain, using: key, authenticating: Self.magic)
            guard let combined = sealed.combined else { throw KretaError.storage }
            try (Self.magic + combined).write(to: file, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            throw KretaError.storage
        }
    }

    private static func loadOrCreateKey(storeExists: Bool) throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyAccount,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        // A store without its key can never be decrypted; refuse to overwrite it silently.
        guard status == errSecItemNotFound, !storeExists else { throw KretaError.keychain }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyAccount,
            kSecAttrLabel as String: "KRETÉN helyi tároló kulcs",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw KretaError.keychain }
        return key
    }
}

extension JSONEncoder {
    static let store: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let store: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
