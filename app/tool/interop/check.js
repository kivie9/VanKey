// Đối chiếu kết quả Dart (package `cryptography`) với libsodium độc lập (libsodium-wrappers-sumo).
// Cần chạy trước:  flutter test test/spike/crypto_spike_test.dart   (để tạo build/spike_out.json)
// Lưu ý: phải dùng bản "sumo", bản libsodium-wrappers thường KHÔNG có Argon2.
const fs = require('fs');
const path = require('path');
const sodium = require('libsodium-wrappers-sumo');

const inputFile = path.join(__dirname, '..', '..', 'build', 'spike_out.json');

(async () => {
  await sodium.ready;
  if (!fs.existsSync(inputFile)) {
    console.error('Không thấy ' + inputFile + '\nHãy chạy trước: flutter test test/spike/crypto_spike_test.dart');
    process.exit(2);
  }
  const out = JSON.parse(fs.readFileSync(inputFile, 'utf8'));
  const hex = (h) => Uint8Array.from(Buffer.from(h, 'hex'));
  const toHex = (u) => Buffer.from(u).toString('hex');
  let ok = true;
  const report = (name, pass, extra) => {
    ok = ok && pass;
    console.log((pass ? 'KHỚP   ' : 'KHÁC   ') + name + (extra ? '  ' + extra : ''));
  };

  // 1) Argon2id
  const a = out.argon2id;
  const t0 = Date.now();
  const key = sodium.crypto_pwhash(32, Buffer.from(a.passphrase, 'utf8'), hex(a.saltHex),
    a.opslimit, a.memlimitBytes, sodium.crypto_pwhash_ALG_ARGON2ID13);
  const ms = Date.now() - t0;
  report('Argon2id (opslimit=3, 64 MiB) cùng khóa 32 byte', toHex(key) === a.keyHex, `(libsodium-wasm: ${ms} ms)`);

  // 2) XChaCha20-Poly1305-IETF với đầu vào cố định
  const e = out.aead;
  const ct = sodium.crypto_aead_xchacha20poly1305_ietf_encrypt(hex(e.plainHex), hex(e.aadHex), null, hex(e.nonceHex), hex(e.keyHex));
  const got = toHex(ct);
  report('XChaCha20-Poly1305: bản mã', got.slice(0, got.length - 32) === e.cipherHex);
  report('XChaCha20-Poly1305: tag 16 byte', got.slice(got.length - 32) === e.tagHex);

  // 3) libsodium giải mã được bản mã do Dart tạo
  const dec = sodium.crypto_aead_xchacha20poly1305_ietf_decrypt(null, Buffer.concat([hex(e.cipherHex), hex(e.tagHex)]), hex(e.aadHex), hex(e.nonceHex), hex(e.keyHex));
  report('libsodium giải mã được bản mã của Dart', toHex(dec) === e.plainHex);

  // 4) libsodium phải từ chối khi sửa 1 byte
  const bad = Buffer.concat([hex(e.cipherHex), hex(e.tagHex)]);
  bad[3] ^= 1;
  let rejected = false;
  try {
    sodium.crypto_aead_xchacha20poly1305_ietf_decrypt(null, bad, hex(e.aadHex), hex(e.nonceHex), hex(e.keyHex));
  } catch (_) {
    rejected = true;
  }
  report('libsodium từ chối bản mã bị sửa 1 byte', rejected);

  console.log(ok ? '\nTẤT CẢ KHỚP: hai bản cài đặt tương thích.' : '\nCÓ CHỖ KHÁC NHAU: cần điều tra.');
  process.exit(ok ? 0 : 1);
})();
