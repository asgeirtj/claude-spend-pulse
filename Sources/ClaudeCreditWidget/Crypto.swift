import Foundation
import CommonCrypto

enum Crypto {
    static func pbkdf2SHA1(password: String, salt: String, iterations: Int, keyLength: Int) -> Data? {
        let passwordBytes = Array(password.utf8)
        let saltBytes = Array(salt.utf8)
        var derivedKey = [UInt8](repeating: 0, count: keyLength)
        let status = passwordBytes.withUnsafeBufferPointer { pwdBuf -> Int32 in
            saltBytes.withUnsafeBufferPointer { saltBuf -> Int32 in
                pwdBuf.baseAddress!.withMemoryRebound(to: Int8.self, capacity: pwdBuf.count) { pwdInt8 in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwdInt8, pwdBuf.count,
                        saltBuf.baseAddress, saltBuf.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        UInt32(iterations),
                        &derivedKey, keyLength
                    )
                }
            }
        }
        guard status == 0 else {
            WidgetLog.log("[Crypto] PBKDF2 failed status=\(status)")
            return nil
        }
        return Data(derivedKey)
    }

    static func aesCBCDecrypt(ciphertext: Data, key: Data, iv: Data, label: String = "") -> Data? {
        var outBytes = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        var numBytesDecrypted = 0
        let status = ciphertext.withUnsafeBytes { (cipherBuf: UnsafeRawBufferPointer) -> Int32 in
            key.withUnsafeBytes { (keyBuf: UnsafeRawBufferPointer) -> Int32 in
                iv.withUnsafeBytes { (ivBuf: UnsafeRawBufferPointer) -> Int32 in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyBuf.baseAddress, key.count,
                        ivBuf.baseAddress,
                        cipherBuf.baseAddress, ciphertext.count,
                        &outBytes, outBytes.count,
                        &numBytesDecrypted
                    )
                }
            }
        }
        guard status == Int32(kCCSuccess) else {
            WidgetLog.log("[Crypto] AES-CBC decrypt failed (\(label)) status=\(status) keyLen=\(key.count) ivLen=\(iv.count) cipherLen=\(ciphertext.count)")
            return nil
        }
        return Data(outBytes.prefix(numBytesDecrypted))
    }

    static func sha256(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }

    static func sha256Prefix(_ data: Data) -> String {
        sha256(data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
