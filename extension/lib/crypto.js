// Criptarea Notițe, compatibilă cu aplicația (lib/services/vault.dart):
// - cheia de date: AES-256-GCM, 32 de octeți aleatori;
// - împachetată cu o cheie din parolă: PBKDF2-HMAC-SHA256, sarea și
//   numărul de iterații stau în documentul `keys/main`;
// - „cutia” = nonce (12 octeți) + text criptat + etichetă (16 octeți),
//   în base64; documentele au ca date asociate (AAD) calea lor, ex.
//   `secrets/<id>`.

const subtle = globalThis.crypto.subtle;
const enc = new TextEncoder();
const dec = new TextDecoder();

export function b64decode(s) {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function b64encode(bytes) {
  let bin = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    bin += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(bin);
}

async function deriveKek(password, salt, iterations) {
  const base = await subtle.importKey(
    'raw',
    enc.encode(password),
    'PBKDF2',
    false,
    ['deriveKey'],
  );
  return subtle.deriveKey(
    { name: 'PBKDF2', hash: 'SHA-256', salt, iterations },
    base,
    { name: 'AES-GCM', length: 256 },
    false,
    ['decrypt'],
  );
}

async function aesOpen(key, box, aad) {
  const params = { name: 'AES-GCM', iv: box.subarray(0, 12) };
  if (aad) params.additionalData = enc.encode(aad);
  return new Uint8Array(await subtle.decrypt(params, key, box.subarray(12)));
}

/// Cheia de date (octeți) din `keys/main` → `password`, sau null dacă
/// parola nu se potrivește.
export async function unwrapDataKey(wrapped, password) {
  const kek = await deriveKek(
    password,
    b64decode(wrapped.salt),
    Number(wrapped.iterations),
  );
  try {
    return await aesOpen(kek, b64decode(wrapped.box));
  } catch {
    return null;
  }
}

export function importDataKey(bytes) {
  return subtle.importKey('raw', bytes, 'AES-GCM', false, [
    'encrypt',
    'decrypt',
  ]);
}

export async function decryptMap(key, encB64, path) {
  const clear = await aesOpen(key, b64decode(encB64), path);
  return JSON.parse(dec.decode(clear));
}

export async function encryptMap(key, data, path) {
  const iv = globalThis.crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(
    await subtle.encrypt(
      { name: 'AES-GCM', iv, additionalData: enc.encode(path) },
      key,
      enc.encode(JSON.stringify(data)),
    ),
  );
  const box = new Uint8Array(12 + ct.length);
  box.set(iv);
  box.set(ct, 12);
  return b64encode(box);
}

/// UUID v4, ca în aplicație.
export function uuid() {
  return globalThis.crypto.randomUUID();
}
