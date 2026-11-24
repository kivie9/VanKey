# Kết quả spike mật mã (M0)

> Ngày: 2026-11-19 · Máy: Windows 11 · Flutter 3.50.0 / Dart 3.14.0 · package `cryptography` 2.9.0
> Đối chiếu bằng `libsodium-wrappers-sumo` 0.8.4 (libsodium biên dịch sang WASM, chạy bằng Node 22)

## Câu hỏi cần trả lời
1. Argon2id và XChaCha20-Poly1305 có chạy đúng trong Dart không?
2. Kết quả có **trùng với libsodium** không? (cần, vì extension và server sau này đọc cùng định dạng file)
3. Tốc độ Argon2id có chấp nhận được không?

## Kết quả

### Đúng đắn: ĐẠT
`app/test/spike/crypto_spike_test.dart` — **7/7 test qua**:

| Test | Kết quả |
|---|---|
| XChaCha20-Poly1305 khớp test vector chính thức (draft-irtf-cfrg-xchacha, A.3.1) | qua |
| Mã hóa rồi giải mã, nonce 24 byte, tag 16 byte | qua |
| Sai khóa → báo lỗi, không trả dữ liệu | qua |
| Sửa 1 byte bản mã hoặc 1 byte tag → báo lỗi | qua |
| AAD khác → báo lỗi (chống sửa header) | qua |
| Argon2id: cùng đầu vào cùng khóa; khác salt khác khóa | qua |
| Xuất dữ liệu cố định để đối chiếu | qua |

### Tương thích với libsodium: ĐẠT, khớp từng byte
Cùng đầu vào, hai bản cài đặt độc lập (Dart `cryptography` và libsodium) cho:

| Phép thử | Kết quả |
|---|---|
| Argon2id: passphrase tiếng Việt, salt cố định, opslimit=3, 64 MiB → khóa 32 byte | **khớp** |
| XChaCha20-Poly1305: bản mã | **khớp** |
| XChaCha20-Poly1305: tag | **khớp** |
| libsodium giải mã được bản mã do Dart tạo | **được** |
| libsodium từ chối bản mã bị sửa 1 byte | **từ chối** |

Hệ quả: **định dạng file đặc tả ở `vault-format.md` thực hiện được bằng Dart và bằng TypeScript** (extension/server về sau) mà đọc/ghi chéo được. Ánh xạ tham số: libsodium `opslimit` = số vòng lặp (`iterations`), `memlimit` = bộ nhớ byte = `memory` (KiB) × 1024, song song hóa = 1.

Dữ liệu đã lưu thành test vector đầu tiên: `app/test/vectors/primitives-v0.json`.

### Tốc độ Argon2id trên PC này

| Tham số | Dart AOT (`dart compile exe`) |
|---|---|
| 1 vòng, 16 MiB | 54 ms |
| 2 vòng, 32 MiB | 236 ms |
| **3 vòng, 64 MiB** (dự kiến mặc định) | **876 ms** |
| 3 vòng, 128 MiB | 1368 ms |

- Chế độ `flutter test` (JIT) với 3 vòng, 64 MiB: 856 ms (gần như cùng).
- Để so sánh: libsodium WASM cùng tham số 3 vòng, 64 MiB: **214 ms** (một lần chạy). Bản thuần Dart chậm hơn khoảng **4 lần**.
- Mỗi số chỉ đo **một lần**, chưa lấy trung bình, nên chỉ dùng để so cỡ độ lớn.

Ngưỡng đặt ở `TASKS.md`: mở khóa ≤ ~1 giây trên PC, ≤ ~1,5 giây trên điện thoại tầm trung.
- **PC: đạt** với 3 vòng, 64 MiB (0,88 s). 128 MiB (1,37 s) vượt ngưỡng.
- **Điện thoại: CHƯA ĐO.** Điện thoại thường chậm hơn PC vài lần, nên có nguy cơ 3 vòng, 64 MiB vượt 1,5 s với bản thuần Dart.

## Chưa kiểm chứng (nói rõ)
- **`sodium_libs` (libsodium gốc) chưa thử.** Nó cần build bản Windows gốc, tức cần **Visual Studio** (chưa cài). Vì spike thuần Dart đã đạt, đây không còn là điều kiện chặn mà là phương án **tăng tốc** về sau.
- **Đo trên Android thật chưa làm** (chưa có Android SDK).
- **Mức dùng bộ nhớ** của Argon2id chưa đo (64 MiB là bộ nhớ thuật toán cần, chưa tính phần phụ trợ của Dart).
- **Xóa khóa khỏi RAM:** Dart có bộ thu gom rác nên không bảo đảm ghi đè được mọi bản sao. Đã ghi trong `threat-model.md`.
- **Chống tấn công kênh phụ (thời gian chạy hằng định):** thư viện thuần Dart không cam kết điều này. Chấp nhận được với mô hình đe dọa hiện tại (ứng dụng cục bộ, không phải dịch vụ nhận đầu vào từ xa), nhưng cần người có chuyên môn xem lại trước khi dùng thật.

## Quyết định (ghi ở `decisions.md`, D4)
**Dùng `cryptography` (thuần Dart) để làm tiếp M1**, đặt sau giao diện `Kdf` và `Aead` của chính dự án. Vì cùng thuật toán, đổi sang libsodium gốc sau này **không thay đổi định dạng file**.

Nếu đo trên Android thấy quá chậm, có ba cách theo thứ tự:
1. Hạ tham số: ví dụ 2 vòng, 64 MiB (vẫn ≥ cận dưới 2 vòng, 32 MiB trong đặc tả). Tham số lưu trong từng keyslot nên chỉnh được mà không đổi định dạng.
2. Chuyển sang `sodium_libs` trên Android.
3. Giữ Argon2id nặng nhưng chạy trong isolate riêng và hiện màn chờ.

## Cách chạy lại
```powershell
cd E:\code\project\keymanager\app
flutter test test/spike/crypto_spike_test.dart

# đo thời gian (AOT)
E:\code\libs\flutter\bin\cache\dart-sdk\bin\dart.exe compile exe test/spike/argon2_bench.dart -o build/argon2_bench.exe
.\build\argon2_bench.exe

# đối chiếu với libsodium (cần Node), chạy SAU lệnh flutter test ở trên:
cd tool\interop
npm install
node check.js
```
Script đối chiếu nằm ở `app/tool/interop/` (dùng bản `libsodium-wrappers-sumo`, bản thường **không** có Argon2) và đọc `app/build/spike_out.json` do test tạo ra.

Số đo thời gian dao động giữa các lần chạy (ví dụ 856 ms rồi 995 ms cho cùng tham số), nên đừng xem một con số đơn lẻ là chính xác.
