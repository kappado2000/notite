// node --test extension/test/totp.test.mjs — vectorii oficiali RFC 6238
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { totpCode } from '../lib/totp.js';

// cheia RFC „12345678901234567890” în Base32
const SHA1 = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

test('RFC 6238 (SHA1, 8 cifre)', async () => {
  const url = `otpauth://totp/x?secret=${SHA1}&digits=8`;
  assert.equal((await totpCode(url, 59 * 1000)).code, '94287082');
  assert.equal((await totpCode(url, 1111111109 * 1000)).code, '07081804');
  assert.equal((await totpCode(url, 20000000000 * 1000)).code, '65353130');
});

test('cheie simplă, 6 cifre, secundele rămase', async () => {
  const r = await totpCode(SHA1, 59 * 1000);
  assert.equal(r.code, '287082');
  assert.equal(r.remaining, 1);
  assert.equal(await totpCode('nu e base32!'), null);
});
