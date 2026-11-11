// node --test extension/test/mfa.test.mjs — conectarea cu verificare în doi
// pași (răspunsurile Firebase sunt simulate; nicio cerere reală).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { signIn, MfaRequired } from '../lib/firebase.js';

const token = (uid) =>
  `x.${Buffer.from(JSON.stringify({ user_id: uid })).toString('base64url')}.y`;

function fakeFetch(calls) {
  return async (url, opts) => {
    const body = JSON.parse(opts.body);
    calls.push({ url, body });
    if (url.includes('signInWithPassword')) {
      return {
        ok: true,
        json: async () => ({
          mfaPendingCredential: 'PENDING',
          mfaInfo: [{ mfaEnrollmentId: 'ENR1', totpInfo: {} }],
        }),
      };
    }
    if (url.includes('mfaSignIn:finalize')) {
      if (body.totpVerificationInfo.verificationCode !== '123456') {
        return { ok: false, status: 400, json: async () => ({ error: { message: 'INVALID_CODE' } }) };
      }
      return { ok: true, json: async () => ({ idToken: token('UID9'), refreshToken: 'R' }) };
    }
    throw new Error('neașteptat ' + url);
  };
}

test('fără cod: cere codul; cu cod corect: se conectează', async () => {
  const calls = [];
  globalThis.fetch = fakeFetch(calls);
  await assert.rejects(signIn('a@b.ro', 'pw'), MfaRequired);
  const s = await signIn('a@b.ro', 'pw', ' 123456 ');
  assert.equal(s.uid, 'UID9');
  assert.equal(s.refreshToken, 'R');
  const fin = calls.find((c) => c.url.includes('finalize')).body;
  assert.equal(fin.mfaPendingCredential, 'PENDING');
  assert.equal(fin.mfaEnrollmentId, 'ENR1');
});

test('cod greșit: mesaj clar', async () => {
  globalThis.fetch = fakeFetch([]);
  await assert.rejects(signIn('a@b.ro', 'pw', '000000'), /greșit/);
});
