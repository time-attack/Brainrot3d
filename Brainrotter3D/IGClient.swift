import Foundation

/// Native Swift port of the reverse-engineered Instagram iOS client (`api_client.py`).
/// Talks directly to `i.instagram.com` from the device — no helper server.
final class IGClient {

    static let api = "https://i.instagram.com"
    static let appID = "124024574287414"
    static let appVersion = "435.0.0.39.111"
    static let appBuild = "999084704"
    static let userAgent =
        "Instagram \(appVersion) (iPhone14,5; iOS 16_3; en_US; en-US; scale=3.00; 1170x2532; \(appBuild))"
    static let bloksVersion = "ce555e5500576acd8e84a66c0d8da9f8f933e9871daf168409b6a0d7c6f0c0a8"

    // Stable per-install device identity (derived from a seed, like the Python client).
    let uuid: String
    let phoneID: String
    let familyDeviceID: String
    let adid: String
    var deviceID: String { uuid }

    // Rotating session state.
    var mid: String?
    var wwwClaim = "0"
    var authorization: String?
    var userID: String?
    var username: String?
    private var pubKey: String?
    private var pubKeyID: String?

    private let session: URLSession

    init(deviceSeed: String = "headlessify-grossed") {
        let h = IGCrypto.sha256Hex(deviceSeed)
        let h1 = String(h.prefix(32))
        let h2 = String(h.dropFirst(32).prefix(32))
        uuid = IGCrypto.uuidString(fromHex32: h1)
        phoneID = IGCrypto.uuidString(fromHex32: h2)
        familyDeviceID = IGCrypto.uuidString(fromHex32: IGCrypto.sha256Hex(h + "fam"))
        adid = IGCrypto.uuidString(fromHex32: IGCrypto.sha256Hex(h + "ad"))

        let cfg = URLSessionConfiguration.default
        cfg.httpShouldSetCookies = true
        cfg.httpCookieAcceptPolicy = .always
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg)
    }

    // MARK: Headers

    private func headers(extra: [String: String] = [:]) -> [String: String] {
        var h: [String: String] = [
            "User-Agent": Self.userAgent,
            "Accept-Language": "en-US",
            "X-IG-App-ID": Self.appID,
            "X-IG-Capabilities": "36r/F/8=",
            "X-IG-Connection-Type": "WIFI",
            "X-IG-Connection-Speed": "\(Int.random(in: 1000...5000))kbps",
            "X-IG-App-Locale": "en_US",
            "X-IG-Device-Locale": "en_US",
            "X-IG-Mapped-Locale": "en_US",
            "X-IG-Device-ID": uuid,
            "X-IG-Family-Device-ID": familyDeviceID,
            "X-IG-Timezone-Offset": "0",
            "X-IG-WWW-Claim": wwwClaim.isEmpty ? "0" : wwwClaim,
            "X-Bloks-Version-Id": Self.bloksVersion,
            "X-Bloks-Is-Layout-RTL": "false",
            "X-Pigeon-Session-Id": "UFS-\(UUID().uuidString.lowercased())-0",
            "X-Pigeon-Rawclienttime": String(format: "%.3f", Date().timeIntervalSince1970),
            "X-FB-HTTP-Engine": "Liger",
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
        ]
        if let mid { h["X-MID"] = mid }
        if let authorization {
            h["Authorization"] = authorization
            if let userID {
                h["IG-U-DS-User-ID"] = userID
                h["IG-INTENDED-USER-ID"] = userID
            }
        }
        h.merge(extra) { _, new in new }
        return h
    }

    /// Capture rotating session tokens from response headers.
    private func absorb(_ resp: HTTPURLResponse) {
        func v(_ k: String) -> String? { resp.value(forHTTPHeaderField: k) }
        if let a = v("ig-set-authorization"), !a.isEmpty { authorization = a }
        if let a = v("x-ig-set-authorization"), !a.isEmpty { authorization = a }
        if let m = v("ig-set-x-mid") { mid = m }
        if let c = v("x-ig-set-www-claim") { wwwClaim = c }
        if let u = v("ig-set-ig-u-ds-user-id") { userID = u }
        if let kid = v("ig-set-password-encryption-key-id") { pubKeyID = kid }
        if let pk = v("ig-set-password-encryption-pub-key") { pubKey = pk }
    }

    // MARK: Low-level

    @discardableResult
    func post(_ path: String, data: [String: String]?, signed: Bool = true,
                      extra: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var bodyString = ""
        if let data {
            if signed {
                let json = compactJSON(data)
                bodyString = "signed_body=" + encode("SIGNATURE." + json)
            } else {
                bodyString = data.map { "\(encode($0.key))=\(encode($0.value))" }.joined(separator: "&")
            }
        }
        return try await send(path, method: "POST", body: Data(bodyString.utf8), extra: extra)
    }

    @discardableResult
    func get(_ path: String, params: [String: String] = [:],
                     extra: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var p = path
        if !params.isEmpty {
            p += "?" + params.map { "\(encode($0.key))=\(encode($0.value))" }.joined(separator: "&")
        }
        return try await send(p, method: "GET", body: nil, extra: extra)
    }

    private func send(_ path: String, method: String, body: Data?,
                      extra: [String: String]) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: Self.api + path) else { throw IGError.network("bad url \(path)") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        for (k, v) in headers(extra: extra) { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw IGError.network("no http response") }
        absorb(http)
        return (data, http)
    }

    private func encode(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private func compactJSON(_ dict: [String: String]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: dict),
              let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }

    func jsonObject(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    // MARK: Pre-auth seeding

    private func syncPrelogin() async throws {
        _ = try await post("/api/v1/qe/sync/", data: [
            "id": uuid,
            "server_config_retrieval": "1",
            "experiments": "ig_android_device_detection_info_upload",
        ])
    }

    private func fetchPasswordPubKey() async throws {
        if pubKey != nil, pubKeyID != nil { return }
        _ = try await get("/api/v1/qe/sync/")
        if pubKey == nil || pubKeyID == nil {
            _ = try await post("/api/v1/launcher/mobile_config/",
                               data: ["id": uuid, "app_version": Self.appVersion])
        }
    }

    // MARK: Login

    enum LoginResult {
        case success
        case twoFactor(TwoFactorInfo)
        case failure(String)
    }

    func login(username: String, password: String) async throws -> LoginResult {
        try await syncPrelogin()
        try await fetchPasswordPubKey()
        guard let pubKey, let pubKeyID else {
            return .failure("server did not deliver a password key — try again")
        }
        let enc = try IGCrypto.encryptPassword(password, pubKeyB64: pubKey, keyId: pubKeyID)
        let data: [String: String] = [
            "jazoest": IGCrypto.jazoest(phoneID),
            "country_codes": "[{\"country_code\":\"1\",\"source\":[\"default\"]}]",
            "phone_id": phoneID,
            "enc_password": enc,
            "username": username,
            "adid": adid,
            "guid": uuid,
            "device_id": deviceID,
            "google_tokens": "[]",
            "login_attempt_count": "0",
        ]
        let (raw, http) = try await post("/api/v1/accounts/login/", data: data)
        let j = jsonObject(raw)
        self.username = username

        if http.statusCode == 200, let user = j["logged_in_user"] as? [String: Any] {
            userID = String(describing: user["pk"] ?? "")
            return .success
        }
        if (j["two_factor_required"] as? Bool) == true,
           let info = j["two_factor_info"] as? [String: Any] {
            return .twoFactor(TwoFactorInfo(json: info))
        }
        let msg = (j["message"] as? String) ?? "login failed"
        let type = (j["error_type"] as? String) ?? ""
        if msg.lowercased().contains("facebook account") || type == "ig_login_blocked" || type == "incomplete_login" {
            return .failure("Instagram rate-limited this attempt (new-device risk check). Wait ~30s and try again.")
        }
        return .failure(msg)
    }

    func twoFactorLogin(code: String, info: TwoFactorInfo, method: String) async throws -> LoginResult {
        guard let username else { return .failure("missing username") }
        let data: [String: String] = [
            "verification_code": code.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: ""),
            "two_factor_identifier": info.identifier,
            "username": username,
            "device_id": deviceID,
            "guid": uuid,
            "_uuid": uuid,
            "verification_method": method,
            "trust_this_device": "1",
        ]
        let (raw, http) = try await post("/api/v1/accounts/two_factor_login/", data: data)
        let j = jsonObject(raw)
        if http.statusCode == 200, let user = j["logged_in_user"] as? [String: Any] {
            userID = String(describing: user["pk"] ?? "")
            return .success
        }
        return .failure((j["message"] as? String) ?? "wrong code (HTTP \(http.statusCode))")
    }

    func sendTwoFactorSMS(_ info: TwoFactorInfo) async throws {
        guard let username else { return }
        _ = try await post("/api/v1/accounts/send_two_factor_login_sms/", data: [
            "username": username, "device_id": deviceID, "guid": uuid,
            "_uuid": uuid, "two_factor_identifier": info.identifier,
        ])
    }

    func sendTwoFactorWhatsApp(_ info: TwoFactorInfo) async throws {
        guard let username else { return }
        _ = try await post("/api/v1/two_factor/send_two_factor_login_whatsapp/", data: [
            "username": username, "device_id": deviceID, "guid": uuid,
            "_uuid": uuid, "two_factor_identifier": info.identifier,
        ])
    }

    // MARK: Reels

    /// Fetch a page of the Reels-tab discovery feed. Returns parsed reels + the next token.
    func reelsDiscover(maxID: String?) async throws -> (reels: [Reel], token: String?, status: Int) {
        var data: [String: String] = ["container_module": "clips_viewer_clips_tab", "_uuid": uuid]
        if let maxID { data["max_id"] = maxID }
        let (raw, http) = try await post("/api/v1/clips/discover/stream/", data: data)
        guard http.statusCode == 200, let text = String(data: raw, encoding: .utf8) else {
            return ([], nil, http.statusCode)
        }
        let objs = NDJSON.parse(text)
        let reels = NDJSON.findReels(objs).compactMap(Reel.init(json:))
        let token = NDJSON.findToken(objs)
        return (reels, token, 200)
    }

    func writeSeenState(pk: String) async {
        let data: [String: String] = [
            "_uuid": uuid, "nav_chain": "",
            "media_ids": "[\"\(pk)\"]",
        ]
        _ = try? await post("/api/v1/clips/write_seen_state/", data: data)
    }

    /// Cheap authed call used to validate a resumed bearer token.
    func validateSession() async -> Bool {
        guard authorization != nil else { return false }
        if let (_, http) = try? await post("/api/v1/clips/discover/stream/",
                                           data: ["container_module": "clips_viewer_clips_tab", "_uuid": uuid]) {
            return http.statusCode == 200
        }
        return false
    }

    // MARK: Persistence

    func saveState() {
        let d = UserDefaults.standard
        d.set(authorization, forKey: "ig_authorization")
        d.set(mid, forKey: "ig_mid")
        d.set(wwwClaim, forKey: "ig_www_claim")
        d.set(userID, forKey: "ig_user_id")
        d.set(username, forKey: "ig_username")
    }

    func loadState() {
        let d = UserDefaults.standard
        authorization = d.string(forKey: "ig_authorization")
        mid = d.string(forKey: "ig_mid")
        wwwClaim = d.string(forKey: "ig_www_claim") ?? "0"
        userID = d.string(forKey: "ig_user_id")
        username = d.string(forKey: "ig_username")
    }

    static func clearState() {
        let d = UserDefaults.standard
        ["ig_authorization", "ig_mid", "ig_www_claim", "ig_user_id", "ig_username"].forEach { d.removeObject(forKey: $0) }
    }
}

/// Two-factor metadata returned by the login call.
struct TwoFactorInfo {
    let identifier: String
    let totp: Bool
    let whatsapp: Bool
    let sms: Bool
    let obfuscatedPhone: String
    let obfuscatedPhone2: String

    init(json: [String: Any]) {
        identifier = (json["two_factor_identifier"] as? String) ?? ""
        totp = (json["totp_two_factor_on"] as? Bool) ?? false
        whatsapp = (json["whatsapp_two_factor_on"] as? Bool) ?? false
        sms = (json["sms_two_factor_on"] as? Bool) ?? false
        obfuscatedPhone = (json["obfuscated_phone_number"] as? String) ?? ""
        obfuscatedPhone2 = (json["obfuscated_phone_number_2"] as? String) ?? ""
    }

    struct Method: Identifiable { let id: String; let label: String }

    var methods: [Method] {
        var out: [Method] = []
        if totp { out.append(.init(id: "3", label: "Authenticator app (TOTP)")) }
        if whatsapp { out.append(.init(id: "6", label: "WhatsApp → \(obfuscatedPhone2.isEmpty ? "your number" : obfuscatedPhone2)")) }
        if sms { out.append(.init(id: "1", label: "SMS → ****\(obfuscatedPhone)")) }
        if out.isEmpty { out.append(.init(id: "3", label: "Enter your 6-digit code")) }
        return out
    }
}
