import SwiftUI

private enum TaskFilter: String, CaseIterable, Identifiable {
    case today = "Hôm nay"
    case daily = "Hằng ngày"
    case open = "Chưa xong"
    case done = "Đã xong"
    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var store = TaskStore()
    @AppStorage("taskflow.ios.darkMode") private var isDarkMode = false
    @State private var email = ""
    @State private var password = ""
    @State private var createAccount = false
    @State private var selectedFilter: TaskFilter = .today
    @State private var showingTaskEditor = false
    @State private var taskDraftTitle = ""
    @State private var taskDraftNotes = ""
    @State private var taskDraftPriority = "normal"
    @State private var taskDraftIsDaily = false
    @State private var taskDraftRepeatEnabled = false
    @State private var taskDraftRepeatTotal = 3

    var body: some View {
        Group {
            if store.session == nil {
                loginScreen
            } else {
                taskScreen
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .tint(.indigo)
        .animation(.easeInOut(duration: 0.22), value: isDarkMode)
        .task {
            if store.session != nil && store.tasks.isEmpty {
                await store.loadTasks()
            }
        }
        .alert("TaskFlow", isPresented: Binding(
            get: { store.alertMessage != nil },
            set: { if !$0 { store.clearAlert() } }
        )) {
            Button("Đóng", role: .cancel) { store.clearAlert() }
        } message: {
            Text(store.alertMessage ?? "")
        }
        .sheet(isPresented: $showingTaskEditor) {
            taskEditor
        }
    }

    private var loginScreen: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    HStack {
                        Spacer()
                        themeButton
                    }
                    .padding(.bottom, 4)

                    VStack(spacing: 10) {
                        logoMark(size: 70)
                        Text("TaskFlow")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("Việc rõ ràng. Đầu óc nhẹ nhàng.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                    VStack(alignment: .leading, spacing: 16) {
                        Text(createAccount ? "Tạo tài khoản" : "Chào mừng trở lại")
                            .font(.title2.bold())
                        Text(createAccount ? "Tạo tài khoản để đồng bộ công việc trên các thiết bị." : "Đăng nhập để xem và hoàn thành công việc của bạn.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 7) {
                            Text("Email").font(.subheadline.weight(.semibold))
                            TextField("ban@email.com", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(14)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.07)))
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Mật khẩu").font(.subheadline.weight(.semibold))
                            SecureField("Ít nhất 6 ký tự", text: $password)
                                .textContentType(createAccount ? .newPassword : .password)
                                .padding(14)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.07)))
                        }

                        Button {
                            Task { await store.authenticate(email: email, password: password, createAccount: createAccount) }
                        } label: {
                            HStack {
                                if store.isLoading { ProgressView().tint(.white) }
                                Text(store.isLoading ? "Đang xử lý…" : (createAccount ? "Tạo tài khoản" : "Đăng nhập"))
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .foregroundStyle(.white)
                            .background(LinearGradient(colors: [.indigo, .blue], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 13))
                        }
                        .disabled(store.isLoading)

                        Button {
                            createAccount.toggle()
                        } label: {
                            Text(createAccount ? "Đã có tài khoản? Đăng nhập" : "Chưa có tài khoản? Tạo mới")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(store.isLoading)
                        .padding(.top, 2)
                    }
                    .padding(22)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.primary.opacity(0.06)))
                    .shadow(color: .black.opacity(isDarkMode ? 0.12 : 0.045), radius: 24, y: 10)

                    Text("Dữ liệu đồng bộ với TaskFlow trên web và Android.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var taskScreen: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Keep action buttons separate so the title never wraps into narrow columns.
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        Button {
                            taskDraftTitle = ""
                            taskDraftNotes = ""
                            taskDraftPriority = "normal"
                            taskDraftIsDaily = selectedFilter == .daily
                            taskDraftRepeatEnabled = false
                            taskDraftRepeatTotal = 3
                            showingTaskEditor = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.headline.weight(.bold))
                                .frame(width: 44, height: 44)
                                .background(Color.indigo, in: RoundedRectangle(cornerRadius: 13))
                                .foregroundStyle(.white)
                        }
                        .accessibilityLabel(selectedFilter == .daily ? "Thêm công việc hằng ngày" : "Tạo công việc")
                        themeButton
                        Button {
                            Task { await store.signOut() }
                        } label: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.headline)
                                .frame(width: 44, height: 44)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Đăng xuất")
                    }

                    HStack(alignment: .center, spacing: 12) {
                        logoMark(size: 48)
                            .fixedSize()
                        VStack(alignment: .leading, spacing: 5) {
                            Text("TASKFLOW")
                                .font(.caption.weight(.bold))
                                .tracking(2)
                                .foregroundStyle(.indigo)
                                .lineLimit(1)
                            Text("Việc cần làm")
                                .font(.largeTitle.bold())
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                            Text(todayDateLabel)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    summaryCard

                    Picker("Danh sách công việc", selection: $selectedFilter) {
                        ForEach(TaskFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    if selectedTasks.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 11) {
                            ForEach(selectedTasks) { task in
                                taskCard(task, canToggle: selectedFilter == .today || !task.isDaily)
                                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                            }
                        }
                        .animation(.snappy(duration: 0.25), value: selectedTasks)
                    }

                    if !store.dailySchemaAvailable {
                        Label("Để dùng công việc hằng ngày, hãy chạy tệp supabase/daily_tasks_migration.sql trong Supabase SQL Editor.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }

                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Đồng bộ cùng tài khoản TaskFlow")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
                .padding(18)
                .frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .refreshable { await store.loadTasks() }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var summaryCard: some View {
        let total = store.tasks.count
        let completed = store.tasks.filter(\.isCompleted).count
        let progress = total == 0 ? 0 : Double(completed) / Double(total)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Tiến độ của bạn", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.title3.bold())
                    .foregroundStyle(.indigo)
            }
            ProgressView(value: progress)
                .tint(.indigo)
                .scaleEffect(x: 1, y: 1.35, anchor: .center)
            HStack(spacing: 0) {
                summaryMetric(title: "Tổng số việc", value: "\(total)", icon: "list.bullet")
                Spacer()
                summaryMetric(title: "Đã xong", value: "\(completed)", icon: "checkmark.circle.fill")
                Spacer()
                summaryMetric(title: "Còn lại", value: "\(max(total - completed, 0))", icon: "hourglass")
            }
        }
        .padding(17)
        .background(
            LinearGradient(colors: [Color.indigo.opacity(isDarkMode ? 0.20 : 0.09), Color(uiColor: .secondarySystemGroupedBackground)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.indigo.opacity(0.12)))
    }

    private func summaryMetric(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.indigo)
            Text(value).font(.title2.bold())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func taskCard(_ task: TaskItem, canToggle: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if canToggle {
                Button {
                    Task { await store.toggle(task, completed: !task.isCompleted) }
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(task.isCompleted ? .green : .indigo)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(task.isCompleted ? "Bỏ hoàn thành \(task.title)" : "Đánh dấu hoàn thành \(task.title)")
            } else {
                Image(systemName: "repeat")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 25, height: 28)
                    .accessibilityLabel("Công việc hằng ngày; đánh dấu hoàn thành tại mục Hôm nay")
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(task.title)
                    .font(.body.weight(.semibold))
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)

                if task.repeatEnabled {
                    HStack(spacing: 10) {
                        Text("Còn \(task.repeatRemaining) / \(task.repeatTotal) lần")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(task.repeatRemaining == 0 ? .green : .indigo)
                        Spacer(minLength: 0)
                        Button {
                            Task { await store.adjustRepeatCount(task, delta: -1) }
                        } label: {
                            Image(systemName: "minus")
                                .font(.caption.weight(.bold))
                                .frame(width: 30, height: 30)
                                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(task.repeatRemaining >= task.repeatTotal || store.isLoading)
                        .accessibilityLabel("Tăng số lần còn lại")
                        Button {
                            Task { await store.adjustRepeatCount(task, delta: 1) }
                        } label: {
                            Image(systemName: "plus")
                                .font(.caption.weight(.bold))
                                .frame(width: 30, height: 30)
                                .background(Color.indigo.opacity(0.12), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(task.repeatRemaining <= 0 || store.isLoading)
                        .accessibilityLabel("Giảm số lần còn lại")
                    }
                    .padding(.top, 3)
                }

                if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(task.notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 7) { taskBadges(task) }
                    VStack(alignment: .leading, spacing: 6) { taskBadges(task) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.primary.opacity(0.055)))
    }

    @ViewBuilder
    private func taskBadges(_ task: TaskItem) -> some View {
        if task.isDaily {
            Label("Hằng ngày", systemImage: "repeat")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.indigo)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.indigo.opacity(0.11), in: Capsule())
        }
        if let category = task.categoryName, !category.isEmpty {
            Label(category, systemImage: "folder")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.primary.opacity(0.055), in: Capsule())
        }
        if let date = task.scheduledDate {
            Label(TaskItem.prettyDate(date), systemImage: "calendar")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.primary.opacity(0.055), in: Capsule())
        }
        if let due = task.dueLabel {
            Label(due, systemImage: "flag")
                .font(.caption2.weight(.medium))
                .foregroundStyle(isOverdue(task) ? Color.red : Color.secondary)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.primary.opacity(0.055), in: Capsule())
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: selectedFilter == .done ? "checkmark.seal.fill" : "sun.max.fill")
                .font(.system(size: 34))
                .foregroundStyle(.indigo)
                .padding(18)
                .background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
            Text(emptyTitle).font(.headline)
            Text(emptySubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if store.isLoading { ProgressView().padding(.top, 4) }
            else {
                Button {
                    Task { await store.loadTasks() }
                } label: {
                    Label("Tải lại", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 38)
        .padding(.horizontal, 22)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var taskEditor: some View {
        NavigationStack {
            Form {
                Section("Chi tiết công việc") {
                    TextField("Tên công việc", text: $taskDraftTitle)
                        .textInputAutocapitalization(.sentences)
                    TextField("Ghi chú (không bắt buộc)", text: $taskDraftNotes, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Thiết lập") {
                    Picker("Mức ưu tiên", selection: $taskDraftPriority) {
                        Text("Cao").tag("high")
                        Text("Bình thường").tag("normal")
                        Text("Thấp").tag("low")
                    }
                    if store.dailySchemaAvailable {
                        Toggle("Lặp lại hằng ngày", isOn: $taskDraftIsDaily)
                    }
                    if store.repeatSchemaAvailable {
                        Toggle("Đếm số lần thực hiện", isOn: $taskDraftRepeatEnabled)
                        if taskDraftRepeatEnabled {
                            Stepper("Số lần cần làm: \(taskDraftRepeatTotal)", value: $taskDraftRepeatTotal, in: 1...999)
                        }
                    }
                }
            }
            .navigationTitle(taskDraftIsDaily ? "Công việc hằng ngày" : "Công việc mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { showingTaskEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        Task {
                            let created = await store.createTask(
                                title: taskDraftTitle,
                                notes: taskDraftNotes,
                                priority: taskDraftPriority,
                                isDaily: taskDraftIsDaily,
                                repeatEnabled: taskDraftRepeatEnabled,
                                repeatTotal: taskDraftRepeatTotal
                            )
                            if created { showingTaskEditor = false }
                        }
                    }
                    .disabled(
                        taskDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        store.isLoading ||
                        (!store.dailySchemaAvailable && taskDraftIsDaily) ||
                        (!store.repeatSchemaAvailable && taskDraftRepeatEnabled)
                    )
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func logoMark(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(Color(red: 0.208, green: 0.388, blue: 0.914))
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.54, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .indigo.opacity(isDarkMode ? 0.18 : 0.24), radius: size * 0.16, y: size * 0.09)
        .accessibilityLabel("TaskFlow")
    }

    private var todayDateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.timeZone = .current
        formatter.dateFormat = "EEEE, d MMMM"
        let value = formatter.string(from: Date())
        return value.prefix(1).uppercased() + value.dropFirst()
    }

    private var themeButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { isDarkMode.toggle() }
        } label: {
            Image(systemName: isDarkMode ? "sun.max.fill" : "moon.fill")
                .font(.headline)
                .frame(width: 42, height: 42)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13))
        }
        .accessibilityLabel(isDarkMode ? "Chuyển sang chế độ sáng" : "Chuyển sang chế độ tối")
    }

    private var selectedTasks: [TaskItem] {
        let today = Self.todayString()
        switch selectedFilter {
        case .today:
            return store.tasks.filter { $0.isDaily || (!$0.isCompleted && ($0.scheduledDate == today || $0.dueDate == today || ($0.scheduledDate == nil && $0.dueDate == nil))) }
        case .daily:
            return store.tasks.filter(\.isDaily)
        case .open:
            return store.tasks.filter { !$0.isCompleted }
        case .done:
            return store.tasks.filter(\.isCompleted)
        }
    }

    private var emptyTitle: String {
        switch selectedFilter {
        case .today: return "Hôm nay chưa có việc nào"
        case .daily: return "Chưa có việc hằng ngày"
        case .open: return "Bạn đã xử lý hết việc"
        case .done: return "Chưa có việc hoàn thành"
        }
    }

    private var emptySubtitle: String {
        switch selectedFilter {
        case .today: return "Các công việc sẽ đồng bộ từ tài khoản TaskFlow của bạn."
        case .daily: return "Đánh dấu công việc lặp lại trên web để chúng xuất hiện ở đây."
        case .open: return "Một chút nghỉ ngơi cũng rất xứng đáng."
        case .done: return "Những việc bạn tích xong sẽ xuất hiện trong mục này."
        }
    }

    private func isOverdue(_ task: TaskItem) -> Bool {
        guard let dueDate = task.dueDate else { return false }
        return dueDate < Self.todayString() && !task.isCompleted
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
