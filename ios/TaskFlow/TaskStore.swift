import Foundation
import Combine
import Security

private enum TaskFlowConfig {
    static let supabaseURL = "https://udhtzlsqbpjklxoyvwgl.supabase.co"
    static let publishableKey = "sb_publishable_y-N5n7lL1c809Bbo4yzbjA_7gKk3cMd"
}

struct TaskSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let userID: String
    let email: String
}

struct TaskItem: Identifiable, Hashable {
    let id: String
    let title: String
    let notes: String
    let categoryName: String?
    let scheduledDate: String?
    let dueDate: String?
    let priority: String
    let isCompleted: Bool
    let isDaily: Bool
    let dailyCompletedOn: String?
    let createdAt: String?

    init(json: [String: Any]) {
        id = json["id"] as? String ?? UUID().uuidString
        title = json["title"] as? String ?? "(Không có tiêu đề)"
        notes = json["notes"] as? String ?? ""
        if let category = json["categories"] as? [String: Any] {
            categoryName = category["name"] as? String
        } else if let categories = json["categories"] as? [[String: Any]] {
            categoryName = categories.first?["name"] as? String
        } else {
            categoryName = nil
        }
        scheduledDate = json["scheduled_date"] as? String
        dueDate = json["due_date"] as? String
        priority = json["priority"] as? String ?? "normal"
        isDaily = json["is_daily"] as? Bool ?? false
        dailyCompletedOn = json["daily_completed_on"] as? String
        let completed = json["is_completed"] as? Bool ?? false
        isCompleted = isDaily ? (dailyCompletedOn == Self.todayString()) : completed
        createdAt = json["created_at"] as? String
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    var dueLabel: String? {
        guard let dueDate else { return nil }
        return "Hạn \(Self.prettyDate(dueDate))"
    }

    static func prettyDate(_ value: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else { return value }
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var session: TaskSession?
    @Published private(set) var tasks: [TaskItem] = []
    @Published var isLoading = false
    @Published var alertMessage: String?
    @Published private(set) var dailySchemaAvailable = true

    private let sessionKey = "taskflow.ios.session"
    private var baseURL: String { TaskFlowConfig.supabaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }

    init() {
        session = Self.loadKeychainSession()
    }

    func authenticate(email: String, password: String, createAccount: Bool) async {
        let cleanedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedEmail.contains("@") else {
            alertMessage = "Bạn hãy nhập email hợp lệ."
            return
        }
        guard password.count >= 6 else {
            alertMessage = "Mật khẩu cần có ít nhất 6 ký tự."
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let path = createAccount ? "/auth/v1/signup" : "/auth/v1/token"
            let query = createAccount ? [] : [URLQueryItem(name: "grant_type", value: "password")]
            let payload = try JSONSerialization.data(withJSONObject: [
                "email": cleanedEmail,
                "password": password
            ])
            let data = try await send(path: path, query: query, method: "POST", body: payload, attachSession: false)
            if let newSession = try sessionFromAuthResponse(data, fallbackEmail: cleanedEmail, fallbackSession: nil) {
                saveSession(newSession)
                session = newSession
                await loadTasks()
                if createAccount { alertMessage = "Tạo tài khoản thành công." }
            } else if createAccount {
                alertMessage = "Tài khoản đã được tạo. Hãy mở email xác nhận, rồi quay lại đăng nhập."
            } else {
                alertMessage = "Supabase chưa trả về phiên đăng nhập. Hãy kiểm tra email và mật khẩu."
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func loadTasks() async {
        guard session != nil else { return }
        isLoading = true
        defer { isLoading = false }
        let fields = "id,title,notes,scheduled_date,due_date,priority,is_completed,completed_at,is_daily,daily_completed_on,position,archived_at,created_at,updated_at,categories(name)"
        let legacyFields = "id,title,notes,scheduled_date,due_date,priority,is_completed,completed_at,position,archived_at,created_at,updated_at,categories(name)"
        let baseQuery = [
            URLQueryItem(name: "user_id", value: "eq.\(session?.userID ?? "")"),
            URLQueryItem(name: "archived_at", value: "is.null"),
            URLQueryItem(name: "order", value: "position.asc,created_at.desc")
        ]
        do {
            let data: Data
            do {
                data = try await send(
                    path: "/rest/v1/tasks",
                    query: [URLQueryItem(name: "select", value: fields)] + baseQuery,
                    method: "GET"
                )
                dailySchemaAvailable = true
            } catch {
                guard Self.isMissingDailyColumns(error) else { throw error }
                dailySchemaAvailable = false
                data = try await send(
                    path: "/rest/v1/tasks",
                    query: [URLQueryItem(name: "select", value: legacyFields)] + baseQuery,
                    method: "GET"
                )
            }
            let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
            tasks = objects.map { TaskItem(json: $0) }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func createTask(title: String, notes: String, priority: String, isDaily: Bool) async -> Bool {
        guard let session else {
            alertMessage = "Hãy đăng nhập lại trước khi tạo công việc."
            return false
        }
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else {
            alertMessage = "Hãy nhập tên công việc."
            return false
        }
        if isDaily && !dailySchemaAvailable {
            alertMessage = "Cần cập nhật Supabase trước khi tạo công việc hằng ngày. Hãy chạy supabase/daily_tasks_migration.sql trong SQL Editor."
            return false
        }

        var payload: [String: Any] = [
            "user_id": session.userID,
            "title": cleanedTitle,
            "notes": notes.trimmingCharacters(in: .whitespacesAndNewlines),
            "priority": priority,
            "is_completed": false
        ]
        if dailySchemaAvailable {
            payload["is_daily"] = isDaily
        }

        isLoading = true
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            _ = try await send(path: "/rest/v1/tasks", method: "POST", body: body, preferMinimal: true)
            isLoading = false
            await loadTasks()
            return true
        } catch {
            isLoading = false
            alertMessage = error.localizedDescription
            return false
        }
    }

    func toggle(_ task: TaskItem, completed: Bool) async {
        guard let session else { return }
        var payload: [String: Any] = [
            "is_completed": completed,
            "completed_at": completed ? ISO8601DateFormatter().string(from: Date()) : NSNull()
        ]
        if dailySchemaAvailable && task.isDaily {
            payload["daily_completed_on"] = completed ? Self.todayString() : NSNull()
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            _ = try await send(
                path: "/rest/v1/tasks",
                query: [
                    URLQueryItem(name: "id", value: "eq.\(task.id)"),
                    URLQueryItem(name: "user_id", value: "eq.\(session.userID)")
                ],
                method: "PATCH",
                body: data,
                preferMinimal: true
            )
            await loadTasks()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func signOut() async {
        if session != nil {
            _ = try? await send(path: "/auth/v1/logout", method: "POST", body: Data("{}".utf8), attachSession: true, retryOnUnauthorized: false)
        }
        session = nil
        tasks = []
        deleteKeychainSession()
    }

    func clearAlert() { alertMessage = nil }

    private func send(
        path: String,
        query: [URLQueryItem] = [],
        method: String,
        body: Data? = nil,
        attachSession: Bool = true,
        retryOnUnauthorized: Bool = true,
        preferMinimal: Bool = false
    ) async throws -> Data {
        guard var components = URLComponents(string: baseURL + path) else {
            throw TaskFlowError.message("Địa chỉ Supabase không hợp lệ.")
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw TaskFlowError.message("Không tạo được địa chỉ yêu cầu.") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(TaskFlowConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if preferMinimal { request.setValue("return=minimal", forHTTPHeaderField: "Prefer") }
        if attachSession, let token = session?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TaskFlowError.message("Supabase trả về phản hồi không hợp lệ.")
        }
        if http.statusCode == 401, attachSession, retryOnUnauthorized {
            do {
                try await refreshSession()
            } catch {
                session = nil
                tasks = []
                deleteKeychainSession()
                throw TaskFlowError.message("Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.")
            }
            return try await send(path: path, query: query, method: method, body: body, attachSession: true, retryOnUnauthorized: false, preferMinimal: preferMinimal)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TaskFlowError.message(Self.serverMessage(data, status: http.statusCode))
        }
        return data
    }

    private func refreshSession() async throws {
        guard let oldSession = session, !oldSession.refreshToken.isEmpty else {
            throw TaskFlowError.message("Không có refresh token.")
        }
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": oldSession.refreshToken])
        let data = try await send(
            path: "/auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            method: "POST",
            body: body,
            attachSession: false,
            retryOnUnauthorized: false
        )
        guard let refreshed = try sessionFromAuthResponse(data, fallbackEmail: oldSession.email, fallbackSession: oldSession) else {
            throw TaskFlowError.message("Không làm mới được phiên đăng nhập.")
        }
        saveSession(refreshed)
        session = refreshed
    }

    private func sessionFromAuthResponse(_ data: Data, fallbackEmail: String, fallbackSession: TaskSession?) throws -> TaskSession? {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let accessToken = root["access_token"] as? String, !accessToken.isEmpty else { return nil }
        let refreshToken = root["refresh_token"] as? String ?? fallbackSession?.refreshToken ?? ""
        let user = root["user"] as? [String: Any]
        let userID = user?["id"] as? String ?? fallbackSession?.userID
        guard let userID else { throw TaskFlowError.message("Không xác định được tài khoản Supabase.") }
        let userEmail = user?["email"] as? String ?? fallbackEmail
        return TaskSession(accessToken: accessToken, refreshToken: refreshToken, userID: userID, email: userEmail)
    }

    private static func isMissingDailyColumns(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return (text.contains("is_daily") || text.contains("daily_completed_on")) &&
            (text.contains("does not exist") || text.contains("could not find") || text.contains("schema cache") || text.contains("42703") || text.contains("pgrst204"))
    }

    private static func serverMessage(_ data: Data, status: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["msg", "message", "error_description", "error"] {
                if let message = object[key] as? String, !message.isEmpty { return message }
            }
        }
        return "Lỗi máy chủ (\(status)). Hãy thử lại sau."
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func saveSession(_ newSession: TaskSession) {
        session = newSession
        guard let data = try? JSONEncoder().encode(newSession) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.minh.taskflow.ios",
            kSecAttrAccount as String: sessionKey
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func loadKeychainSession() -> TaskSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.minh.taskflow.ios",
            kSecAttrAccount as String: "taskflow.ios.session",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(TaskSession.self, from: data)
    }

    private func deleteKeychainSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.minh.taskflow.ios",
            kSecAttrAccount as String: sessionKey
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private enum TaskFlowError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        }
    }
}
