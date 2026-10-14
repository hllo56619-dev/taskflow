package com.minh.taskflow

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.content.res.ColorStateList
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

class MainActivity : Activity() {
    private val blue = Color.rgb(53, 99, 233)
    private val ink = Color.rgb(23, 32, 51)
    private val muted = Color.rgb(123, 132, 151)
    private val canvas = Color.rgb(246, 247, 251)
    private val line = Color.rgb(232, 236, 244)
    private val green = Color.rgb(21, 150, 106)

    private lateinit var repository: TaskRepository
    private val io = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var allTasks: List<TaskItem> = emptyList()
    private var currentFilter = FILTER_TODAY
    private var isLoading = false
    private var authEmailInput: EditText? = null
    private var authPasswordInput: EditText? = null
    private var authSubmitButton: Button? = null
    private var tabButtons: List<Button> = emptyList()
    private var countLabel: TextView? = null
    private var taskContainer: LinearLayout? = null
    private var syncLabel: TextView? = null

    private val pollRunnable = object : Runnable {
        override fun run() {
            if (!isFinishing && repository.hasSession() && taskContainer != null) {
                loadTasks(showSpinner = false, showErrors = false)
                mainHandler.postDelayed(this, 30_000L)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = canvas
        window.navigationBarColor = Color.WHITE
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        repository = TaskRepository(this)

        if (!repository.isConfigured()) {
            showAuthScreen(configWarning = true)
        } else if (repository.hasSession()) {
            showMainScreen()
            loadTasks(showSpinner = true, showErrors = true)
        } else {
            showAuthScreen()
        }
    }

    override fun onResume() {
        super.onResume()
        if (::repository.isInitialized && repository.hasSession() && taskContainer != null) {
            mainHandler.removeCallbacks(pollRunnable)
            mainHandler.postDelayed(pollRunnable, 30_000L)
            loadTasks(showSpinner = false, showErrors = false)
        }
    }

    override fun onPause() {
        mainHandler.removeCallbacks(pollRunnable)
        super.onPause()
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(pollRunnable)
        io.shutdown()
        super.onDestroy()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun baseColumn(padding: Int = 20): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(padding), dp(padding), dp(padding), dp(padding))
    }

    private fun rounded(color: Int, radiusDp: Int = 14, strokeColor: Int? = null): GradientDrawable = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(radiusDp).toFloat()
        if (strokeColor != null) setStroke(dp(1), strokeColor)
    }

    private fun label(text: String, sizeSp: Float, color: Int = ink, bold: Boolean = false): TextView = TextView(this).apply {
        this.text = text
        textSize = sizeSp
        setTextColor(color)
        if (bold) setTypeface(typeface, Typeface.BOLD)
        includeFontPadding = true
    }

    private fun button(text: String, primary: Boolean = false): Button = Button(this).apply {
        this.text = text
        textSize = 14f
        isAllCaps = false
        setTypeface(typeface, Typeface.BOLD)
        setTextColor(if (primary) Color.WHITE else ink)
        background = rounded(if (primary) blue else Color.WHITE, 12, if (primary) null else line)
        minimumHeight = dp(46)
        setPadding(dp(15), dp(8), dp(15), dp(8))
        stateListAnimator = null
    }

    private fun space(height: Int): View = View(this).apply {
        layoutParams = LinearLayout.LayoutParams(1, dp(height))
    }

    private fun showAuthScreen(configWarning: Boolean = false) {
        taskContainer = null
        tabButtons = emptyList()
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(22), dp(26), dp(22), dp(26))
            setBackgroundColor(canvas)
        }
        val card = baseColumn(22).apply {
            background = rounded(Color.WHITE, 22, line)
            elevation = dp(2).toFloat()
        }
        val brand = label("✓  TaskFlow", 27f, blue, true).apply { gravity = Gravity.CENTER }
        val heading = label("Danh sách việc của bạn", 20f, ink, true).apply { gravity = Gravity.CENTER }
        val subtitle = label("Đăng nhập để đồng bộ với Mac", 13f, muted).apply { gravity = Gravity.CENTER }
        card.addView(brand, matchWrap())
        card.addView(space(19))
        card.addView(heading, matchWrap())
        card.addView(space(7))
        card.addView(subtitle, matchWrap())
        card.addView(space(21))

        if (configWarning) {
            val warning = label(
                "Trước tiên hãy điền Supabase URL và publishable/anon key trong AppConfig.kt. Xem README.md để làm theo từng bước.",
                12f,
                Color.rgb(126, 83, 15)
            ).apply {
                setPadding(dp(12), dp(12), dp(12), dp(12))
                background = rounded(Color.rgb(255, 247, 220), 10)
            }
            card.addView(warning, matchWrap())
            card.addView(space(12))
        }

        card.addView(label("Email", 12f, muted, true), matchWrap())
        authEmailInput = EditText(this).apply {
            hint = "ban@email.com"
            textSize = 14f
            singleLine = true
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS
            setPadding(dp(12), dp(11), dp(12), dp(11))
            background = rounded(Color.WHITE, 10, line)
        }
        card.addView(authEmailInput, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(48)))
        card.addView(space(13))
        card.addView(label("Mật khẩu", 12f, muted, true), matchWrap())
        authPasswordInput = EditText(this).apply {
            hint = "Ít nhất 6 ký tự"
            textSize = 14f
            singleLine = true
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            setPadding(dp(12), dp(11), dp(12), dp(11))
            background = rounded(Color.WHITE, 10, line)
        }
        card.addView(authPasswordInput, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(48)))
        card.addView(space(19))

        authSubmitButton = button("Đăng nhập", primary = true).apply {
            isEnabled = !configWarning
            setOnClickListener { authenticate(isSignUp = false) }
        }
        card.addView(authSubmitButton, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(48)))
        card.addView(space(6))
        val signup = button("Tạo tài khoản mới").apply {
            isEnabled = !configWarning
            setOnClickListener { authenticate(isSignUp = true) }
        }
        card.addView(signup, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(48)))
        card.addView(space(10))
        card.addView(label("Trên điện thoại, bạn chỉ cần xem danh sách và tích hoàn thành.", 11f, muted).apply { gravity = Gravity.CENTER }, matchWrap())

        root.addView(card, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        setContentView(root)
    }

    private fun authenticate(isSignUp: Boolean) {
        val email = authEmailInput?.text?.toString()?.trim().orEmpty()
        val password = authPasswordInput?.text?.toString().orEmpty()
        if (email.isBlank() || !email.contains('@')) {
            toast("Nhập email hợp lệ nhé.")
            return
        }
        if (password.length < 6) {
            toast("Mật khẩu cần ít nhất 6 ký tự.")
            return
        }
        authSubmitButton?.isEnabled = false
        authSubmitButton?.text = if (isSignUp) "Đang tạo tài khoản…" else "Đang đăng nhập…"
        io.execute {
            try {
                if (isSignUp) repository.signUp(email, password) else repository.signIn(email, password)
                mainHandler.post {
                    showMainScreen()
                    loadTasks(showSpinner = true, showErrors = true)
                    toast(if (isSignUp) "Tạo tài khoản thành công." else "Đăng nhập thành công.")
                }
            } catch (error: NeedsEmailConfirmationException) {
                mainHandler.post {
                    authSubmitButton?.isEnabled = true
                    authSubmitButton?.text = "Đăng nhập"
                    toast(error.message ?: "Hãy xác nhận email rồi đăng nhập.")
                }
            } catch (error: Exception) {
                mainHandler.post {
                    authSubmitButton?.isEnabled = true
                    authSubmitButton?.text = "Đăng nhập"
                    toast(error.message ?: "Không thể đăng nhập. Kiểm tra cấu hình Supabase.")
                }
            }
        }
    }

    private fun showMainScreen() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(canvas)
        }

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(20), dp(17), dp(14), dp(10))
        }
        val titleColumn = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        titleColumn.addView(label("TaskFlow", 13f, blue, true), matchWrap())
        titleColumn.addView(space(3))
        titleColumn.addView(label("Việc cần làm", 25f, ink, true), matchWrap())
        titleColumn.addView(space(4))
        titleColumn.addView(label(todayLabel(), 12f, muted), matchWrap())
        header.addView(titleColumn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        val refresh = button("↻", false).apply {
            textSize = 22f
            minimumWidth = dp(44)
            setOnClickListener { loadTasks(showSpinner = true, showErrors = true) }
        }
        header.addView(refresh)
        val logout = button("Thoát", false).apply {
            textSize = 12f
            minimumWidth = dp(58)
            setOnClickListener { logout() }
        }
        val logoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dp(44))
        logoutParams.marginStart = dp(5)
        header.addView(logout, logoutParams)
        root.addView(header)

        val summaryCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(13), dp(16), dp(13))
            background = rounded(Color.WHITE, 14, line)
        }
        countLabel = label("Đang tải danh sách…", 14f, ink, true)
        summaryCard.addView(countLabel, matchWrap())
        syncLabel = label("Đang kết nối Supabase", 11f, muted)
        summaryCard.addView(space(4))
        summaryCard.addView(syncLabel, matchWrap())
        val summaryParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        summaryParams.setMargins(dp(16), dp(5), dp(16), dp(13))
        root.addView(summaryCard, summaryParams)

        val tabBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(16), 0, dp(16), dp(10))
        }
        val tabs = listOf("Hôm nay", "Chưa xong", "Đã xong")
        tabButtons = tabs.mapIndexed { index, text ->
            button(text, primary = index == currentFilter).apply {
                textSize = 12f
                minimumHeight = dp(39)
                setPadding(dp(8), dp(4), dp(8), dp(4))
                val params = LinearLayout.LayoutParams(0, dp(40), 1f)
                if (index > 0) params.marginStart = dp(7)
                tabBar.addView(this, params)
                setOnClickListener {
                    currentFilter = index
                    updateTabStyles()
                    renderTaskRows()
                }
            }
        }
        root.addView(tabBar)

        val scroll = ScrollView(this).apply {
            clipToPadding = false
            isFillViewport = false
            setPadding(dp(16), dp(1), dp(16), dp(20))
        }
        taskContainer = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        scroll.addView(taskContainer, ScrollView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(scroll, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

        setContentView(root)
        updateTabStyles()
    }

    private fun updateTabStyles() {
        tabButtons.forEachIndexed { index, tab ->
            val selected = index == currentFilter
            tab.setTextColor(if (selected) Color.WHITE else ink)
            tab.background = rounded(if (selected) blue else Color.WHITE, 11, if (selected) null else line)
        }
    }

    private fun loadTasks(showSpinner: Boolean, showErrors: Boolean) {
        if (!repository.hasSession() || isLoading) return
        isLoading = true
        if (showSpinner) syncLabel?.text = "Đang đồng bộ…"
        io.execute {
            try {
                val loaded = repository.fetchTasks()
                mainHandler.post {
                    allTasks = loaded
                    isLoading = false
                    syncLabel?.text = "Đã đồng bộ · ${SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())}"
                    renderTaskRows()
                }
            } catch (error: Exception) {
                mainHandler.post {
                    isLoading = false
                    syncLabel?.text = "Chưa đồng bộ được"
                    if (showErrors) toast(error.message ?: "Không tải được danh sách.")
                    if (!repository.hasSession()) showAuthScreen()
                }
            }
        }
    }

    private fun renderTaskRows() {
        val container = taskContainer ?: return
        container.removeAllViews()
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        val filtered = allTasks.filter { task ->
            when (currentFilter) {
                FILTER_TODAY -> !task.completed && (task.scheduledDate == today || task.dueDate == today || (task.scheduledDate == null && task.dueDate == null))
                FILTER_TODO -> !task.completed
                FILTER_DONE -> task.completed
                else -> !task.completed
            }
        }
        val completedCount = allTasks.count { it.completed }
        val todoCount = allTasks.size - completedCount
        countLabel?.text = when (currentFilter) {
            FILTER_TODAY -> "${filtered.size} việc trong danh sách hôm nay"
            FILTER_TODO -> "Còn $todoCount việc chưa hoàn thành"
            else -> "$completedCount việc đã hoàn thành"
        }

        if (filtered.isEmpty()) {
            val empty = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(dp(20), dp(52), dp(20), dp(54))
                background = rounded(Color.WHITE, 15, line)
            }
            val icon = label(if (currentFilter == FILTER_DONE) "✓" else "☀", 29f, green, true).apply { gravity = Gravity.CENTER }
            empty.addView(icon, matchWrap())
            empty.addView(space(10))
            empty.addView(label(
                when (currentFilter) { FILTER_TODAY -> "Hôm nay chưa có việc nào"; FILTER_TODO -> "Bạn đã xử lý hết việc"; else -> "Chưa có việc hoàn thành" },
                16f, ink, true
            ).apply { gravity = Gravity.CENTER }, matchWrap())
            empty.addView(space(7))
            empty.addView(label("Danh sách sẽ tự cập nhật khi bạn thêm việc trên Mac.", 12f, muted).apply { gravity = Gravity.CENTER }, matchWrap())
            container.addView(empty, matchWrap())
            return
        }

        filtered.forEach { task ->
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(8), dp(8), dp(10), dp(8))
                background = rounded(Color.WHITE, 13, line)
                minimumHeight = dp(76)
            }
            val checkbox = CheckBox(this).apply {
                buttonTintList = ColorStateList.valueOf(if (task.completed) green else blue)
                isChecked = task.completed
                contentDescription = if (task.completed) "Bỏ hoàn thành ${task.title}" else "Hoàn thành ${task.title}"
                setPadding(dp(4), dp(6), dp(10), dp(6))
                setOnCheckedChangeListener { _, checked ->
                    if (checked != task.completed) changeTaskStatus(task, checked)
                }
            }
            row.addView(checkbox, LinearLayout.LayoutParams(dp(48), dp(52)))

            val textColumn = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(2), dp(4), dp(2), dp(4))
            }
            val title = label(task.title, 14f, if (task.completed) muted else ink, true).apply {
                maxLines = 3
                setLineSpacing(dp(1).toFloat(), 1f)
                if (task.completed) paintFlags = paintFlags or android.graphics.Paint.STRIKE_THRU_TEXT_FLAG
            }
            textColumn.addView(title, matchWrap())
            val meta = buildString {
                task.categoryName?.let { append(it) }
                val dateText = when {
                    task.dueDate != null && task.dueDate < today && !task.completed -> "Quá hạn ${shortDate(task.dueDate)}"
                    task.dueDate == today && !task.completed -> "Hạn hôm nay"
                    task.scheduledDate != null -> "Dự định ${shortDate(task.scheduledDate)}"
                    task.dueDate != null -> "Hạn ${shortDate(task.dueDate)}"
                    else -> ""
                }
                if (dateText.isNotBlank()) {
                    if (isNotEmpty()) append("  ·  ")
                    append(dateText)
                }
                if (task.priority == "high") {
                    if (isNotEmpty()) append("  ·  ")
                    append("Ưu tiên cao")
                }
            }
            if (meta.isNotBlank()) {
                textColumn.addView(space(4))
                textColumn.addView(label(meta, 11f, if (!task.completed && task.dueDate != null && task.dueDate < today) Color.rgb(205, 66, 76) else muted), matchWrap())
            }
            row.addView(textColumn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            row.setOnClickListener { checkbox.isChecked = !checkbox.isChecked }
            val params = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            params.bottomMargin = dp(8)
            container.addView(row, params)
        }
    }

    private fun changeTaskStatus(task: TaskItem, completed: Boolean) {
        syncLabel?.text = "Đang lưu thay đổi…"
        io.execute {
            try {
                repository.setCompleted(task.id, completed)
                val refreshed = repository.fetchTasks()
                mainHandler.post {
                    allTasks = refreshed
                    syncLabel?.text = "Đã đồng bộ · ${SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())}"
                    renderTaskRows()
                    toast(if (completed) "Đã tích hoàn thành." else "Đã bỏ đánh dấu.")
                }
            } catch (error: Exception) {
                mainHandler.post {
                    loadTasks(showSpinner = false, showErrors = false)
                    syncLabel?.text = "Chưa lưu được thay đổi"
                    toast(error.message ?: "Không cập nhật được công việc.")
                }
            }
        }
    }

    private fun logout() {
        io.execute {
            repository.logout()
            mainHandler.post {
                allTasks = emptyList()
                showAuthScreen()
                toast("Đã đăng xuất.")
            }
        }
    }

    private fun todayLabel(): String = SimpleDateFormat("EEEE, d MMMM", Locale("vi", "VN")).format(Date())
        .replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale("vi", "VN")) else it.toString() }

    private fun shortDate(value: String): String {
        val parts = value.split("-")
        return if (parts.size == 3) "${parts[2]}/${parts[1]}" else value
    }

    private fun matchWrap() = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)

    private fun toast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
    }

    companion object {
        private const val FILTER_TODAY = 0
        private const val FILTER_TODO = 1
        private const val FILTER_DONE = 2
    }
}
