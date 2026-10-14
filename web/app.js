(() => {
  'use strict';

  const $ = (selector) => document.querySelector(selector);
  const queryAll = (selector) => Array.from(document.querySelectorAll(selector));
  const THEME_STORAGE_KEY = 'taskflow-theme';

  function readSavedTheme() {
    try {
      const saved = window.localStorage.getItem(THEME_STORAGE_KEY);
      if (saved === 'light' || saved === 'dark') return saved;
    } catch (error) {
      console.warn('Không đọc được tùy chọn giao diện:', error);
    }
    return window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }

  let activeTheme = readSavedTheme();
  document.documentElement.dataset.theme = activeTheme;

  function applyTheme(theme) {
    activeTheme = theme === 'dark' ? 'dark' : 'light';
    document.documentElement.dataset.theme = activeTheme;
    try {
      window.localStorage.setItem(THEME_STORAGE_KEY, activeTheme);
    } catch (error) {
      console.warn('Không lưu được tùy chọn giao diện:', error);
    }
    const button = $('#themeToggle');
    const icon = $('#themeIcon');
    const label = $('#themeLabel');
    const isDark = activeTheme === 'dark';
    if (button) {
      button.setAttribute('aria-pressed', String(isDark));
      button.setAttribute('aria-label', isDark ? 'Chuyển sang chế độ sáng' : 'Chuyển sang chế độ tối');
      button.title = isDark ? 'Chuyển sang chế độ sáng' : 'Chuyển sang chế độ tối';
    }
    if (icon) icon.textContent = isDark ? '☀' : '☾';
    if (label) label.textContent = isDark ? 'Sáng' : 'Tối';
  }

  const config = window.TASKFLOW_CONFIG || {};
  const configured = Boolean(config.supabaseUrl && config.supabaseAnonKey &&
    !config.supabaseUrl.includes('YOUR-PROJECT-ID') &&
    !config.supabaseAnonKey.includes('YOUR_SUPABASE'));

  let client = null;
  let currentUser = null;
  let tasks = [];
  let categories = [];
  let currentView = 'today';
  let currentCategoryId = null;
  let authMode = 'login';
  let editingTaskId = null;
  let realtimeChannel = null;
  let loadInProgress = false;
  let dailySchemaAvailable = false;
  let dailySchemaWarningShown = false;

  const viewNames = {
    today: 'Hôm nay', daily: 'Công việc hằng ngày', upcoming: 'Sắp tới',
    overdue: 'Quá hạn', all: 'Tất cả công việc', completed: 'Đã hoàn thành', stats: 'Thống kê'
  };
  const viewDescriptions = {
    today: 'Bắt đầu từ việc quan trọng nhất.',
    daily: 'Những thói quen và việc cần duy trì mỗi ngày.',
    upcoming: 'Những công việc đang chờ ở phía trước.',
    overdue: 'Những việc đã vượt quá hạn cuối.',
    all: 'Mọi công việc chưa lưu trữ của bạn.',
    completed: 'Nhìn lại những việc bạn đã hoàn thành.'
  };

  function toast(message, type = '') {
    const node = document.createElement('div');
    node.className = `toast ${type}`.trim();
    node.textContent = message;
    $('#toastRegion').appendChild(node);
    window.setTimeout(() => node.remove(), 3400);
  }

  function setSyncState(kind, label) {
    $('#syncDot').className = `sync-dot ${kind || ''}`.trim();
    $('#syncLabel').textContent = label;
  }

  function setAuthMode(mode) {
    authMode = mode;
    const signingUp = mode === 'signup';
    $('#authSubmit').textContent = signingUp ? 'Tạo tài khoản' : 'Đăng nhập';
    $('#authSwitchLabel').textContent = signingUp ? 'Đã có tài khoản?' : 'Chưa có tài khoản?';
    $('#authSwitch').textContent = signingUp ? 'Đăng nhập' : 'Tạo tài khoản';
    $('#authPassword').autocomplete = signingUp ? 'new-password' : 'current-password';
  }

  function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>"']/g, (char) => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    })[char]);
  }

  function isMissingDailyColumns(error) {
    const message = String(error?.message || error || '');
    return /is_daily|daily_completed_on/i.test(message) &&
      (/42703|PGRST204|does not exist|could not find|schema cache/i.test(`${error?.code || ''} ${message}`));
  }

  function setDailySchemaAvailable(available) {
    dailySchemaAvailable = available;
    const checkbox = $('#taskIsDaily');
    const hint = $('#dailyOptionHint');
    const schemaNotice = $('#schemaNotice');
    if (schemaNotice) schemaNotice.classList.toggle('hidden', available);
    if (checkbox) {
      checkbox.disabled = !available;
      if (!available) checkbox.checked = false;
    }
    if (hint) hint.textContent = available
      ? 'Tự bỏ đánh dấu hoàn thành khi sang ngày mới.'
      : 'Cần cập nhật Supabase để bật tính năng lặp lại hằng ngày.';
    if (available) {
      dailySchemaWarningShown = false;
    } else if (!dailySchemaWarningShown) {
      toast('Cơ sở dữ liệu chưa có cột công việc hằng ngày. Mở supabase/daily_tasks_migration.sql trong GitHub, sao chép câu lệnh vào Supabase → SQL Editor → Run. Các công việc hiện có vẫn dùng được.', 'error');
      dailySchemaWarningShown = true;
    }
  }

  function todayString() {
    const now = new Date();
    return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
  }

  function addDays(dateString, amount) {
    const [year, month, day] = dateString.split('-').map(Number);
    const date = new Date(year, month - 1, day);
    date.setDate(date.getDate() + amount);
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  }

  function formatDate(value) {
    if (!value) return '';
    const [year, month, day] = value.split('-').map(Number);
    return new Intl.DateTimeFormat('vi-VN', { day: 'numeric', month: 'short' }).format(new Date(year, month - 1, day));
  }

  function formatLongDate(date = new Date()) {
    return new Intl.DateTimeFormat('vi-VN', { weekday: 'long', day: 'numeric', month: 'long' }).format(date);
  }

  function getCategory(categoryId) {
    return categories.find((item) => item.id === categoryId) || null;
  }

  function countDate(date, field = 'scheduled_date') {
    return tasks.filter((task) => !task.is_completed && !task.archived_at && task[field] === date).length;
  }

  function isOverdue(task) {
    return !task.is_completed && task.due_date && task.due_date < todayString();
  }

  function taskMatchesView(task) {
    const today = todayString();
    if (currentView.startsWith('category:')) return task.category_id === currentCategoryId && !task.is_completed;
    switch (currentView) {
      case 'today': return !task.is_completed && (task.is_daily || task.scheduled_date === today || task.due_date === today || (!task.scheduled_date && !task.due_date));
      case 'daily': return Boolean(task.is_daily);
      case 'upcoming': return !task.is_completed && ((task.scheduled_date && task.scheduled_date > today) || (!task.scheduled_date && task.due_date && task.due_date > today));
      case 'overdue': return !task.is_completed && Boolean(task.due_date && task.due_date < today);
      case 'completed': return task.is_completed;
      case 'all': return !task.is_completed;
      default: return !task.is_completed;
    }
  }

  function visibleTasks() {
    const query = $('#searchInput').value.trim().toLocaleLowerCase('vi');
    const categoryFilter = $('#filterCategory').value;
    const priorityFilter = $('#filterPriority').value;
    const selected = tasks.filter((task) => {
      if (task.archived_at) return false;
      if (!taskMatchesView(task)) return false;
      if (categoryFilter && task.category_id !== categoryFilter) return false;
      if (priorityFilter && task.priority !== priorityFilter) return false;
      if (query && !`${task.title} ${task.notes || ''} ${(getCategory(task.category_id) || {}).name || ''}`.toLocaleLowerCase('vi').includes(query)) return false;
      return true;
    });
    const mode = $('#sortSelect').value;
    selected.sort((a, b) => {
      if (mode === 'priority') {
        const score = { high: 0, normal: 1, low: 2 };
        return score[a.priority] - score[b.priority] || Number(a.position || 0) - Number(b.position || 0);
      }
      if (mode === 'due') return (a.due_date || '9999-12-31').localeCompare(b.due_date || '9999-12-31') || Number(a.position || 0) - Number(b.position || 0);
      if (mode === 'newest') return String(b.created_at || '').localeCompare(String(a.created_at || ''));
      return Number(a.position || 0) - Number(b.position || 0) || String(b.created_at || '').localeCompare(String(a.created_at || ''));
    });
    return selected;
  }

  function renderStatsStrip() {
    const visible = tasks.filter((task) => !task.archived_at);
    const completed = visible.filter((task) => task.is_completed).length;
    const pending = visible.length - completed;
    const rate = visible.length ? Math.round(completed / visible.length * 100) : 0;
    $('#totalStat').textContent = visible.length;
    $('#completedStat').textContent = completed;
    $('#pendingStat').textContent = pending;
    $('#rateStat').textContent = `${rate}%`;
    $('#rateBar').style.width = `${rate}%`;
    $('#todayCount').textContent = tasks.filter((task) => !task.is_completed && !task.archived_at && (task.is_daily || task.scheduled_date === todayString() || task.due_date === todayString() || (!task.scheduled_date && !task.due_date))).length;
    const dailyCount = $('#dailyCount');
    if (dailyCount) dailyCount.textContent = tasks.filter((task) => task.is_daily && !task.is_completed && !task.archived_at).length;
    $('#overdueCount').textContent = visible.filter(isOverdue).length;
    $('#completedNote').textContent = completed ? 'Đang có tiến triển tốt' : 'Mỗi việc nhỏ đều đáng kể';
  }

  function renderCategorySelects() {
    const makeOptions = (firstLabel) => `<option value="">${firstLabel}</option>` + categories.map((category) =>
      `<option value="${escapeHtml(category.id)}">${escapeHtml(category.name)}</option>`).join('');
    const currentTaskValue = $('#taskCategory').value;
    const currentFilterValue = $('#filterCategory').value;
    $('#taskCategory').innerHTML = makeOptions('Chưa phân loại');
    $('#filterCategory').innerHTML = makeOptions('Tất cả danh mục');
    if (categories.some((category) => category.id === currentTaskValue)) $('#taskCategory').value = currentTaskValue;
    if (categories.some((category) => category.id === currentFilterValue)) $('#filterCategory').value = currentFilterValue;
    $('#categoryList').innerHTML = categories.map((category) => {
      const count = tasks.filter((task) => task.category_id === category.id && !task.is_completed && !task.archived_at).length;
      const active = currentView === `category:${category.id}` ? ' active' : '';
      return `<div class="category-row-wrap"><button class="category-row${active}" data-category="${escapeHtml(category.id)}" title="Mở danh mục ${escapeHtml(category.name)}"><span class="category-dot" style="background:${escapeHtml(category.color)}"></span><span class="cat-name">${escapeHtml(category.name)}</span><span class="cat-count">${count}</span></button><button class="category-remove" data-delete-category="${escapeHtml(category.id)}" title="Xóa danh mục" aria-label="Xóa danh mục ${escapeHtml(category.name)}">×</button></div>`;
    }).join('');
  }

  function renderTaskRows() {
    const filtered = visibleTasks();
    $('#taskCountLabel').textContent = `${filtered.length} công việc`;
    $('#taskList').innerHTML = filtered.map((task) => {
      const category = getCategory(task.category_id);
      const priorityLabel = { high: 'Ưu tiên cao', normal: 'Bình thường', low: 'Ưu tiên thấp' }[task.priority] || 'Bình thường';
      const dateBits = [];
      if (task.scheduled_date) dateBits.push(`<span class="meta-pill">◷ Dự định ${escapeHtml(formatDate(task.scheduled_date))}</span>`);
      if (task.due_date) {
        let klass = 'meta-pill';
        let prefix = 'Hạn';
        if (isOverdue(task)) { klass += ' due-overdue'; prefix = 'Quá hạn'; }
        else if (!task.is_completed && task.due_date === todayString()) { klass += ' due-today'; prefix = 'Hạn hôm nay'; }
        dateBits.push(`<span class="${klass}">▦ ${prefix} ${escapeHtml(formatDate(task.due_date))}</span>`);
      }
      const notes = task.notes ? `<div class="task-notes">${escapeHtml(task.notes)}</div>` : '';
      const categoryBit = category ? `<span class="meta-pill category-pill"><span class="category-dot" style="background:${escapeHtml(category.color)}"></span>${escapeHtml(category.name)}</span>` : '';
      return `<article class="task-row${task.is_completed ? ' completed' : ''}" data-task-row="${escapeHtml(task.id)}">
        <input class="task-check" type="checkbox" data-toggle-task="${escapeHtml(task.id)}" ${task.is_completed ? 'checked' : ''} aria-label="${task.is_completed ? 'Bỏ hoàn thành' : 'Đánh dấu hoàn thành'}: ${escapeHtml(task.title)}">
        <div class="task-main"><div class="task-title">${escapeHtml(task.title)}</div>${notes}<div class="task-meta">${categoryBit}${dateBits.join('')}<span class="meta-pill"><span class="priority-dot ${escapeHtml(task.priority)}"></span>${priorityLabel}</span></div></div>
        <div class="task-actions"><button class="icon-button edit-action" data-edit-task="${escapeHtml(task.id)}" title="Sửa công việc" aria-label="Sửa công việc">✎</button><button class="icon-button" data-delete-task="${escapeHtml(task.id)}" title="Xóa công việc" aria-label="Xóa công việc">×</button></div>
      </article>`;
    }).join('');
    const empty = filtered.length === 0;
    $('#emptyState').classList.toggle('hidden', !empty);
    $('#taskList').classList.toggle('hidden', empty);
    if (empty) {
      $('#emptyTitle').textContent = $('#searchInput').value.trim() ? 'Không tìm thấy công việc' : (currentView === 'completed' ? 'Chưa có việc nào hoàn thành' : 'Danh sách đang trống');
      $('#emptyText').textContent = $('#searchInput').value.trim() ? 'Thử từ khóa khác hoặc xóa bớt bộ lọc.' : (currentView === 'completed' ? 'Những việc đã tích xong sẽ xuất hiện ở đây.' : 'Bạn có thể tạo việc mới hoặc chọn một danh sách khác.');
      $('#emptyCreateBtn').classList.toggle('hidden', currentView === 'completed' || currentView.startsWith('category:'));
    }
    const activeFilters = Boolean($('#filterCategory').value || $('#filterPriority').value);
    $('#activeFilterLabel').classList.toggle('hidden', !activeFilters);
    $('#activeFilterLabel').textContent = activeFilters ? 'Đang áp dụng bộ lọc' : '';
  }

  function renderStatsPage() {
    const visible = tasks.filter((task) => !task.archived_at);
    const completed = visible.filter((task) => task.is_completed);
    const pending = visible.filter((task) => !task.is_completed);
    const overdue = pending.filter(isOverdue);
    const rate = visible.length ? Math.round(completed.length / visible.length * 100) : 0;
    $('#statsSummary').innerHTML = [
      ['Tổng số việc', visible.length, 'Công việc đang lưu'],
      ['Đã hoàn thành', completed.length, 'Đã tích xong'],
      ['Quá hạn', overdue.length, 'Cần xem lại'],
      ['Tỷ lệ hoàn thành', `${rate}%`, 'Trên tổng số việc']
    ].map(([label, number, note]) => `<div class="summary-card"><strong>${number}</strong><span>${label}</span><span>${note}</span></div>`).join('');

    const today = todayString();
    const days = Array.from({ length: 7 }, (_, index) => addDays(today, index - 6));
    const chartCounts = days.map((day) => completed.filter((task) => task.completed_at && task.completed_at.slice(0, 10) === day).length);
    const maximum = Math.max(1, ...chartCounts);
    $('#weeklyChart').innerHTML = days.map((day, index) => {
      const [year, month, d] = day.split('-').map(Number);
      const label = new Intl.DateTimeFormat('vi-VN', { weekday: 'short' }).format(new Date(year, month - 1, d));
      const height = Math.max(3, chartCounts[index] / maximum * 100);
      return `<div class="chart-col"><div class="chart-track"><span class="chart-bar" style="height:${height}%"></span></div><span class="chart-number">${chartCounts[index]}</span><span class="chart-label">${escapeHtml(label)}</span></div>`;
    }).join('');

    $('#categoryStats').innerHTML = categories.length ? categories.map((category) => {
      const inCategory = visible.filter((task) => task.category_id === category.id);
      const done = inCategory.filter((task) => task.is_completed).length;
      const percent = inCategory.length ? Math.round(done / inCategory.length * 100) : 0;
      return `<div><div class="category-stat-head"><span class="category-stat-name"><span class="category-dot" style="background:${escapeHtml(category.color)}"></span>${escapeHtml(category.name)}</span><span class="category-stat-count">${done}/${inCategory.length} · ${percent}%</span></div><div class="category-track"><span style="width:${percent}%;background:${escapeHtml(category.color)}"></span></div></div>`;
    }).join('') : '<p class="muted small-text">Tạo danh mục để xem thống kê theo nhóm.</p>';
  }

  function render() {
    if (!currentUser) return;
    const activeCategory = currentView.startsWith('category:') ? getCategory(currentCategoryId) : null;
    const label = activeCategory ? activeCategory.name : (viewNames[currentView] || 'Hôm nay');
    queryAll('.nav-item').forEach((button) => button.classList.toggle('active', button.dataset.view === currentView));
    queryAll('.category-row').forEach((button) => button.classList.toggle('active', button.dataset.category === currentCategoryId && currentView.startsWith('category:')));
    $('#currentViewLabel').textContent = label;
    $('#pageTitle').textContent = label;
    $('#pageSubtitle').textContent = activeCategory ? `Các công việc trong danh mục ${activeCategory.name}.` : (viewDescriptions[currentView] || 'Bắt đầu từ việc quan trọng nhất.');
    $('#taskView').classList.toggle('hidden', currentView === 'stats');
    $('#statsView').classList.toggle('hidden', currentView !== 'stats');
    $('#statsStrip').classList.toggle('hidden', currentView === 'completed');
    renderStatsStrip();
    renderCategorySelects();
    renderTaskRows();
    renderStatsPage();
    $('#lastUpdated').textContent = `Cập nhật ${new Intl.DateTimeFormat('vi-VN', { hour: '2-digit', minute: '2-digit' }).format(new Date())}`;
  }

  async function ensureDefaultCategories() {
    if (categories.length) return;
    const defaults = [
      { user_id: currentUser.id, name: 'Học tập', color: '#7c83ee', position: 0 },
      { user_id: currentUser.id, name: 'Lập trình', color: '#2fa58a', position: 1 },
      { user_id: currentUser.id, name: 'Cá nhân', color: '#e6a84b', position: 2 }
    ];
    const { error } = await client.from('categories').insert(defaults);
    if (error) console.warn('Không tạo được danh mục mặc định:', error.message);
    const result = await client.from('categories').select('*').order('position').order('name');
    if (!result.error) categories = result.data || [];
  }

  async function loadAll({ silent = false } = {}) {
    if (!currentUser || loadInProgress) return;
    loadInProgress = true;
    setSyncState('', 'Đang đồng bộ…');
    try {
      const [categoryResult, queriedTaskResult] = await Promise.all([
        client.from('categories').select('*').eq('user_id', currentUser.id).order('position').order('name'),
        client.from('tasks').select('id,user_id,title,notes,category_id,scheduled_date,due_date,priority,is_completed,completed_at,is_daily,daily_completed_on,position,archived_at,created_at,updated_at').eq('user_id', currentUser.id).is('archived_at', null).order('position', { ascending: true }).order('created_at', { ascending: false })
      ]);
      if (categoryResult.error) throw categoryResult.error;
      let taskResult = queriedTaskResult;
      if (taskResult.error && isMissingDailyColumns(taskResult.error)) {
        setDailySchemaAvailable(false);
        taskResult = await client.from('tasks').select('id,user_id,title,notes,category_id,scheduled_date,due_date,priority,is_completed,completed_at,position,archived_at,created_at,updated_at').eq('user_id', currentUser.id).is('archived_at', null).order('position', { ascending: true }).order('created_at', { ascending: false });
      } else if (!taskResult.error) {
        setDailySchemaAvailable(true);
      }
      if (taskResult.error) throw taskResult.error;
      categories = categoryResult.data || [];
      tasks = (taskResult.data || []).map((task) => ({
        ...task,
        is_daily: dailySchemaAvailable ? Boolean(task.is_daily) : false,
        daily_completed_on: dailySchemaAvailable ? task.daily_completed_on : null,
        is_completed: dailySchemaAvailable && task.is_daily
          ? task.daily_completed_on === todayString()
          : task.is_completed
      }));
      if (!categories.length) await ensureDefaultCategories();
      setSyncState('online', 'Đã đồng bộ');
      render();
    } catch (error) {
      console.error(error);
      setSyncState('error', 'Lỗi đồng bộ');
      if (!silent) toast(error.message || 'Không tải được dữ liệu. Kiểm tra kết nối và cấu hình Supabase.', 'error');
    } finally {
      loadInProgress = false;
    }
  }

  function subscribeRealtime() {
    if (!client || !currentUser) return;
    if (realtimeChannel) client.removeChannel(realtimeChannel);
    realtimeChannel = client.channel(`taskflow-${currentUser.id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'tasks', filter: `user_id=eq.${currentUser.id}` }, () => loadAll({ silent: true }))
      .on('postgres_changes', { event: '*', schema: 'public', table: 'categories', filter: `user_id=eq.${currentUser.id}` }, () => loadAll({ silent: true }))
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') setSyncState('online', 'Đồng bộ trực tiếp');
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') setSyncState('error', 'Đồng bộ dự phòng');
      });
  }

  async function enterApp(user) {
    currentUser = user;
    $('#authScreen').classList.add('hidden');
    $('#appShell').classList.remove('hidden');
    $('#accountEmail').textContent = user.email || 'Tài khoản';
    $('#avatarInitial').textContent = (user.email || 'T').slice(0, 1).toLocaleUpperCase('vi');
    await loadAll();
    subscribeRealtime();
  }

  async function leaveApp() {
    if (realtimeChannel && client) await client.removeChannel(realtimeChannel);
    realtimeChannel = null;
    currentUser = null;
    tasks = [];
    categories = [];
    $('#appShell').classList.add('hidden');
    $('#authScreen').classList.remove('hidden');
    $('#sidebar').classList.remove('open');
  }

  function setView(view, categoryId = null) {
    currentView = view;
    currentCategoryId = categoryId;
    $('#filterCategory').value = '';
    $('#filterPriority').value = '';
    $('#searchInput').value = '';
    render();
    $('#sidebar').classList.remove('open');
  }

  function openTaskDialog(task = null) {
    editingTaskId = task ? task.id : null;
    $('#taskDialogTitle').textContent = task ? 'Chỉnh sửa công việc' : 'Tạo công việc';
    $('#taskTitle').value = task?.title || '';
    $('#taskNotes').value = task?.notes || '';
    $('#taskCategory').value = task?.category_id || '';
    $('#taskPriority').value = task?.priority || 'normal';
    $('#taskScheduledDate').value = task?.scheduled_date || (currentView === 'today' ? todayString() : '');
    $('#taskIsDaily').checked = Boolean(task?.is_daily);
    $('#taskDueDate').value = task?.due_date || '';
    $('#saveTaskBtn').textContent = task ? 'Lưu thay đổi' : 'Lưu công việc';
    $('#taskDialog').showModal();
    window.setTimeout(() => $('#taskTitle').focus(), 40);
  }

  async function saveTask(event) {
    event.preventDefault();
    const title = $('#taskTitle').value.trim();
    if (!title) return;
    const payload = {
      title,
      notes: $('#taskNotes').value.trim(),
      category_id: $('#taskCategory').value || null,
      scheduled_date: $('#taskScheduledDate').value || null,
      due_date: $('#taskDueDate').value || null,
      priority: $('#taskPriority').value,
      user_id: currentUser.id
    };
    const existingTask = editingTaskId ? tasks.find((task) => task.id === editingTaskId) : null;
    if (dailySchemaAvailable) {
      payload.is_daily = $('#taskIsDaily').checked;
      if (existingTask && Boolean(existingTask.is_daily) !== payload.is_daily) {
        payload.is_completed = false;
        payload.completed_at = null;
        payload.daily_completed_on = null;
      }
    }
    if (!editingTaskId) payload.position = tasks.length ? Math.min(...tasks.map((task) => Number(task.position || 0))) - 1 : 0;
    $('#saveTaskBtn').disabled = true;
    try {
      let result;
      if (editingTaskId) result = await client.from('tasks').update(payload).eq('id', editingTaskId).eq('user_id', currentUser.id);
      else result = await client.from('tasks').insert(payload);
      if (result.error) throw result.error;
      $('#taskDialog').close();
      toast(editingTaskId ? 'Đã cập nhật công việc.' : 'Đã tạo công việc.', 'success');
      await loadAll({ silent: true });
    } catch (error) {
      toast(error.message || 'Không lưu được công việc.', 'error');
    } finally {
      $('#saveTaskBtn').disabled = false;
    }
  }

  async function toggleTask(taskId, checked) {
    const task = tasks.find((item) => item.id === taskId);
    if (!task) return;
    const box = document.querySelector(`[data-toggle-task="${CSS.escape(taskId)}"]`);
    if (box) box.disabled = true;
    try {
      const { error } = await client.from('tasks').update({
        is_completed: checked,
        completed_at: checked ? new Date().toISOString() : null,
        ...(dailySchemaAvailable && task.is_daily ? { daily_completed_on: checked ? todayString() : null } : {})
      }).eq('id', taskId).eq('user_id', currentUser.id);
      if (error) throw error;
      toast(checked ? 'Đã hoàn thành. Tốt lắm!' : 'Đã bỏ đánh dấu hoàn thành.', 'success');
      await loadAll({ silent: true });
    } catch (error) {
      toast(error.message || 'Không cập nhật được trạng thái.', 'error');
      if (box) { box.checked = !checked; box.disabled = false; }
    }
  }

  async function deleteTask(taskId) {
    const task = tasks.find((item) => item.id === taskId);
    if (!task || !window.confirm(`Xóa công việc “${task.title}”? Thao tác này không thể hoàn tác.`)) return;
    try {
      const { error } = await client.from('tasks').delete().eq('id', taskId).eq('user_id', currentUser.id);
      if (error) throw error;
      toast('Đã xóa công việc.', 'success');
      await loadAll({ silent: true });
    } catch (error) {
      toast(error.message || 'Không xóa được công việc.', 'error');
    }
  }

  async function createCategory(event) {
    event.preventDefault();
    const name = $('#categoryName').value.trim();
    if (!name) return;
    try {
      const { error } = await client.from('categories').insert({
        user_id: currentUser.id, name, color: $('#categoryColor').value,
        position: categories.length ? Math.max(...categories.map((item) => item.position || 0)) + 1 : 0
      });
      if (error) throw error;
      $('#categoryDialog').close();
      $('#categoryForm').reset();
      $('#categoryColor').value = '#64748b';
      toast('Đã tạo danh mục.', 'success');
      await loadAll({ silent: true });
    } catch (error) {
      toast(error.code === '23505' ? 'Danh mục này đã tồn tại.' : (error.message || 'Không tạo được danh mục.'), 'error');
    }
  }

  async function deleteCategory(categoryId) {
    const category = getCategory(categoryId);
    if (!category || !window.confirm(`Xóa danh mục “${category.name}”? Các công việc bên trong sẽ vẫn được giữ lại và chuyển thành chưa phân loại.`)) return;
    try {
      const { error } = await client.from('categories').delete().eq('id', categoryId).eq('user_id', currentUser.id);
      if (error) throw error;
      if (currentCategoryId === categoryId) setView('all');
      toast('Đã xóa danh mục.', 'success');
      await loadAll({ silent: true });
    } catch (error) {
      toast(error.message || 'Không xóa được danh mục.', 'error');
    }
  }

  function bindEvents() {
    $('#authSwitch').addEventListener('click', () => setAuthMode(authMode === 'login' ? 'signup' : 'login'));
    $('#authForm').addEventListener('submit', async (event) => {
      event.preventDefault();
      if (!client) return;
      const email = $('#authEmail').value.trim();
      const password = $('#authPassword').value;
      $('#authSubmit').disabled = true;
      $('#authSubmit').textContent = authMode === 'signup' ? 'Đang tạo…' : 'Đang đăng nhập…';
      try {
        const result = authMode === 'signup'
          ? await client.auth.signUp({ email, password })
          : await client.auth.signInWithPassword({ email, password });
        if (result.error) throw result.error;
        if (result.data.session && result.data.user) {
          await enterApp(result.data.user);
          toast(authMode === 'signup' ? 'Đã tạo tài khoản.' : 'Đăng nhập thành công.', 'success');
        } else if (authMode === 'signup') {
          toast('Đã tạo tài khoản. Hãy mở email để xác nhận, sau đó đăng nhập.');
          setAuthMode('login');
        } else {
          throw new Error('Không tạo được phiên đăng nhập. Hãy kiểm tra email và mật khẩu.');
        }
      } catch (error) {
        toast(error.message || 'Không đăng nhập được.', 'error');
      } finally {
        $('#authSubmit').disabled = false;
        $('#authSubmit').textContent = authMode === 'signup' ? 'Tạo tài khoản' : 'Đăng nhập';
      }
    });
    const performLogout = async () => {
      if (!client) return;
      const button = $('#logoutTopBtn');
      if (button) button.disabled = true;
      try {
        const { error } = await client.auth.signOut();
        if (error) throw error;
        await leaveApp();
        toast('Đã đăng xuất khỏi TaskFlow.', 'success');
      } catch (error) {
        toast(error.message || 'Không đăng xuất được. Thử lại nhé.', 'error');
      } finally {
        if (button) button.disabled = false;
      }
    };
    $('#logoutBtn').addEventListener('click', performLogout);
    $('#logoutTopBtn').addEventListener('click', performLogout);
    $('#themeToggle').addEventListener('click', () => applyTheme(activeTheme === 'dark' ? 'light' : 'dark'));
    applyTheme(activeTheme);
    queryAll('.nav-item').forEach((button) => button.addEventListener('click', () => setView(button.dataset.view)));
    $('#categoryList').addEventListener('click', (event) => {
      const deleteButton = event.target.closest('[data-delete-category]');
      if (deleteButton) { event.stopPropagation(); deleteCategory(deleteButton.dataset.deleteCategory); return; }
      const button = event.target.closest('[data-category]');
      if (button) setView(`category:${button.dataset.category}`, button.dataset.category);
    });
    const addTask = () => openTaskDialog();
    $('#newTaskBtn').addEventListener('click', addTask);
    $('#headingNewTaskBtn').addEventListener('click', addTask);
    $('#emptyCreateBtn').addEventListener('click', addTask);
    $('#taskForm').addEventListener('submit', saveTask);
    $('#categoryForm').addEventListener('submit', createCategory);
    $('#addCategoryBtn').addEventListener('click', () => $('#categoryDialog').showModal());
    queryAll('[data-close]').forEach((button) => button.addEventListener('click', () => $(`#${button.dataset.close}`).close()));
    $('#taskList').addEventListener('change', (event) => {
      const checkbox = event.target.closest('[data-toggle-task]');
      if (checkbox) toggleTask(checkbox.dataset.toggleTask, checkbox.checked);
    });
    $('#taskList').addEventListener('click', (event) => {
      const edit = event.target.closest('[data-edit-task]');
      if (edit) { const task = tasks.find((item) => item.id === edit.dataset.editTask); if (task) openTaskDialog(task); return; }
      const del = event.target.closest('[data-delete-task]');
      if (del) deleteTask(del.dataset.deleteTask);
    });
    $('#searchInput').addEventListener('input', renderTaskRows);
    $('#sortSelect').addEventListener('change', renderTaskRows);
    $('#filterToggle').addEventListener('click', () => $('#filterPanel').classList.toggle('hidden'));
    $('#filterCategory').addEventListener('change', renderTaskRows);
    $('#filterPriority').addEventListener('change', renderTaskRows);
    $('#clearFiltersBtn').addEventListener('click', () => { $('#filterCategory').value = ''; $('#filterPriority').value = ''; renderTaskRows(); });
    $('#refreshBtn').addEventListener('click', () => loadAll());
    $('#mobileMenuBtn').addEventListener('click', () => $('#sidebar').classList.toggle('open'));
    document.addEventListener('click', (event) => {
      if (window.innerWidth <= 760 && $('#sidebar').classList.contains('open') && !event.target.closest('#sidebar') && !event.target.closest('#mobileMenuBtn')) $('#sidebar').classList.remove('open');
    });
    document.addEventListener('keydown', (event) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') { event.preventDefault(); $('#searchInput').focus(); }
      if (event.key === 'Escape') $('#sidebar').classList.remove('open');
    });
  }

  async function init() {
    bindEvents();
    $('#pageSubtitle').textContent = formatLongDate();
    if (!configured || !window.supabase?.createClient) {
      $('#configWarning').classList.remove('hidden');
      $('#configWarning').textContent = 'Cần cấu hình Supabase trước khi đăng nhập. Mở web/config.js và thay Project URL cùng publishable/anon key theo README.md.';
      $('#authSubmit').disabled = true;
      $('#authSwitch').disabled = true;
      return;
    }
    client = window.supabase.createClient(config.supabaseUrl, config.supabaseAnonKey, {
      auth: {
        storage: window.localStorage,
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true
      }
    });

    // Khôi phục giao diện khi Supabase nạp phiên đã lưu hoặc làm mới token.
    client.auth.onAuthStateChange((event, session) => {
      if (event !== 'SIGNED_IN' && event !== 'TOKEN_REFRESHED' && event !== 'USER_UPDATED') return;
      const user = session?.user;
      if (!user || user.id === currentUser?.id) return;
      queueMicrotask(() => {
        if (client && currentUser?.id !== user.id) void enterApp(user);
      });
    });

    const { data, error } = await client.auth.getSession();
    if (error) console.warn('Không đọc được phiên đăng nhập:', error.message);
    if (data?.session?.user) await enterApp(data.session.user);
  }

  document.addEventListener('DOMContentLoaded', init);
})();
