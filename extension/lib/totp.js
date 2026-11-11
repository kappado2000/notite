// Coduri 2FA (TOTP, RFC 6238), ca în aplicație (lib/services/totp.dart):
// cheie Base32 sau link `otpauth://totp/…?secret=…&digits=…&period=…`.

function base32Decode(input) {
  const s = input.toUpperCase().replace(/[\s=-]/g, '');
  if (!s || /[^A-Z2-7]/.test(s)) return null;
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  const out = [];
  let bits = 0;
  let value = 0;
  for (const c of s) {
    value = (value << 5) | alphabet.indexOf(c);
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return new Uint8Array(out);
}

export function parseTotp(text) {
  const t = (text || '').trim();
  if (!t) return null;
  if (t.toLowerCase().startsWith('otpauth://')) {
    let u;
    try {
      u = new URL(t);
    } catch {
      return null;
    }
    if (u.host.toLowerCase() !== 'totp') return null;
    const secret = base32Decode(u.searchParams.get('secret') || '');
    if (!secret) return null;
    return {
      secret,
      digits: Number(u.searchParams.get('digits')) || 6,
      period: Number(u.searchParams.get('period')) || 30,
      algorithm: (u.searchParams.get('algorithm') || 'SHA1').toUpperCase(),
    };
  }
  const secret = base32Decode(t);
  return secret ? { secret, digits: 6, period: 30, algorithm: 'SHA1' } : null;
}

/// → { code, remaining } (secunde până la codul următor), sau null.
export async function totpCode(text, now = Date.now()) {
  const p = parseTotp(text);
  if (!p) return null;
  const hash = { SHA256: 'SHA-256', SHA512: 'SHA-512' }[p.algorithm] || 'SHA-1';
  const seconds = Math.floor(now / 1000);
  const counter = Math.floor(seconds / p.period);
  const msg = new Uint8Array(8);
  let c = counter;
  for (let i = 7; i >= 0; i--) {
    msg[i] = c & 0xff;
    c = Math.floor(c / 256);
  }
  const key = await crypto.subtle.importKey(
    'raw',
    p.secret,
    { name: 'HMAC', hash },
    false,
    ['sign'],
  );
  const h = new Uint8Array(await crypto.subtle.sign('HMAC', key, msg));
  const o = h[h.length - 1] & 0x0f;
  const bin =
    ((h[o] & 0x7f) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
  const code = String(bin % 10 ** p.digits).padStart(p.digits, '0');
  return { code, remaining: p.period - (seconds % p.period) };
}
