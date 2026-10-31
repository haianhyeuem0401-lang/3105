import CryptoKit
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Configuration
// ─────────────────────────────────────────────────────────────────────────────
private enum KeyConfig {
    /// Base URL server của QBao.
    static let baseURL = "https://qbaonew1.onrender.com"
    /// Endpoint POST để check key.  Body JSON: { "key": "..." }
    /// Server trả:  { "valid": true/false, "expires": "2026-12-31", "note": "..." }
    static let checkPath = "/check"
    /// Số giờ tối thiểu giữa hai lần revalidate khi app active.
    static let revalidateIntervalHours: Double = 6
    /// Tên admin hiển thị trong UI.
    static let adminName = "QbaoTweakxVft King"
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Request / Response models
// ─────────────────────────────────────────────────────────────────────────────

/// Body gửi lên server  POST /check
private struct KeyCheckRequest: Encodable {
    let key: String
    let device: String
    let ios: String
}

/// JSON server trả về.
/// Hỗ trợ nhiều format phổ biến:
///   { "valid": true, "expires": "...", "note": "..." }          ← chuẩn
///   { "status": "valid", "expiry": "...", "message": "..." }    ← variant
///   { "success": true, "data": { "expires": "..." } }           ← wrapped
struct KeyCheckResponse: Decodable {
    // Chuẩn
    let valid: Bool?
    let expires: String?
    let note: String?
    // Variants
    let status: String?
    let expiry: String?
    let message: String?
    let success: Bool?

    /// Kết quả cuối: true nếu bất kỳ dạng nào cho thấy hợp lệ.
    var isValid: Bool {
        if let v = valid { return v }
        if let v = success { return v }
        if let s = status {
            return s.lowercased() == "valid"
                || s.lowercased() == "ok"
                || s.lowercased() == "active"
        }
        return false
    }

    var expiresResolved: String? { expires ?? expiry }
    var noteResolved: String? { note ?? message }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - KeyVerificationService
// ─────────────────────────────────────────────────────────────────────────────
@MainActor
final class KeyVerificationService: ObservableObject {

    @Published private(set) var isVerified: Bool = false
    @Published private(set) var isChecking: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var keyExpires: String?
    @Published private(set) var serverNote: String?

    // Hash 1 chiều của key lưu vào UserDefaults (không lưu key gốc)
    private(set) var savedKeyHash: String? {
        get { UserDefaults.standard.string(forKey: "qbao.key.hash") }
        set { UserDefaults.standard.set(newValue, forKey: "qbao.key.hash") }
    }
    private var sessionKey: String?

    private var lastVerifiedAt: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: "qbao.key.lastVerified")
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            UserDefaults.standard.set(
                newValue?.timeIntervalSince1970 ?? 0,
                forKey: "qbao.key.lastVerified"
            )
        }
    }

    init() {
        if savedKeyHash != nil {
            log("key: previous session hash found — waiting for re-entry")
        }
    }

    // MARK: - Public

    func verify(key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Vui lòng nhập key."
            return
        }
        await performCheck(key: trimmed)
    }

    func logout() {
        isVerified = false
        savedKeyHash = nil
        sessionKey = nil
        lastVerifiedAt = nil
        keyExpires = nil
        serverNote = nil
        errorMessage = nil
        log("key: logged out")
    }

    func revalidateIfNeeded() {
        guard let key = sessionKey,
              let last = lastVerifiedAt else { return }
        let elapsed = Date().timeIntervalSince(last) / 3600
        guard elapsed >= KeyConfig.revalidateIntervalHours else { return }
        Task { await performCheck(key: key, silent: true) }
    }

    // MARK: - Internal

    private func performCheck(key: String, silent: Bool = false) async {
        guard !isChecking else { return }
        if !silent { isChecking = true; errorMessage = nil }
        defer { if !silent { isChecking = false } }

        // Thử POST trước, nếu server trả 405 thì fallback sang GET
        do {
            let response = try await callPOST(key: key)
                         ?? (try await callGET(key: key))
            if response.isValid {
                handleSuccess(key: key, response: response, silent: silent)
            } else {
                handleInvalid(
                    message: response.noteResolved ?? "Key không hợp lệ hoặc đã hết hạn.",
                    silent: silent
                )
            }
        } catch let urlErr as URLError where urlErr.code == .timedOut {
            if !silent { errorMessage = "Hết thời gian kết nối. Kiểm tra internet và thử lại." }
            log("key: timeout — \(urlErr.localizedDescription)")
        } catch {
            if !silent { errorMessage = "Không thể kết nối server. Kiểm tra internet." }
            log("key: error — \(error.localizedDescription)")
        }
    }

    // ── POST /check  { "key": "...", "device": "...", "ios": "..." } ──────────
    private func callPOST(key: String) async throws -> KeyCheckResponse? {
        guard let url = URL(string: KeyConfig.baseURL + KeyConfig.checkPath) else { return nil }

        let body = KeyCheckRequest(
            key: key,
            device: AppInfo.machineName,
            ios: AppInfo.osVersion
        )
        let bodyData = try JSONEncoder().encode(body)

        var req = URLRequest(url: url, timeoutInterval: 12)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("QbaoTweakxVft/1.0 iOS/\(AppInfo.osVersion)", forHTTPHeaderField: "User-Agent")
        req.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as? HTTPURLResponse

        // 405 Method Not Allowed → server không hỗ trợ POST → fallback GET
        if http?.statusCode == 405 { return nil }

        // 403 → key sai ngay
        if http?.statusCode == 403 {
            return KeyCheckResponse(valid: false, expires: nil, note: nil,
                                    status: nil, expiry: nil, message: nil, success: nil)
        }

        log("key: POST \(KeyConfig.checkPath) → HTTP \(http?.statusCode ?? 0) (\(data.count) bytes)")
        return try decode(data)
    }

    // ── GET /check?key=...&device=...&ios=... ─────────────────────────────────
    private func callGET(key: String) async throws -> KeyCheckResponse {
        var components = URLComponents(string: KeyConfig.baseURL + KeyConfig.checkPath)
        components?.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "device", value: AppInfo.machineName),
            URLQueryItem(name: "ios", value: AppInfo.osVersion)
        ]
        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("QbaoTweakxVft/1.0 iOS/\(AppInfo.osVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as? HTTPURLResponse

        if http?.statusCode == 403 {
            return KeyCheckResponse(valid: false, expires: nil, note: nil,
                                    status: nil, expiry: nil, message: nil, success: nil)
        }

        log("key: GET \(KeyConfig.checkPath) → HTTP \(http?.statusCode ?? 0) (\(data.count) bytes)")
        return try decode(data)
    }

    private func decode(_ data: Data) throws -> KeyCheckResponse {
        // Log raw để debug (chỉ 200 ký tự đầu)
        if let raw = String(data: data.prefix(200), encoding: .utf8) {
            log("key: raw response = \(raw)")
        }
        return try JSONDecoder().decode(KeyCheckResponse.self, from: data)
    }

    private func handleSuccess(key: String, response: KeyCheckResponse, silent: Bool) {
        sessionKey = key
        savedKeyHash = sha256Hex(key)
        lastVerifiedAt = Date()
        keyExpires = response.expiresResolved
        serverNote = response.noteResolved
        isVerified = true
        if !silent { errorMessage = nil }
        log("key: ✅ verified — expires=\(response.expiresResolved ?? "none") note=\(response.noteResolved ?? "")")
    }

    private func handleInvalid(message: String, silent: Bool) {
        isVerified = false
        savedKeyHash = nil
        sessionKey = nil
        if !silent { errorMessage = message }
        log("key: ❌ invalid — \(message)")
    }

    private func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Convenience
extension KeyVerificationService {
    var adminName: String { KeyConfig.adminName }
    var checkEndpoint: String { KeyConfig.baseURL + KeyConfig.checkPath }
}
