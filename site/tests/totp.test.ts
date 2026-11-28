import { test } from 'node:test';
import assert from 'node:assert/strict';
import { base32Decode, secondsLeft, totp } from '../src/scripts/totp.ts';

// RFC 6238 phụ lục B, hàng SHA1, mã 8 chữ số.
const secret = new Uint8Array(Buffer.from('12345678901234567890', 'ascii'));
const vectors: [number, string][] = [
  [59, '94287082'],
  [1111111109, '07081804'],
  [1111111111, '14050471'],
  [1234567890, '89005924'],
  [2000000000, '69279037'],
  [20000000000, '65353130'],
];

for (const [time, expected] of vectors) {
  test(`RFC 6238 SHA1 tại T=${time}`, async () => {
    assert.equal(await totp(secret, time, 8), expected);
  });
}

test('mã 6 chữ số là 6 chữ số cuối của mã 8 chữ số', async () => {
  assert.equal(await totp(secret, 59), '287082');
});

test('khóa mẫu base32 trên trang giải ra đúng khóa của RFC', () => {
  assert.deepEqual(base32Decode('GEZD GNBV GY3T QOJQ GEZD GNBV GY3T QOJQ'), secret);
});

test('đếm ngược nằm trong 1..30', () => {
  assert.equal(secondsLeft(0), 30);
  assert.equal(secondsLeft(29.9), 1);
  assert.equal(secondsLeft(30), 30);
});
