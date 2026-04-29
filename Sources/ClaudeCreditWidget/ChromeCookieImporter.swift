import Foundation
import Security
import SQLite3
import CommonCrypto

enum ChromeImportError: LocalizedError {
    case dbNotFound
    case dbCopyFailed(Error)
    case sqliteOpen
    case sqliteQuery
    case keychainPasswordMissing(OSStatus)
    case decryptFailed(String)
    case missingCookies([String])

    var errorDescription: String? {
        switch self {
        case .dbNotFound:
            return "Chrome cookie database not found at the expected path."
        case .dbCopyFailed(let e):
            return "Could not copy cookie DB: \(e.localizedDescription)"
        case .sqliteOpen:
            return "Could not open Chrome cookie database."
        case .sqliteQuery:
            return "Failed to query Chrome cookie database."
        case .keychainPasswordMissing(let s):
            if s == errSecUserCanceled {
                return "Keychain access denied. Click Allow on the prompt and try again."
            }
            return "Could not read Chrome Safe Storage password from Keychain (status \(s))."
        case .decryptFailed(let name):
            return "Failed to decrypt cookie \(name). Check ~/Library/Logs/ClaudeCreditWidget/widget.log for details."
        case .missingCookies(let names):
            return "Missing cookies in Chrome: \(names.joined(separator: ", ")). Make sure you're logged into platform.claude.com in Chrome."
        }
    }
}

struct ChromeImportResult {
    let sessionKey: String
    let orgId: String
}

enum ChromeCookieImporter {
    private static let salt = "saltysalt"
    private static let macIterations = 1003
    private static let keyLength = 16
    private static let iv = Data(repeating: 0x20, count: 16)

    static func importCookies() throws -> ChromeImportResult {
        WidgetLog.log("[Import] === Starting Chrome cookie import ===")

        let password = try chromeSafeStoragePassword()
        WidgetLog.log("[Import] Got Keychain password: length=\(password.count) sha256_8=\(Crypto.sha256Prefix(Data(password.utf8)))")

        let derivedKey = try deriveKey(password: password, label: "Chrome/macIters=\(macIterations)")
        WidgetLog.log("[Import] Derived key sha256_8=\(Crypto.sha256Prefix(derivedKey))")

        let cookies = try readCookies()
        WidgetLog.log("[Import] Read \(cookies.count) cookies for *.claude.com")
        for (name, entry) in cookies.sorted(by: { $0.key < $1.key }) {
            let prefix = entry.encrypted.prefix(3).map { String(format: "%02x", $0) }.joined()
            WidgetLog.log("[Import]   - \(name) (host=\(entry.hostKey)): \(entry.encrypted.count) bytes, prefix=\(prefix)")
        }

        guard let sessionEntry = cookies["sessionKey"] else {
            throw ChromeImportError.missingCookies(["sessionKey"])
        }
        guard let sessionKey = decrypt(sessionEntry.encrypted, hostKey: sessionEntry.hostKey, key: derivedKey, label: "sessionKey") else {
            tryAlternateDecryption(blob: sessionEntry.encrypted, password: password, name: "sessionKey")
            throw ChromeImportError.decryptFailed("sessionKey")
        }
        WidgetLog.log("[Import] sessionKey decrypted: length=\(sessionKey.count) prefix=\(sessionKey.prefix(12))…")

        guard let orgEntry = cookies["lastActiveOrg"] else {
            throw ChromeImportError.missingCookies(["lastActiveOrg"])
        }
        guard let orgId = decrypt(orgEntry.encrypted, hostKey: orgEntry.hostKey, key: derivedKey, label: "lastActiveOrg") else {
            throw ChromeImportError.decryptFailed("lastActiveOrg")
        }
        WidgetLog.log("[Import] lastActiveOrg decrypted: \(orgId)")

        return ChromeImportResult(sessionKey: sessionKey, orgId: orgId)
    }

    private static func deriveKey(password: String, label: String) throws -> Data {
        guard let key = Crypto.pbkdf2SHA1(password: password, salt: salt, iterations: macIterations, keyLength: keyLength) else {
            throw ChromeImportError.decryptFailed("PBKDF2 (\(label))")
        }
        return key
    }

    private static func chromeSafeStoragePassword() throws -> String {
        WidgetLog.log("[Import] Looking up Keychain item service='Chrome Safe Storage' account='Chrome'")
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Chrome Safe Storage",
            kSecAttrAccount as String: "Chrome",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        WidgetLog.log("[Import] SecItemCopyMatching status=\(status)")
        guard status == errSecSuccess,
              let data = item as? Data,
              let pwd = String(data: data, encoding: .utf8) else {
            // Log all generic-password "Safe Storage" entries for diagnosis
            logSafeStorageEntries()
            throw ChromeImportError.keychainPasswordMissing(status)
        }
        return pwd
    }

    private static func logSafeStorageEntries() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: 50
        ]
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        guard status == errSecSuccess, let array = items as? [[String: Any]] else {
            WidgetLog.log("[Import] could not enumerate keychain items (status=\(status))")
            return
        }
        for item in array {
            let svc = (item[kSecAttrService as String] as? String) ?? ""
            let acct = (item[kSecAttrAccount as String] as? String) ?? ""
            if svc.contains("Safe Storage") || svc.contains("Chrome") {
                WidgetLog.log("[Import] keychain entry: service='\(svc)' account='\(acct)'")
            }
        }
    }

    struct CookieEntry {
        let hostKey: String
        let encrypted: Data
    }

    private static func readCookies() throws -> [String: CookieEntry] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dbURL = home
            .appendingPathComponent("Library/Application Support/Google/Chrome/Default/Cookies")
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw ChromeImportError.dbNotFound
        }

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ccw_cookies_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            try FileManager.default.copyItem(at: dbURL, to: tempURL)
        } catch {
            throw ChromeImportError.dbCopyFailed(error)
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tempURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw ChromeImportError.sqliteOpen
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT name, host_key, encrypted_value FROM cookies WHERE host_key LIKE '%claude.com'"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ChromeImportError.sqliteQuery
        }
        defer { sqlite3_finalize(stmt) }

        var result: [String: CookieEntry] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cName = sqlite3_column_text(stmt, 0),
                  let cHost = sqlite3_column_text(stmt, 1) else { continue }
            let name = String(cString: cName)
            let host = String(cString: cHost)
            let blobPtr = sqlite3_column_blob(stmt, 2)
            let blobLen = sqlite3_column_bytes(stmt, 2)
            guard let blobPtr, blobLen > 0 else { continue }
            let data = Data(bytes: blobPtr, count: Int(blobLen))
            result[name] = CookieEntry(hostKey: host, encrypted: data)
        }
        return result
    }

    private static func decrypt(_ encrypted: Data, hostKey: String, key: Data, label: String) -> String? {
        guard encrypted.count > 3 else {
            WidgetLog.log("[Import] decrypt(\(label)): blob too small (\(encrypted.count))")
            return nil
        }
        let prefix = encrypted.prefix(3)
        let prefixStr = String(data: prefix, encoding: .utf8) ?? "?"
        guard prefix == Data("v10".utf8) else {
            WidgetLog.log("[Import] decrypt(\(label)): unexpected prefix '\(prefixStr)' bytes=\(prefix.map { String(format: "%02x", $0) }.joined())")
            return nil
        }
        let ciphertext = encrypted.subdata(in: 3..<encrypted.count)
        guard ciphertext.count % 16 == 0 else {
            WidgetLog.log("[Import] decrypt(\(label)): ciphertext length \(ciphertext.count) not a multiple of 16")
            return nil
        }
        guard let plaintext = Crypto.aesCBCDecrypt(ciphertext: ciphertext, key: key, iv: iv, label: label) else {
            return nil
        }

        // Chrome 130+ on macOS wraps the value as [SHA256(host_key) | actual_value].
        // Try with the SHA-256 prefix stripped first; fall back to raw on failure.
        let hostHash = Crypto.sha256(Data(hostKey.utf8))
        if plaintext.count >= 32 {
            let possibleHash = plaintext.prefix(32)
            if possibleHash == hostHash {
                let body = plaintext.suffix(from: plaintext.startIndex.advanced(by: 32))
                if let str = String(data: body, encoding: .utf8) {
                    return str
                }
            }
        }
        if let str = String(data: plaintext, encoding: .utf8) {
            return str
        }
        WidgetLog.log("[Import] decrypt(\(label)): decrypted bytes are not valid UTF-8 (len=\(plaintext.count), first16=\(plaintext.prefix(16).map { String(format: "%02x", $0) }.joined()))")
        return nil
    }

    /// Try alternative parameter combinations to identify what scheme works.
    /// This only logs; it doesn't modify state.
    private static func tryAlternateDecryption(blob: Data, password: String, name: String) {
        WidgetLog.log("[Import] === Diagnostic: trying alternate decryption schemes for '\(name)' ===")

        guard blob.count > 3 else { return }
        let prefix = blob.prefix(3)
        let prefixStr = String(data: prefix, encoding: .utf8) ?? "?"
        WidgetLog.log("[Import] blob prefix: '\(prefixStr)' (\(prefix.map { String(format: "%02x", $0) }.joined())) total=\(blob.count) bytes")

        let cipher = blob.subdata(in: 3..<blob.count)

        // Try various iteration counts (Linux uses 1)
        for iter in [1, 1003, 10000] {
            guard let key = Crypto.pbkdf2SHA1(password: password, salt: salt, iterations: iter, keyLength: keyLength) else { continue }
            if let pt = Crypto.aesCBCDecrypt(ciphertext: cipher, key: key, iv: iv, label: "\(name)/iter=\(iter)"),
               let s = String(data: pt, encoding: .utf8) {
                WidgetLog.log("[Import] *** ALT: iter=\(iter) WORKED → '\(s.prefix(20))…'")
                return
            }
        }

        // Try larger key (AES-256 is sometimes used)
        if let key = Crypto.pbkdf2SHA1(password: password, salt: salt, iterations: macIterations, keyLength: 32) {
            // Use AES-256 by passing 32-byte key — CommonCrypto picks AES variant from key length
            var outBytes = [UInt8](repeating: 0, count: cipher.count + kCCBlockSizeAES128)
            var numBytesDecrypted = 0
            let status = cipher.withUnsafeBytes { cb in
                key.withUnsafeBytes { kb in
                    iv.withUnsafeBytes { ivb in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            kb.baseAddress, key.count,
                            ivb.baseAddress,
                            cb.baseAddress, cipher.count,
                            &outBytes, outBytes.count,
                            &numBytesDecrypted
                        )
                    }
                }
            }
            if status == 0,
               let s = String(data: Data(outBytes.prefix(numBytesDecrypted)), encoding: .utf8) {
                WidgetLog.log("[Import] *** ALT: AES-256 key (32 bytes, iter=\(macIterations)) WORKED → '\(s.prefix(20))…'")
                return
            } else {
                WidgetLog.log("[Import] ALT AES-256 status=\(status)")
            }
        }

        WidgetLog.log("[Import] No alternate scheme worked; suspect non-standard Chrome encryption")
    }

    private static func asciiPrefix(_ data: Data, count: Int) -> String {
        let bytes = data.prefix(count)
        return bytes.map { byte in
            if byte >= 0x20 && byte < 0x7f {
                return String(UnicodeScalar(byte))
            } else {
                return "·"
            }
        }.joined()
    }
}
