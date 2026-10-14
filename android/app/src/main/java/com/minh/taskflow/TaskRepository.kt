package com.minh.taskflow

import android.content.Context
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

internal data class TaskItem(
    val id: String,
    val title: String,
    val notes: String,
    val categoryName: String?,
    val scheduledDate: String?,
    val dueDate: String?,
    val priority: String,
    val completed: Boolean,
    val completedAt: String?,
    val isDaily: Boolean,
    val dailyCompletedOn: String?
)

internal class NeedsEmailConfirmationException : Exception("Tài khoản đã tạo. Hãy xác nhận email rồi đăng nhập.")

internal class TaskRepository(context: Context) {
    private val prefs = context.getSharedPreferences("taskflow_session", Context.MODE_PRIVATE)
    private val jsonType = "application/json; charset=utf-8".toMediaType()
    private val dailyTaskIds = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
    private val http = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .writeTimeout(20, TimeUnit.SECONDS)
        .callTimeout(25, TimeUnit.SECONDS)
        .build()

    private val baseUrl: String
        get() = AppConfig.SUPABASE_URL.trimEnd('/')

    fun isConfigured(): Boolean =
        !AppConfig.SUPABASE_URL.contains("YOUR-PROJECT-ID") &&
        !AppConfig.SUPABASE_ANON_KEY.contains("YOUR_SUPABASE") &&
        AppConfig.SUPABASE_URL.startsWith("https://")

    fun hasSession(): Boolean = !prefs.getString("access_token", null).isNullOrBlank()
    fun email(): String = prefs.getString("email", "") ?: ""

    @Throws(Exception::class)
    fun signIn(email: String, password: String) {
        val body = JSONObject().put("email", email).put("password", password)
        val response = request("/auth/v1/token?grant_type=password", "POST", body, null)
        val data = parseResponse(response)
        saveSession(data, email)
    }

    @Throws(Exception::class)
    fun signUp(email: String, password: String) {
        val body = JSONObject().put("email", email).put("password", password)
        val response = request("/auth/v1/signup", "POST", body, null)
        val data = parseResponse(response)
        if (data.optString("access_token").isBlank()) {
            throw NeedsEmailConfirmationException()
        }
        saveSession(data, email)
    }

    fun logout() {
        val token = prefs.getString("access_token", null)
        if (!token.isNullOrBlank()) {
            try { request("/auth/v1/logout", "POST", JSONObject(), token) } catch (_: Exception) { }
        }
        prefs.edit().clear().apply()
    }

    private var dailyColumnsAvailable = true

    fun isDailyTaskSchemaAvailable(): Boolean = dailyColumnsAvailable

    @Throws(Exception::class)
    fun fetchTasks(): List<TaskItem> {
        val userId = prefs.getString("user_id", null) ?: throw IOException("Phiên đăng nhập hết hạn. Hãy đăng nhập lại.")
        val dailyPath = "/rest/v1/tasks?select=id,title,notes,scheduled_date,due_date,priority,is_completed,completed_at,is_daily,daily_completed_on,position,created_at,categories(name)&user_id=eq.$userId&archived_at=is.null&order=position.asc,created_at.desc"
        val legacyPath = "/rest/v1/tasks?select=id,title,notes,scheduled_date,due_date,priority,is_completed,completed_at,position,created_at,categories(name)&user_id=eq.$userId&archived_at=is.null&order=position.asc,created_at.desc"
        val array = if (dailyColumnsAvailable) {
            try {
                parseArrayResponse(protectedRequest(dailyPath, "GET", null))
            } catch (error: IOException) {
                val message = error.message.orEmpty()
                val missingDailyColumn = (message.contains("is_daily", ignoreCase = true) ||
                    message.contains("daily_completed_on", ignoreCase = true)) &&
                    (message.contains("does not exist", ignoreCase = true) ||
                    message.contains("could not find", ignoreCase = true) ||
                    message.contains("schema cache", ignoreCase = true) ||
                    message.contains("42703", ignoreCase = true) ||
                    message.contains("PGRST204", ignoreCase = true))
                if (!missingDailyColumn) throw error
                dailyColumnsAvailable = false
                parseArrayResponse(protectedRequest(legacyPath, "GET", null))
            }
        } else {
            parseArrayResponse(protectedRequest(legacyPath, "GET", null))
        }
        dailyTaskIds.clear()
        val result = ArrayList<TaskItem>(array.length())
        for (index in 0 until array.length()) {
            val obj = array.getJSONObject(index)
            val categoryObj = obj.optJSONObject("categories")
            if (obj.optBoolean("is_daily", false)) dailyTaskIds.add(obj.getString("id"))
            result.add(
                TaskItem(
                    id = obj.getString("id"),
                    title = obj.optString("title", ""),
                    notes = obj.optString("notes", ""),
                    categoryName = categoryObj?.optString("name")?.takeIf { !it.isNullOrBlank() },
                    scheduledDate = obj.optString("scheduled_date").takeUnless { it.isBlank() || it == "null" },
                    dueDate = obj.optString("due_date").takeUnless { it.isBlank() || it == "null" },
                    priority = obj.optString("priority", "normal"),
                    completed = if (obj.optBoolean("is_daily", false)) obj.optString("daily_completed_on") == java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date()) else obj.optBoolean("is_completed", false),
                    completedAt = obj.optString("completed_at").takeUnless { it.isBlank() || it == "null" },
                    isDaily = obj.optBoolean("is_daily", false),
                    dailyCompletedOn = obj.optString("daily_completed_on").takeUnless { it.isBlank() || it == "null" }
                )
            )
        }
        return result
    }

    @Throws(Exception::class)
    fun setCompleted(taskId: String, completed: Boolean) {
        val userId = prefs.getString("user_id", null) ?: throw IOException("Hãy đăng nhập lại.")
        val payload = JSONObject().put("is_completed", completed)
        // Set completed_at to a timestamp when checked; clear it when unchecked.
        payload.put("completed_at", if (completed) java.time.Instant.now().toString() else JSONObject.NULL)
        val task = dailyTaskIds.contains(taskId)
        if (task) payload.put("daily_completed_on", if (completed) java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date()) else JSONObject.NULL)
        val response = protectedRequest(
            "/rest/v1/tasks?id=eq.$taskId&user_id=eq.$userId",
            "PATCH",
            payload
        )
        if (response.code !in 200..299) {
            val message = errorMessage(response)
            response.close()
            throw IOException(message)
        }
        response.close()
    }

    private fun saveSession(data: JSONObject, fallbackEmail: String) {
        val user = data.optJSONObject("user")
        val token = data.optString("access_token")
        if (token.isBlank()) throw IOException("Supabase chưa trả về phiên đăng nhập.")
        val refreshToken = data.optString("refresh_token").takeIf { it.isNotBlank() }
            ?: (prefs.getString("refresh_token", "") ?: "")
        val userId = user?.optString("id")?.takeIf { it.isNotBlank() }
            ?: (prefs.getString("user_id", "") ?: "")
        val savedEmail = user?.optString("email")?.takeIf { it.isNotBlank() } ?: fallbackEmail
        val editor = prefs.edit()
            .putString("access_token", token)
            .putString("refresh_token", refreshToken)
            .putString("user_id", userId)
            .putString("email", savedEmail)
        editor.apply()
    }

    @Throws(Exception::class)
    private fun protectedRequest(path: String, method: String, body: JSONObject?): okhttp3.Response {
        val token = prefs.getString("access_token", null) ?: throw IOException("Hãy đăng nhập lại.")
        var response = request(path, method, body, token)
        if (response.code != 401) return response
        response.close()
        if (!refreshSession()) {
            prefs.edit().clear().apply()
            throw IOException("Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.")
        }
        val freshToken = prefs.getString("access_token", null) ?: throw IOException("Hãy đăng nhập lại.")
        response = request(path, method, body, freshToken)
        return response
    }

    private fun refreshSession(): Boolean {
        val refreshToken = prefs.getString("refresh_token", null)?.takeIf { it.isNotBlank() } ?: return false
        return try {
            val response = request(
                "/auth/v1/token?grant_type=refresh_token",
                "POST",
                JSONObject().put("refresh_token", refreshToken),
                null
            )
            if (response.code !in 200..299) {
                response.close()
                false
            } else {
                val data = JSONObject(response.body?.string().orEmpty())
                response.close()
                saveSession(data, email())
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun request(path: String, method: String, body: JSONObject?, bearer: String?): okhttp3.Response {
        val builder = Request.Builder()
            .url(baseUrl + path)
            .header("apikey", AppConfig.SUPABASE_ANON_KEY)
            .header("Accept", "application/json")
        if (!bearer.isNullOrBlank()) builder.header("Authorization", "Bearer $bearer")
        when (method) {
            "GET" -> builder.get()
            "POST" -> builder.post((body ?: JSONObject()).toString().toRequestBody(jsonType))
            "PATCH" -> builder.patch((body ?: JSONObject()).toString().toRequestBody(jsonType))
            "DELETE" -> builder.delete()
            else -> throw IllegalArgumentException("Unsupported HTTP method: $method")
        }
        if (path.startsWith("/rest/v1/")) builder.header("Prefer", "return=minimal")
        return http.newCall(builder.build()).execute()
    }

    private fun parseResponse(response: okhttp3.Response): JSONObject {
        val text = response.body?.string().orEmpty()
        val code = response.code
        response.close()
        if (code !in 200..299) throw IOException(parseErrorMessage(text, code))
        return if (text.isBlank()) JSONObject() else JSONObject(text)
    }

    private fun parseArrayResponse(response: okhttp3.Response): JSONArray {
        val text = response.body?.string().orEmpty()
        val code = response.code
        response.close()
        if (code !in 200..299) throw IOException(parseErrorMessage(text, code))
        return JSONArray(text)
    }

    private fun errorMessage(response: okhttp3.Response): String {
        val code = response.code
        val text = response.body?.string().orEmpty()
        return parseErrorMessage(text, code)
    }

    private fun parseErrorMessage(text: String, code: Int): String {
        return try {
            val obj = JSONObject(text)
            obj.optString("msg").takeIf { it.isNotBlank() }
                ?: obj.optString("message").takeIf { it.isNotBlank() }
                ?: obj.optString("error_description").takeIf { it.isNotBlank() }
                ?: obj.optString("error").takeIf { it.isNotBlank() }
                ?: "Lỗi máy chủ ($code)."
        } catch (_: Exception) {
            "Lỗi máy chủ ($code). Kiểm tra URL, khóa Supabase và cấu hình cơ sở dữ liệu."
        }
    }
}
