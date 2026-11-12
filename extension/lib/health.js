// Starea unei parole, ca în aplicație: 🔴 compromisă (apare în scurgeri de
// date publice), 🟡 slabă sau folosită și la alt cont, 🟢 în regulă.
//
// Verificarea scurgerilor folosește Have I Been Pwned prin „k-anonimitate”:
// pleacă doar primele 5 caractere din amprenta SHA-1 a parolei, nu parola.

const COMMON = [
  'parola', 'password', 'qwerty', 'azerty', '123456', 'abc123',
  'iloveyou', 'admin', 'welcome', 'romania',
];

/// Aceeași regulă ca în aplicație (passwordStrength = weak).
export function isWeak(p) {
  if (!p) return true;
  const lower = p.toLowerCase();
  const obvious =
    COMMON.some((c) => lower.includes(c)) || /(.)\1{3,}/.test(p) || /^\d+$/.test(p);
  return p.length < 8 || obvious;
}

export async function sha1Hex(text) {
  const d = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(text));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('').toUpperCase();
}

/// true = apare în scurgeri; null = nu s-a putut verifica.
export async function pwned(hash) {
  try {
    const r = await fetch(`https://api.pwnedpasswords.com/range/${hash.slice(0, 5)}`, {
      headers: { 'Add-Padding': 'true' },
    });
    if (!r.ok) return null;
    const rest = hash.slice(5);
    for (const line of (await r.text()).split('\n')) {
      const [suffix, count] = line.trim().split(':');
      if (suffix === rest) return Number(count) > 0;
    }
    return false;
  } catch {
    return null;
  }
}

/// 'red' | 'yellow' | 'green' pentru fiecare parolă dintr-o listă.
export function healthOf(item, reuseCount, breaches, hash) {
  if (!item.password) return '';
  if (hash && breaches[hash] === true) return 'red';
  if (isWeak(item.password) || (reuseCount.get(item.password) ?? 0) > 1) return 'yellow';
  return 'green';
}
