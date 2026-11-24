# Đặc tả định dạng kho (`.vkv`) — bản nháp v0.1

> Trạng thái: **bản nháp v0.2, đã có cài đặt tham chiếu bằng Dart (M1)**. Đặc tả này khớp với mã trong `app/lib/core/`. Chưa có người ngoài rà soát: **không dùng cho dữ liệu thật cho đến khi có rà soát (xem `TASKS.md` M7)**.
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

### 5.2 AAD của phép bọc khóa (wrap)
`wrap.ct = XChaCha20-Poly1305(KEK, wrap.nonce, vault_key, aad)` với `aad` là chuỗi UTF-8:

```
passphrase : vankey/wrap/v1|<vaultId>|<slotId>|passphrase|argon2id13|<opslimit>|<memlimit>|<salt base64>
recovery   : vankey/wrap/v1|<vaultId>|<slotId>|recovery|hkdf-sha256|<salt base64>|<info>
```

Nhờ vậy một khe **không thể chép sang kho khác** (khác `vaultId`) và **sửa tham số KDF trong header thì mở khóa thất bại**.

### 5.3 Khe lạ
Khe có `type` chưa biết (do bản app mới hơn thêm) được **bỏ qua khi mở và giữ nguyên khi ghi lại**; không cần có `kdf`/`wrap` hợp lệ. Header cũng giữ nguyên các trường lạ ở mức cao nhất.

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
  "fields": [
    { "key": "username", "value": "...", "secret": false, "kind": "text" },
    { "label": "Câu hỏi bảo mật", "value": "...", "secret": true, "kind": "text" }
  ],
  "totp": { "secret": "<base32>", "algo": "SHA1", "digits": 6, "period": 30 },
  "group": "Dev",
  "favorite": true,
  "pwHistory": [ { "value": "...", "changedAt": "..." } ],
  "reminder": { "months": 3, "noticeDays": 7, "lastChangedAt": "..." },
  "createdAt": "...",
  "updatedAt": "...",
  "deletedAt": null,
  "hlc": "<wallclockMs>:<counter>:<deviceId>"
}
```
- **Trường theo mẫu có `key` ổn định** (`username`, `password`, `url`, `backupCodes`, `account`, `service`, `key`, `expiry`, `wallet`, `address`, `seedPhrase`, `holder`, `number`, `cvv`, `pin`, `ssid`, `security`, `content`, `notes`) để giao diện dịch nhãn theo ngôn ngữ; **trường người dùng tự thêm** có `label` thay cho `key`. Mẫu nằm ở `ItemTemplates` (`app/lib/core/vault/models.dart`).
- `deletedAt != null` nghĩa là **trong thùng rác** (khôi phục được 30 ngày; quá hạn thì tự xóa vĩnh viễn). Xóa vĩnh viễn → bỏ khỏi `items` và thêm vào `tombstones` để việc xóa lan sang thiết bị khác.
- Trường `secret: true` không được dùng làm dòng phụ trong danh sách, không đưa vào tìm kiếm, không hiện khi chưa bấm.
- Trường lạ trong JSON phải **được giữ nguyên khi ghi lại** (cả ở mức mục lẫn mức kho). `type` lạ được hiểu tạm là `note` khi hiển thị nhưng **ghi lại đúng giá trị gốc**.
- `schema` lớn hơn bản app hiểu → từ chối mở (cần cập nhật ứng dụng).

### 6.3 Đệm kích thước
Trước khi mã hóa, **đệm phần JSON bằng khoảng trắng (0x20) cho đến bội số của 4096 byte**. Khoảng trắng ở cuối là JSON hợp lệ nên không cần cơ chế gỡ đệm. Giảm lộ số lượng mục chính xác qua kích thước file.

### 6.4 Nén
Chưa nén ở v1 (đơn giản, tránh tấn công nén). Header có chỗ để thêm `compression` ở phiên bản sau.

---

## 7. Gộp (merge)

> **Thay đổi so với bản nháp v0.1:** bản nháp dùng trường `parentHlc` để phát hiện xung đột. Cách đó **báo xung đột sai** khi một thiết bị sửa một mục nhiều lần liên tiếp rồi mới đồng bộ (thiết bị kia thấy bản mới nhất nhưng không có bản trung gian). Đã chuyển sang **gộp ba chiều**, trường `parentHlc` bị bỏ.

**Đồng hồ lai (HLC):** `hlc = <wallclockMs>:<counter>:<deviceId>`; `deviceId` chỉ gồm chữ, số, `-`, `_`. So sánh theo `(wallclockMs, counter, deviceId)`: một thứ tự **toàn phần**, nên mọi thiết bị chọn cùng một bản thắng bất kể lệch giờ. Mỗi lần sửa mục (kể cả chuyển vào thùng rác, khôi phục) thiết bị sinh HLC mới **lớn hơn** mọi HLC đã sinh hoặc đã thấy. Chuỗi HLC hỏng được hiểu là cổ nhất.

**Gộp ba chiều** `merge(local, remote, base)`: `base` là bản chung gần nhất đã đồng bộ thành công (thiết bị lưu lại sau mỗi lần đồng bộ; `null` nếu chưa từng đồng bộ). Với mỗi `id` (trạng thái: có mục / đã xóa vĩnh viễn / không có):

| Tình huống | Kết quả |
|---|---|
| `local` và `remote` cùng phiên bản (cùng `hlc`, hoặc cùng là tombstone) | giữ nguyên (hai tombstone khác `hlc` thì lấy `hlc` lớn hơn, để kết quả không phụ thuộc thứ tự) |
| Có `base`, chỉ một bên đổi so với `base` | lấy bên đã đổi, **không xung đột** (kể cả khi bên đó đổi nhiều lần) |
| Có `base`, cả hai bên đều đổi | bản có `hlc` lớn hơn thắng; nếu cả hai đều là mục còn tồn tại thì **ghi nhận xung đột** để giao diện hỏi người dùng |
| Không có `base`, một bên không có | lấy bên có |
| Không có `base`, cả hai có và khác nhau | `hlc` lớn hơn thắng, ghi nhận xung đột |
| Tombstone đối đầu với bản sửa | `hlc` lớn hơn thắng (sửa sau xóa thì giữ bản sửa), **không** ghi nhận xung đột |

- **Giải quyết xung đột:** người dùng chọn giữ bản của mình hoặc của máy chủ; kết quả là một **phiên bản mới** (HLC lớn hơn cả hai) để lần đồng bộ sau mọi thiết bị đều nhận.
- `groups`: hợp hai bên (chưa theo dõi việc xóa nhóm).
- **Tính chất đã kiểm bằng thử ngẫu nhiên** (500 kịch bản, `test/core/vault/merge_test.dart`): giao hoán (đổi chỗ local/remote cho cùng kết quả và cùng tập xung đột), hội tụ (gộp tiếp kết quả với từng bên không làm đổi), không mất mục khi không có tombstone mới hơn.
- Tìm thấy bằng thử ngẫu nhiên và đã sửa: khi cả hai máy cùng xóa vĩnh viễn một mục, kết quả phụ thuộc thứ tự nếu không chọn tombstone theo `hlc`.

---

## 8. Quy trình ghi và đọc

**Ghi:**
1. Tăng `revision`, đặt `updatedAt`.
2. Đệm JSON (6.3), sinh nonce **mới** 24 byte.
3. Dựng byte từ magic đến hết header, dùng làm AAD.
4. Mã hóa bằng vault key.
5. Ghi ra **file tạm cùng thư mục** (`<tên>.tmp`), `flush`, giữ bản trước thành `<tên>.bak`, rồi **đổi tên** đè file cũ (ghi nguyên tử, không bao giờ để kho nửa vời). Cài đặt: `VaultStorage.writeAtomic`.

**Đọc:**
1. Kiểm magic, version, độ dài (giới hạn mục 4).
2. Phân tích header, kiểm cận dưới tham số KDF.
3. Thử các keyslot theo thứ tự; mở được một slot là có vault key.
4. Giải mã dữ liệu với AAD; **thất bại = coi file hỏng/bị sửa**, không bao giờ trả dữ liệu một phần.
5. Xóa khóa trung gian (KEK) và bản rõ khỏi bộ nhớ ngay khi xong (mức cố gắng tối đa).

---

## 9. Test vector và kiểm thử

Test vector dùng chung với TypeScript sau này nằm ở `app/test/vectors/`. Các kiểm thử đã có (Dart):

- [x] Argon2id: passphrase tiếng Việt + salt + tham số → khóa 32 byte, **đối chiếu với libsodium** (`primitives-v0.json`, `test/core/crypto/primitives_test.dart`)
- [x] XChaCha20-Poly1305: vector chính thức draft-irtf-cfrg-xchacha A.3.1, và vector có tiếng Việt đối chiếu libsodium
- [x] HKDF-SHA256: vector RFC 5869 (test case 1 và 3)
- [x] NFKC: passphrase tiếng Việt dạng tổ hợp và dạng dựng sẵn mở được cùng một kho
- [x] File hỏng: sai magic, cắt cụt, JSON header rác → `CorruptVaultException`; sửa từng byte rải khắp file → không bao giờ mở được
- [x] `format_version` cao hơn hoặc cờ lạ → `UnsupportedVersionException`
- [x] Tham số KDF quá yếu/quá nặng trong header → `WeakKdfParametersException`
- [x] Chép khe sang kho khác (`vaultId` khác) → không mở được
- [x] Khe lạ và trường header lạ được giữ nguyên khi mở rồi ghi lại
- [x] Đệm kích thước: phần mã hóa luôn là bội số của 4096 (+ 16 byte tag)
- [ ] **Một file `.vkv` hoàn chỉnh cố định** (kèm passphrase và recovery key) để **TypeScript đọc chéo**. Chưa tạo; cần khi làm extension/server. Việc đối chiếu chéo Dart ↔ libsodium cho các phép nguyên thủy đã đạt (xem `docs/spike-m0.md`), nhưng **chưa có đối chiếu chéo cho cả định dạng file**.

---

## 10. Câu hỏi còn mở

| # | Câu hỏi | Tình trạng |
|---|---|---|
| 1 | Tham số Argon2id cuối cùng | Mặc định **3 vòng, 64 MiB** (0,88 s trên PC); chốt sau khi đo trên Android (xem `spike-m0.md`) |
| 2 | HKDF | **Đã chốt:** dùng HKDF của thư viện `cryptography` (đúng vector RFC 5869) |
| 3 | Khóa xác thực server dẫn xuất từ vault key (đăng nhập Cloudflare) | Tách riêng khỏi định dạng này; quyết ở M5 |
| 4 | Tên trường/enum của `kind` | Hiện là chuỗi tự do (`text`, `multiline`, `url`); chuẩn hóa khi cần |
| 5 | `settings` có đồng bộ trong kho không | Không, cài đặt chỉ ở cục bộ |
| 6 | Khe `device` (mở nhanh bằng sinh trắc) | Giao diện sẽ làm ở M3; **không** nằm trong file đồng bộ (mục 3.2) |
| 7 | Theo dõi việc xóa nhóm khi gộp | Chưa; nhóm chỉ hợp lại |
| 8 | HOTP (bộ đếm) | Chưa hỗ trợ ở v1: `totp` chỉ có TOTP; link HOTP khi nhập bị bỏ qua có cảnh báo |

---

## 11. Cài đặt tham chiếu

| Phần | Tệp |
|---|---|
| Nguyên thủy mật mã | `lib/core/crypto/{aead,kdf,csprng,passphrase,recovery_key}.dart` |
| Khe khóa | `lib/core/crypto/keyslot.dart` |
| File kho, header | `lib/core/vault/vault_file.dart` |
| Phiên làm việc (tạo, mở, đổi passphrase, xoay khóa) | `lib/core/vault/vault_session.dart` |
| Mô hình dữ liệu | `lib/core/vault/models.dart` |
| HLC và gộp | `lib/core/vault/{hlc,merge}.dart` |
| Ghi nguyên tử | `lib/core/vault/vault_storage.dart` |
