// Jurnalul schimbărilor: forma cererilor către Firestore (fetch simulat).
// Rulează: node test/changes.test.mjs
import assert from 'node:assert/strict';
import { getChanges, markChanged, getSecrets } from '../lib/firebase.js';

const session = { uid: 'U1', idToken: 'T' };
const calls = [];
globalThis.fetch = async (url, opts = {}) => {
  calls.push({ url, opts });
  if (url.endsWith('/keys/secretsVersion') && !opts.method) {
    return {
      ok: true,
      status: 200,
      json: async () => ({
        fields: {
          v: { integerValue: '5' },
          c: {
            mapValue: {
              fields: {
                'a-1': { integerValue: '3' },
                'b-2': { integerValue: '5' },
              },
            },
          },
        },
      }),
    };
  }
  if (url.includes(':batchGet')) {
    return {
      ok: true,
      status: 200,
      json: async () => [
        {
          found: {
            name: 'projects/p/databases/(default)/documents/users/U1/secrets/a-1',
            fields: { enc: { stringValue: 'X' } },
          },
        },
        { missing: 'projects/p/databases/(default)/documents/users/U1/secrets/b-2' },
      ],
    };
  }
  return { ok: true, status: 200, json: async () => ({}) };
};

// citire: harta id → moment
assert.deepEqual(await getChanges(session), { 'a-1': 3, 'b-2': 5 });

// notare: doar câmpurile v și c.`id` (merge, nu suprascrie restul hărții)
const at = await markChanged(session, 'a-1');
assert.ok(at > 0);
const put = calls.at(-1);
assert.equal(put.opts.method, 'PATCH');
assert.ok(put.url.includes('updateMask.fieldPaths=v'));
assert.ok(put.url.includes(`updateMask.fieldPaths=${encodeURIComponent('c.`a-1`')}`));
const body = JSON.parse(put.opts.body);
assert.equal(body.fields.c.mapValue.fields['a-1'].integerValue, String(at));

// citire punctuală: găsit + șters (lipsă = ca un cont șters)
const docs = await getSecrets(session, ['a-1', 'b-2']);
assert.deepEqual(docs, [
  { id: 'a-1', data: { enc: 'X' } },
  { id: 'b-2', data: { deleted: true } },
]);
const req = JSON.parse(calls.at(-1).opts.body);
assert.equal(req.documents.length, 2);
assert.ok(req.documents[0].endsWith('/users/U1/secrets/a-1'));

console.log('changes: ok');
