# Lõi `lib/core/` — tổng quan cho người viết giao diện (M2)

Toàn bộ là **Dart thuần, không import Flutter**. Giao diện chỉ gọi vào đây, không tự làm mật mã.
Đặc tả định dạng file: [`vault-format.md`](vault-format.md). Danh sách việc: [`TASKS.md`](TASKS.md).

## Luồng chính

```dart
// 1) Tạo kho mới (lần đầu). Trả về phiên và recovery key (hiển thị MỘT lần để người dùng lưu).
final (session, recovery) = await VaultSession.create(passphrase: 'cụm từ của người dùng');
print(recovery.formatted);                      // XXXX-XXXX-XXXX-XXXX-XXXX-XXXX

// 2) Làm việc với dữ liệu: VaultData bất biến, mỗi thay đổi trả bản mới.
final clock = HlcClock(node: deviceId);          // deviceId: chữ/số/-/_ , sinh một lần cho mỗi thiết bị
var data = VaultData.fromJson(session.payload);
final item = Item.create(type: ItemType.login, title: 'GitHub', clock: clock,
    values: {'username': 'van', 'password': 'p@ss'}, group: 'Dev');
data = data.upsert(item);
session.payload = data.toJson();

// 3) Lưu xuống đĩa (ghi nguyên tử, giữ .bak).
await VaultStorage.writeAtomic(File(path), await session.save());

// 4) Mở lại.
final bytes = await VaultStorage.read(File(path));
final opened = await VaultSession.openWithPassphrase(bytes!, 'cụm từ');   // hoặc openWithRecoveryKey
// ... khi khóa app:
opened.close();                                  // ghi đè vault key trong RAM
```

> **Argon2id mất khoảng 1 giây** với tham số chuẩn: gọi `create`/`open*`/`changePassphrase` trong **isolate riêng**
> (ví dụ `Isolate.run`) để giao diện không đứng hình.

## Các mô-đun

| Thư mục | Làm gì | Điểm vào |
|---|---|---|
| `crypto/` | Nguyên thủy mật mã, khe khóa, recovery key | `Kdf`, `Aead`, `KeySlots`, `RecoveryKey`, `normalizePassphrase` |
| `vault/` | Mô hình dữ liệu, file kho, phiên, gộp, tìm kiếm | `VaultData`, `Item`, `VaultSession`, `mergeVaults`, `matchesQuery` |
| `totp/` | Mã 2FA, link `otpauth://`, Google Authenticator | `Otp.code`, `OtpAuth.parse`, `Migration.parseUri` |
| `import_export/` | Nhập từ app khác, xuất | `Importers.auto`, `Exporters.csv/otpauthLines/googleMigrationUris` |
| `security/` | Độ mạnh, tạo mật khẩu, trùng, kiểm tra bảo mật, nhắc hạn, HIBP | `PasswordStrength`, `PasswordGenerator`, `findDuplicates`, `healthReport`, `pendingAlerts` |

## Hiển thị mã 2FA

```dart
final code = Otp.code(item.totp!, DateTime.now());      // '123456'
Otp.grouped(code);                                      // '123 456'
Otp.secondsRemaining(DateTime.now());                   // 1..30 (cho vòng đếm ngược)
```
Chỉ dùng **một** bộ hẹn giờ cho toàn app (mỗi giây) rồi tính lại mọi mã; không tạo bộ hẹn giờ cho từng dòng.

## Đồng bộ (M4)

```dart
final r = mergeVaults(local: localData, remote: remoteData, base: lastSyncedData);
// r.merged           -> dữ liệu sau gộp
// r.changesLocal     -> cần lưu cục bộ
// r.changesRemote    -> cần tải lên
// r.conflicts        -> giao diện hỏi người dùng; resolveConflict(...) tạo phiên bản mới
```
Sau mỗi lần đồng bộ thành công phải **lưu lại `base`** (bản chung vừa đồng bộ).

## Quy tắc khi dùng

- **Không bao giờ** in, log hay đưa vào thông báo: mật khẩu, khóa 2FA, passphrase, recovery key, trường `secret: true`.
- Dòng phụ trong danh sách: dùng `Item.subtitle` (đã bỏ trường bí mật).
- Tìm kiếm: dùng `matchesQuery` (không tìm trong trường bí mật, bỏ dấu tiếng Việt).
- Mọi lỗi của lõi là `VaultException`; bắt theo loại con (`AuthenticationFailedException` = sai passphrase hoặc file bị sửa,
  `UnsupportedVersionException` = cần cập nhật app, `EncryptedImportException` = file nhập đã mã hóa bởi app nguồn...).
- Nhãn trường: dùng `Field.key` để tra bản dịch; chỉ trường tự thêm mới có `Field.label`.

## Giới hạn đã biết

- Mật mã chạy **thuần Dart**: chưa đo trên Android, không cam kết chống tấn công kênh phụ, xóa khóa khỏi RAM chỉ ở mức cố gắng.
- Định dạng file **chưa có người ngoài rà soát**.
- Bộ đọc nhập khẩu **chưa thử với file xuất thật** của từng ứng dụng.
- Chưa hỗ trợ HOTP/Steam, chưa có khe `device` (sinh trắc), chưa có `SecureBytes`.
