// Folosit de test/extension_crypto_test.dart: primește pe stdin
// {password, keysDoc, enc, path}, decriptează cu codul extensiei și
// trimite înapoi pe stdout {decoded, reenc} (o intrare nouă criptată).
import {
  unwrapDataKey,
  importDataKey,
  decryptMap,
  encryptMap,
} from '../lib/crypto.js';

let input = '';
for await (const chunk of process.stdin) input += chunk;
const { password, keysDoc, enc, path } = JSON.parse(input);

const wrong = await unwrapDataKey(keysDoc.password, password + 'x');
const bytes = await unwrapDataKey(keysDoc.password, password);
if (!bytes) throw new Error('unwrap failed');
const key = await importDataKey(bytes);
const decoded = await decryptMap(key, enc, path);
const reenc = await encryptMap(
  key,
  { ...decoded, password: 'din-extensie', title: 'Scris de extensie' },
  'secrets/din-extensie',
);
process.stdout.write(JSON.stringify({ wrongIsNull: wrong === null, decoded, reenc }));
