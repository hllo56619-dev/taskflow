# TaskFlow — Quản lý công việc trên Mac, Android và iPhone

TaskFlow là bộ ứng dụng cá nhân gồm hai phần dùng chung dữ liệu Supabase:

- **Trên Mac (web):** tạo, sửa, xóa, phân loại, tìm kiếm, lọc, sắp xếp công việc và xem thống kê.
- **Trên Android (app Kotlin native):** đăng nhập, xem danh sách và tích/bỏ tích hoàn thành. Điện thoại không có chức năng tạo hay chỉnh sửa note.
- **Đồng bộ:** web dùng Supabase Realtime; Android tải lại khi mở app, khi bấm nút làm mới và tự kiểm tra dữ liệu mỗi 30 giây khi đang mở.
- **Tạo APK trên cloud:** GitHub Actions sẽ biên dịch app Android trên máy chủ của GitHub. Minh không cần cài Android Studio hay Android SDK trên Mac.

## Phiên bản đầu có gì?

- Đăng nhập/tạo tài khoản bằng email và mật khẩu qua Supabase Auth.
- Dữ liệu từng tài khoản được bảo vệ bằng Row Level Security (RLS).
- Danh mục, ghi chú, ngày dự định làm, hạn cuối và độ ưu tiên.
- Các mục trên web: Hôm nay, Ngày mai, Sắp tới, Quá hạn, Tất cả việc, Đã hoàn thành, Thống kê và từng danh mục.
- Tìm kiếm, bộ lọc danh mục/độ ưu tiên, sắp xếp và thống kê tỷ lệ hoàn thành.
- App Android có ba tab: Hôm nay, Chưa xong, Đã xong.
- APK debug có thể tải trong trang Actions của GitHub.

## Phần mềm cần cài trên Mac

**Không cần cài Android Studio, Xcode hoặc Android SDK.** Hướng dẫn sử dụng trình duyệt và Terminal. Git dùng để tải mã nguồn lên GitHub; kiểm tra bằng lệnh `git --version`. Trình duyệt tải thư viện Supabase từ CDN, không cần cài thêm gói JavaScript ở máy.

Nếu Terminal báo `git: command not found`, hãy dừng lại và nhắn mình trước khi cài thêm bất kỳ thứ gì. Có thể chuyển sang cách tải mã nguồn qua trình duyệt, nhưng cách đó sẽ nhiều thao tác hơn.

---

# Hướng dẫn cài đặt từng bước

## Bước 1 — Tạo dự án Supabase

1. Mở [supabase.com](https://supabase.com), đăng nhập hoặc tạo tài khoản.
2. Tạo một project mới. Lưu mật khẩu database mà Supabase yêu cầu.
3. Chờ project được tạo xong.
4. Mở file `supabase/schema.sql` trong bộ mã nguồn này bằng TextEdit (nếu dùng TextEdit, chọn **Format → Make Plain Text**). Sao chép toàn bộ nội dung.
5. Trong trang Supabase, mở **SQL Editor → New query**, dán toàn bộ SQL vào và bấm **Run**.
6. Mở phần cài đặt API của project, thường nằm ở **Project Settings → API Keys** hoặc mục **API**. Lấy hai thông tin:
   - **Project URL** — địa chỉ project, dạng `https://ten-project.supabase.co`;
   - **Publishable key** — bắt đầu bằng `sb_publishable_...`. Legacy `anon` key cũng được hỗ trợ.

**Nếu bạn đã có TaskFlow từ trước:** khi dùng tính năng *Công việc hằng ngày*, hãy mở `supabase/daily_tasks_migration.sql`, sao chép toàn bộ câu lệnh vào **Supabase → SQL Editor → New query**, rồi bấm **Run** một lần. Lệnh này bổ sung cột còn thiếu mà không xóa công việc hiện có.

**Cảnh báo quan trọng:** tuyệt đối không dùng `service_role` key hay secret key trong web/app. Publishable/anon key được thiết kế để dùng phía client; RLS trong SQL mới là lớp hạn chế mỗi tài khoản chỉ truy cập dữ liệu của chính mình.

### Email xác nhận

Tùy cài đặt Supabase, tài khoản mới có thể phải xác nhận email trước khi đăng nhập. Nếu vậy, mở email xác nhận trước rồi mới đăng nhập trong TaskFlow. Với project dùng lâu dài, nên giữ email confirmation bật.

## Bước 2 — Điền URL và key vào hai file

Cần điền **cùng một Project URL và publishable/anon key** vào cả hai file này:

1. `web/config.js`
2. `android/app/src/main/java/com/minh/taskflow/AppConfig.kt`

Ví dụ cho file `web/config.js` (đây chỉ là giá trị minh họa, không phải key thật):

```js
window.TASKFLOW_CONFIG = {
  supabaseUrl: "https://ten-project.supabase.co",
  supabaseAnonKey: "sb_publishable_key-cua-ban"
};
```

Ví dụ cho file `AppConfig.kt`:

```kotlin
object AppConfig {
    const val SUPABASE_URL = "https://ten-project.supabase.co"
    const val SUPABASE_ANON_KEY = "sb_publishable_key-cua-ban"
}
```

### Cách sửa file bằng Terminal, không cài phần mềm mới

Sau khi giải nén project, mở Terminal và chuyển vào thư mục project. Nếu nằm trong Downloads, thường dùng:

```bash
cd ~/Downloads/taskflow-project
nano web/config.js
```

Trong `nano`, sửa hai giá trị mẫu thành thông tin Supabase. Lưu bằng **Control + O**, bấm **Return**, rồi thoát bằng **Control + X**.

Tiếp tục sửa file Android:

```bash
nano android/app/src/main/java/com/minh/taskflow/AppConfig.kt
```

Làm tương tự, lưu lại và thoát. Không thêm dấu ngoặc hoặc dấu cách vào đầu/cuối URL hay key. Không dùng dấu nháy cong; giữ nguyên dấu nháy thẳng `"`.

## Bước 3 — Đưa mã nguồn lên GitHub

1. Mở [github.com/new](https://github.com/new) và tạo repository tên `taskflow`.
2. Với tài khoản GitHub Free, cách đơn giản nhất thường là chọn **Public**, vì GitHub Pages miễn phí thường yêu cầu repository công khai. Bộ mã nguồn chỉ chứa publishable/anon key, không có secret key. Nếu gói GitHub của Minh hỗ trợ Pages cho repository Private, có thể chọn Private.
3. Giải nén file ZIP này. Trong Terminal, chạy các lệnh sau từ thư mục `taskflow-project`:

   ```bash
   git --version
   git init -b main
   git add .
   git commit -m "Initial TaskFlow app"
   git remote add origin https://github.com/TEN-GITHUB-CUA-BAN/taskflow.git
   git push -u origin main
   ```

   Thay `TEN-GITHUB-CUA-BAN` bằng tên tài khoản GitHub của Minh. Khi `git push`, GitHub có thể yêu cầu đăng nhập/ủy quyền trên trình duyệt.

4. Trên GitHub, vào repository vừa tạo → **Settings → Pages** → phần Build and deployment, chọn **GitHub Actions** làm nguồn deploy.

Sau khi push mã nguồn, GitHub sẽ tự chạy hai workflow:

- **Deploy TaskFlow web app**: xuất bản trang web trong thư mục `web`.
- **Build Android APK**: biên dịch ứng dụng Kotlin trên máy chủ cloud.

Nếu workflow deploy web lỗi ở lần đầu vì Pages chưa được bật, hãy chọn GitHub Actions trong Settings → Pages rồi vào tab Actions, mở workflow **Deploy TaskFlow web app** và bấm **Run workflow** để chạy lại.

## Bước 4 — Mở web quản lý trên Mac

1. Trên GitHub, mở repository → tab **Actions**.
2. Chọn lần chạy mới nhất của **Deploy TaskFlow web app**, đợi trạng thái thành công.
3. Mở **Settings → Pages** để xem địa chỉ web được xuất bản. Mở URL đó trong Safari hoặc Chrome.
4. Quay lại Supabase → **Authentication → URL Configuration** và đặt **Site URL** bằng đúng URL web vừa xuất bản. Việc này giúp đường dẫn xác nhận email quay về đúng trang TaskFlow.
5. Tạo tài khoản và đăng nhập. Khi tài khoản chưa có danh mục nào, web sẽ tự tạo ba danh mục gợi ý: Học tập, Lập trình và Cá nhân.

### Chạy thử web trên Mac mà không deploy

Sau khi điền `web/config.js`, có thể chạy máy chủ tĩnh có sẵn trong Python của macOS:

```bash
cd ~/Downloads/taskflow-project/web
python3 -m http.server 8000
```

Mở `http://localhost:8000` trên trình duyệt. Dừng server bằng **Control + C**. Cách này chỉ chạy web cục bộ; Supabase vẫn cần Internet. Không cần cài Node package.

## Bước 5 — Tải APK và cài lên Android

1. Trên GitHub, vào tab **Actions**.
2. Mở lần chạy mới nhất của **Build Android APK** và đợi trạng thái hoàn thành thành công.
3. Cuộn xuống phần **Artifacts**, tải `TaskFlow-debug-APK`. GitHub tải về một file ZIP.
4. Giải nén ZIP; bên trong có file `app-debug.apk`.
5. Chuyển APK sang điện thoại Android bằng cáp USB, Drive hoặc cách Minh thường dùng, rồi mở file APK trên điện thoại.
6. Android có thể yêu cầu cho phép cài ứng dụng từ ứng dụng đang mở file (ví dụ Chrome hoặc Files). Cho phép cho lần cài này rồi tiếp tục cài đặt.
7. Mở TaskFlow và đăng nhập bằng đúng email/mật khẩu đã dùng trên web.

APK này là **debug build để thử nghiệm cá nhân**, không phải bản phát hành Google Play. Không cần Play Store để cài thủ công. GitHub giữ artifact mặc định 14 ngày, nên hãy tải về trước khi hết hạn nếu muốn giữ bản build đó.

## Bản iPhone (iOS)

Mã nguồn native cho iPhone nằm trong thư mục `ios/TaskFlow` và dùng chung tài khoản/dữ liệu Supabase với website và Android. Bản iOS hiện có đăng nhập/tạo tài khoản, danh sách Hôm nay/Hằng ngày/Chưa xong/Đã xong, tích hoàn thành, làm mới dữ liệu, chế độ sáng/tối và đăng xuất.

Mỗi lần cập nhật mã nguồn iOS, GitHub Actions sẽ chạy workflow **Build TaskFlow for iPhone**. Khi workflow thành công, mở lần chạy đó → **Artifacts**:
- `TaskFlow-iOS-Xcode-Project`: dự án Xcode đã được tạo sẵn để mở trên Mac.
- `TaskFlow-iOS-Builds`: bản build iOS Simulator và bản build thiết bị chưa ký.

### Cài lên iPhone thật

iOS yêu cầu ứng dụng được ký trước khi cài lên iPhone. Tệp build chưa ký trong Artifacts dùng để kiểm tra build, **không thể cài trực tiếp như APK Android**. Để chạy app trên iPhone:

1. Tải và giải nén artifact `TaskFlow-iOS-Xcode-Project` trên Mac có Xcode.
2. Mở `TaskFlow.xcodeproj`.
3. Kết nối iPhone với Mac, chọn iPhone làm thiết bị chạy.
4. Trong **Signing & Capabilities**, chọn Team là Apple ID/Apple Developer của bạn và dùng một Bundle Identifier riêng nếu Xcode yêu cầu.
5. Nhấn **Run** trong Xcode để cài và mở ứng dụng trên iPhone.

Bạn có thể chạy bản trên iPhone cá nhân bằng Personal Team của Apple ID trong Xcode; thời hạn ký phát triển có thể cần làm mới định kỳ. Phát hành cho người khác hoặc qua App Store cần quy trình ký/phân phối riêng. Không cần đưa Apple certificate hay mật khẩu vào GitHub.

## Khắc phục lỗi thường gặp

- **Web báo chưa cấu hình:** kiểm tra `web/config.js`, đảm bảo không còn placeholder `YOUR-PROJECT-ID` hoặc `YOUR_SUPABASE...`, rồi commit/push lại.
- **Android báo chưa cấu hình:** kiểm tra `AppConfig.kt`, push thay đổi lên GitHub và tải APK mới sau khi workflow build xong.
- **Lỗi API key hoặc 401:** kiểm tra URL và key có cùng thuộc một Supabase project hay không. Không dùng `service_role` key.
- **Lỗi `column tasks.is_daily does not exist`:** mở `supabase/daily_tasks_migration.sql`, dán vào **Supabase → SQL Editor → New query**, bấm **Run**, sau đó tải lại website bằng `⌘ + Shift + R`. Không cần xóa hay tạo lại bảng `tasks`.
- **Lỗi permission/table not found:** chạy toàn bộ `supabase/schema.sql` trong SQL Editor và kiểm tra câu lệnh chạy thành công.
- **Tạo tài khoản được nhưng không đăng nhập được:** kiểm tra hộp thư xác nhận email và cài đặt Email provider trong Supabase.
- **Tích trên Android nhưng Mac chưa đổi ngay:** bấm nút làm mới trên web; nếu cần, kiểm tra cấu hình Realtime trong Supabase. Trên Android, bấm nút làm mới hoặc đợi tối đa khoảng 30 giây khi app đang mở.
- **GitHub Actions báo lỗi:** mở workflow thất bại, bấm vào bước màu đỏ đầu tiên và đọc thông báo. Đây là mã nguồn khởi đầu; nên kiểm tra lần build cloud đầu tiên trước khi cài APK.

## Giới hạn có chủ đích của phiên bản đầu

- Android cần kết nối Internet để cập nhật công việc; chưa có hàng đợi thay đổi offline.
- Android tự tải dữ liệu lại mỗi 30 giây thay vì dùng push notification.
- Chưa có việc định kỳ, nhắc giờ, việc con hay xử lý xung đột offline.
- APK hiện tại dùng chữ ký debug và chưa được phát hành lên Google Play.

## Bảo mật dữ liệu

Web và Android chỉ dùng publishable/anon key. Quyền truy cập bảng được giới hạn bằng RLS theo user ID. Không tắt RLS và không đưa service-role key vào app để “sửa nhanh” lỗi quyền truy cập. Hãy bảo vệ tài khoản GitHub, Supabase và email của Minh.
