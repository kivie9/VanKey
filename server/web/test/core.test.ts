// Bản web phải đọc đúng y hệt bản Dart. Vector do `app/tool/make_web_vectors.dart` tạo từ chính lõi Dart.
//   node --test web/test/core.test.ts
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { deriveAuthKey, deriveLegacyAuthKey, hasLegacyAuthKey } from '../src/core/auth.ts';
import { fromB64, toB64, utf8 } from '../src/core/bytes.ts';
import { argon2id } from '../src/core/argon2.ts';
import { aeadOpen, hkdfSha256 } from '../src/core/crypto.ts';
import { otpCode } from '../src/core/otp.ts';
import { decryptPayload, parseRecoveryKey, parseVault, unwrapWithPassphrase, unwrapWithRecovery } from '../src/core/vault.ts';

const root = new URL('../../../app/test/vectors/', import.meta.url);
const web = JSON.parse(readFileSync(new URL('web-v1.json', root), 'utf8'));
const prim = JSON.parse(readFileSync(new URL('primitives-v0.json', root), 'utf8'));
const hex = (s: string) => Uint8Array.from(Buffer.from(s, 'hex'));
const file = () => fromB64(web.vault.fileB64);

test('Argon2id khớp libsodium (primitives-v0)', async () => {
  const a = prim.argon2id;
  const k = await argon2id(utf8(a.passphrase.normalize('NFKC')), hex(a.saltHex), { opslimit: a.opslimit, memlimitBytes: a.memlimitBytes });
  assert.equal(Buffer.from(k).toString('hex'), a.keyHex);
});

test('XChaCha20-Poly1305 khớp libsodium (primitives-v0)', () => {
  const v = prim.aead;
  const plain = aeadOpen(hex(v.keyHex), hex(v.nonceHex), hex(v.cipherHex + v.tagHex), hex(v.aadHex));
  assert.equal(Buffer.from(plain).toString('hex'), v.plainHex);
});

test('HKDF-SHA256 khớp RFC 5869 test case 1', async () => {
  const okm = await hkdfSha256(hex('0b'.repeat(22)), hex('000102030405060708090a0b0c'), hex('f0f1f2f3f4f5f6f7f8f9'), 42);
  assert.equal(Buffer.from(okm).toString('hex'), '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865');
});

test('mở kho bằng passphrase (dạng tổ hợp, cần NFKC) ra đúng dữ liệu', async () => {
  const v = parseVault(file());
  assert.equal(v.vaultId, web.vault.vaultId);
  const key = await unwrapWithPassphrase(v, web.vault.passphraseNfd, argon2id);
  assert.deepEqual(decryptPayload(v, key), web.vault.payload);
});

test('mở kho bằng recovery key, nhập chữ thường và khoảng trắng vẫn được', async () => {
  const v = parseVault(file());
  const key = await unwrapWithRecovery(v, ` ${web.vault.recoveryKey.toLowerCase().replaceAll('-', ' ')} `);
  assert.deepEqual(decryptPayload(v, key), web.vault.payload);
  assert.equal(parseRecoveryKey(web.vault.recoveryKey).length, 15);
});

test('sai passphrase thì không mở được', async () => {
  const v = parseVault(file());
  await assert.rejects(unwrapWithPassphrase(v, 'sai mật khẩu', argon2id), { code: 'auth' });
});

test('sửa bất kỳ byte nào trong header hoặc dữ liệu thì không mở được', async () => {
  const good = file();
  const key = await unwrapWithPassphrase(parseVault(good), web.vault.passphraseNfd, argon2id);
  const h = new DataView(good.buffer).getUint32(8);
  for (const at of [12 + 5, 12 + h - 2, 12 + h + 3, good.length - 1, good.length - 40]) {
    const bad = good.slice();
    bad[at] ^= 0x01;
    assert.throws(() => decryptPayload(parseVault(bad), key), (e: { code?: string }) => e.code === 'auth' || e.code === 'corrupt', `byte ${at}`);
  }
});

test('từ chối phiên bản mới hơn, magic sai, file cụt và tham số KDF yếu', () => {
  const f = file();
  const v2 = f.slice();
  v2[5] = 2;
  assert.throws(() => parseVault(v2), { code: 'unsupported' });
  const magic = f.slice();
  magic[0] = 0;
  assert.throws(() => parseVault(magic), { code: 'corrupt' });
  assert.throws(() => parseVault(f.subarray(0, 40)), { code: 'corrupt' });

  const h = new DataView(f.buffer).getUint32(8);
  const header = Buffer.from(f.subarray(12, 12 + h)).toString().replace('"opslimit":3', '"opslimit":1');
  const hb = utf8(header);
  const weak = new Uint8Array(12 + hb.length + f.length - 12 - h);
  weak.set(f.subarray(0, 12));
  new DataView(weak.buffer).setUint32(8, hb.length);
  weak.set(hb, 12);
  weak.set(f.subarray(12 + h), 12 + hb.length);
  assert.throws(() => parseVault(weak), { code: 'weak_kdf' });
});

test('khóa đăng nhập khớp bản Dart, cả kiểu mới (NFKC) lẫn kiểu cũ', async () => {
  const a = web.auth;
  assert.equal(await deriveAuthKey(a.username, a.passwordNfd, argon2id), a.authKey);
  assert.equal(await deriveLegacyAuthKey(a.username, a.passwordNfd, argon2id), a.legacyAuthKey);
  assert.equal(hasLegacyAuthKey(a.passwordNfd), true);
  assert.equal(hasLegacyAuthKey('abc'), false);
});

test('mã TOTP, HOTP và Steam khớp bản Dart', async () => {
  for (const o of web.otp) {
    const s = await otpCode(o, (o.time ?? 0) * 1000);
    assert.equal(s.code, o.code, JSON.stringify(o));
  }
});

test('base64 khứ hồi', () => {
  const b = Uint8Array.from({ length: 70000 }, (_, i) => i % 251);
  assert.deepEqual(fromB64(toB64(b)), b);
});
