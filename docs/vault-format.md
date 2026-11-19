# Đặc tả định dạng kho (`.vkv`) — bản nháp v0.1

> Trạng thái: **NHÁP**. Chưa có dòng code nào kiểm chứng. Các giá trị đánh dấu **[M0]** phải đo/chốt ở bước spike (xem `TASKS.md`). Phần **test vector** (mục 9) chỉ điền được sau khi có code chạy.
> Mọi triển khai (Dart, và TypeScript cho extension/server sau này) phải đọc/ghi **byte-cho-byte giống nhau** theo tài liệu này.

---

## 1. Mục tiêu

1. Nơi lưu trữ (Google Drive, server Cloudflare, ổ đĩa) **không đọc được nội dung** và không sửa được mà không bị phát hiện.
2. Mở được bằng **nhiều cách** (passphrase, recovery key) mà không phải mã hóa lại cả kho.
3. **Đổi passphrase rẻ** (chỉ bọc lại khóa, không mã hóa lại dữ liệu).
4. Có **version** để nâng cấp về sau mà không làm hỏng kho cũ.
5. Gộp (merge) được giữa nhiều thiết bị.

Ngoài phạm vi: che giấu việc "đây là file VanKey" (magic number để rõ ràng), che số lượng mục chính xác (có đệm kích thước, xem 6.3).

---

## 2. Thuật toán

| Việc | Thuật toán | Ghi chú |
|---|---|---|
| Dẫn xuất khóa từ passphrase | **Argon2id** (libsodium `crypto_pwhash`, `ALG_ARGON2ID13`) | Tham số trong từng keyslot |
| Mã hóa xác thực | **XChaCha20-Poly1305-IETF** (libsodium `crypto_aead_xchacha20poly1305_ietf`) | Nonce 24 byte ngẫu nhiên, tag 16 byte |
| Dẫn xuất khóa từ recovery key | **HKDF-SHA256** (RFC 5869) | Recovery key đủ entropy nên không cần Argon2 |
| Sinh ngẫu nhiên | CSPRNG của hệ điều hành / libsodium (`randombytes_buf`) | Không dùng `Random()` của ngôn ngữ |
| So sánh bí mật | So sánh hằng thời gian | |

Nếu spike M0 cho thấy `sodium_libs` không dùng được trên một nền tảng, phải chọn thư viện thay thế **nhưng vẫn giữ nguyên các thuật toán trên** để định dạng không đổi.

---

## 3. Phân cấp khóa

```
vault key (32 byte, ngẫu nhiên, tạo một lần)
   │  mã hóa toàn bộ dữ liệu (XChaCha20-Poly1305)
   │
   └── được "bọc" (wrap) riêng biệt trong mỗi keyslot:
         ├─ passphrase : KEK = Argon2id(NFKC(passphrase), salt, tham số)
         ├─ recovery   : KEK = HKDF-SHA256(recovery_bytes, salt, "vankey/recovery/v1")
         └─ device     : KEK = khóa ngẫu nhiên cất trong kho an toàn của OS
                          (KHÔNG nằm trong file đồng bộ, xem 3.2)
```

- `wrap = AEAD(KEK, nonce, vault_key, aad = vaultId || slotId)`. Gắn `vaultId` và `slotId` vào AAD để một keyslot không thể bị chép sang kho khác.
- **Đổi passphrase:** mở kho, tính KEK mới, bọc lại vault key vào keyslot passphrase. Dữ liệu không đổi.
- **Xoay vault key** (khi nghi lộ): sinh vault key mới, mã hóa lại toàn bộ dữ liệu, bọc lại vào mọi keyslot. Thiết bị khác phải mở lại bằng passphrase/recovery.

### 3.1 Chuẩn hóa passphrase
Trước khi đưa vào Argon2id: **chuẩn hóa Unicode NFKC**, rồi UTF-8. Bắt buộc, vì tiếng Việt có chữ tổ hợp (ví dụ `ệ` có thể là một ký tự hoặc `e` + dấu), và bàn phím/hệ điều hành khác nhau cho ra dạng khác nhau. Không chuẩn hóa thì cùng một passphrase mở được trên máy này mà không mở được trên máy kia.
> Dart không có sẵn NFKC trong thư viện chuẩn; cần package (ví dụ `unorm_dart`) và test riêng với chuỗi tiếng Việt.

### 3.2 Keyslot `device` không nằm trong file đồng bộ
Keyslot `device` gắn với **một thiết bị cụ thể** (khóa nằm trong Keystore/Credential Manager). Nếu nằm trong file đồng bộ thì máy này sẽ ghi đè slot của máy kia.
- **File đồng bộ** (`vault.vkv` trên Drive/Cloudflare) chỉ chứa keyslot `passphrase` và `recovery`.
- **Bản lưu cục bộ** của thiết bị = file đồng bộ + một tệp nhỏ `local.json` chứa wrap của keyslot `device` (và cài đặt cục bộ). Mở nhanh bằng sinh trắc dùng slot này.
- **Chế độ offline, không tài khoản:** file cục bộ có thể chưa có slot `passphrase`/`recovery`; chỉ có `device`. Khi bật đồng bộ, **bắt buộc** thêm `passphrase` và `recovery` trước khi tải lên.

---

## 4. Bố cục file

Số nguyên nhiều byte dùng **big-endian**.

```
offset      kích thước   trường
0           4            magic = 0x56 0x4B 0x56 0x31  ("VKV1")
4           2            format_version (u16) = 1
6           2            flags (u16) = 0, dành riêng
8           4            header_len H (u32)
12          H            header: JSON UTF-8 (xem 5)
12+H        24           nonce (XChaCha20-Poly1305)
36+H        C            ciphertext || tag(16)
```

- **AAD của bước mã hóa dữ liệu** = toàn bộ byte từ offset 0 đến hết header (`0 .. 12+H`). Sửa magic, version hoặc header thì giải mã thất bại.
- Giới hạn: `H ≤ 64 KiB`, toàn file `≤ 16 MiB` (từ chối nếu vượt; chống file độc làm cạn bộ nhớ).
- Người đọc **từ chối** `format_version` lớn hơn bản mình hỗ trợ (thông báo cần cập nhật app), và **không bao giờ ghi đè** kho có version cao hơn.

---

## 5. Header (JSON)

```json
{
  "vaultId": "7f3c...-uuid",
  "revision": 42,
  "updatedAt": "2026-11-19T10:15:30Z",
  "cipher": "xchacha20poly1305-ietf",
  "keyslots": [
    {
      "id": "slot-uuid",
      "type": "passphrase",
      "kdf": { "alg": "argon2id13", "opslimit": 3, "memlimit": 67108864, "salt": "<b64 16B>" },
      "wrap": { "nonce": "<b64 24B>", "ct": "<b64 48B>" }
    },
    {
      "id": "slot-uuid",
      "type": "recovery",
      "kdf": { "alg": "hkdf-sha256", "salt": "<b64 16B>", "info": "vankey/recovery/v1" },
      "wrap": { "nonce": "<b64 24B>", "ct": "<b64 48B>" }
    }
  ]
}
```

- Mã hóa nhị phân trong JSON dùng **base64 chuẩn có padding**.
- `revision` tăng 1 mỗi lần ghi (để chẩn đoán; **không** dùng làm cơ chế đồng bộ, phiên bản đồng bộ do nơi lưu trữ quản lý).
- `opslimit`/`memlimit` mặc định **[M0]**: dự kiến `opslimit=3`, `memlimit=64 MiB`, điều chỉnh theo đo thực tế (xem TASKS.md M0). Lưu trong từng slot nên nâng được sau.
- **Cận dưới bắt buộc khi đọc:** từ chối `memlimit < 32 MiB` hoặc `opslimit < 2` (chống bị hạ tham số). Tham số nằm trong AAD của `wrap`, nên sửa tham số thì mở khóa thất bại.
- Header **không** chứa tên mục, số mục, hay bất kỳ thông tin nào về dữ liệu.

### 5.1 Recovery key
- 24 ký tự từ bảng chữ `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (32 ký hiệu, loại `0 O 1 I` để khỏi nhầm) → **120 bit entropy**.
- Hiển thị theo nhóm `XXXX-XXXX-XXXX-XXXX-XXXX-XXXX`. Khi nhập: bỏ khoảng trắng và gạch ngang, không phân biệt hoa thường.
- `recovery_bytes` = 24 ký hiệu giải mã thành 15 byte. KEK = `HKDF-SHA256(ikm = recovery_bytes, salt, info)`.

---

## 6. Dữ liệu bên trong (sau khi giải mã)

### 6.1 Định dạng
JSON UTF-8:

```json
{
  "schema": 1,
  "groups": ["Cá nhân", "Công việc"],
  "items": [ /* Item, xem 6.2 */ ],
  "tombstones": [ { "id": "item-uuid", "deletedAt": "...", "hlc": "..." } ]
}
```

### 6.2 `Item`
```json
{
  "id": "uuid",
  "type": "login|totp|key|crypto|card|wifi|note",
  "title": "GitHub",
  "fields": [ { "label": "Tên đăng nhập", "value": "...", "secret": false, "kind": "text" } ],
  "totp": { "secret": "<base32>", "algo": "SHA1", "digits": 6, "period": 30 },
  "group": "Dev",
  "favorite": true,
  "pwHistory": [ { "value": "...", "changedAt": "..." } ],
  "reminder": { "months": 3, "noticeDays": 7, "lastChangedAt": "..." },
  "createdAt": "...",
  "updatedAt": "...",
  "deletedAt": null,
  "hlc": "<wallclockMs>:<counter>:<deviceId>",
  "parentHlc": "<hlc của bản mà thay đổi này dựa trên>"
}
```
- `deletedAt != null` nghĩa là **trong thùng rác** (khôi phục được 30 ngày). Xóa vĩnh viễn → bỏ khỏi `items` và thêm vào `tombstones` để việc xóa lan sang thiết bị khác.
- Trường `secret: true` không được dùng làm dòng phụ trong danh sách, không đưa vào tìm kiếm, không hiện khi chưa bấm.
- Trường lạ trong JSON phải **được giữ nguyên khi ghi lại** (để bản app cũ không làm mất trường của bản mới).

### 6.3 Đệm kích thước
Trước khi mã hóa, **đệm phần JSON bằng khoảng trắng (0x20) cho đến bội số của 4096 byte**. Khoảng trắng ở cuối là JSON hợp lệ nên không cần cơ chế gỡ đệm. Giảm lộ số lượng mục chính xác qua kích thước file.

### 6.4 Nén
Chưa nén ở v1 (đơn giản, tránh tấn công nén). Header có chỗ để thêm `compression` ở phiên bản sau.

---

## 7. Gộp (merge)

- **Đồng hồ lai (HLC):** `hlc = <wallclockMs>:<counter>:<deviceId>`. So sánh theo `(wallclockMs, counter, deviceId)`. Mỗi lần sửa mục, thiết bị tạo HLC mới lớn hơn HLC lớn nhất đã thấy.
- **Theo từng mục:** với cùng `id`, bản có `hlc` lớn hơn thắng.
- **Xung đột:** nếu cả hai bản có `hlc` khác nhau và **không bản nào có `parentHlc` bằng `hlc` của bản kia** (tức cả hai sửa từ một bản gốc), đó là xung đột → giao diện cho người dùng chọn, **không ghi đè âm thầm**.
- Mục có trong tombstone của một bên và còn trong bên kia: so `hlc`; sửa sau xóa thì giữ bản sửa.
- Merge phải **giao hoán, kết hợp, lũy đẳng** (có property test).

---

## 8. Quy trình ghi và đọc

**Ghi:**
1. Tăng `revision`, đặt `updatedAt`.
2. Đệm JSON (6.3), sinh nonce **mới** 24 byte.
3. Dựng byte từ magic đến hết header, dùng làm AAD.
4. Mã hóa bằng vault key.
5. Ghi ra **file tạm cùng thư mục**, `fsync`, rồi **đổi tên** đè file cũ (ghi nguyên tử, không bao giờ để kho nửa vời).

**Đọc:**
1. Kiểm magic, version, độ dài (giới hạn mục 4).
2. Phân tích header, kiểm cận dưới tham số KDF.
3. Thử các keyslot theo thứ tự; mở được một slot là có vault key.
4. Giải mã dữ liệu với AAD; **thất bại = coi file hỏng/bị sửa**, không bao giờ trả dữ liệu một phần.
5. Xóa khóa trung gian (KEK) và bản rõ khỏi bộ nhớ ngay khi xong (mức cố gắng tối đa).

---

## 9. Test vector — **CHƯA CÓ** (điền ở M1)

Cần tạo và đưa vào `app/test/vectors/`, dùng chung cho TypeScript:

- [x] Argon2id: passphrase cố định + salt cố định + tham số → khóa 32 byte (`app/test/vectors/primitives-v0.json`, đã đối chiếu với libsodium)
- [x] XChaCha20-Poly1305: khóa, nonce, bản rõ, AAD → bản mã (cùng file; **tiếng Việt** trong bản rõ; đã đối chiếu với libsodium và test vector draft-irtf-cfrg-xchacha)
- [ ] HKDF-SHA256 cho recovery key (kèm một recovery key mẫu)
- [ ] Một file `.vkv` hoàn chỉnh nhỏ (2 keyslot, 3 mục) kèm passphrase và recovery key để mở thử
- [ ] File hỏng: sửa 1 byte ở magic / header / ciphertext / tag → phải thất bại
- [ ] NFKC: passphrase tiếng Việt dạng tổ hợp và dạng dựng sẵn phải cho cùng khóa
- [ ] File có `format_version` cao hơn → phải từ chối, không ghi đè

---

## 10. Câu hỏi còn mở

| # | Câu hỏi | Dự kiến |
|---|---|---|
| 1 | Tham số Argon2id cuối cùng | Chốt sau khi đo ở M0 |
| 2 | `sodium_libs` có cung cấp `crypto_kdf_hkdf_sha256` không, hay tự viết HKDF bằng HMAC | Tự viết HKDF trên `crypto` nếu thiếu (đơn giản, có test vector RFC 5869) |
| 3 | Có cần **khóa xác thực server** dẫn xuất từ vault key (cho đăng nhập Cloudflare) | Tách riêng khỏi định dạng này; quyết ở M5 |
| 4 | Tên trường/enum chính xác của `kind` | Chốt khi viết model ở M1 |
| 5 | Có đưa `settings` đồng bộ được vào kho không | Hiện: không, cài đặt chỉ ở cục bộ |
