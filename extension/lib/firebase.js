// Firebase prin REST (fără SDK): conectare cu email și parolă și
// documentele din `users/<uid>/...`. Aceleași reguli de acces ca aplicația:
// fiecare cont vede doar datele lui.

export const API_KEY = 'AIzaSyAxr-cYa12UYnYRWVA-qi-Zs3zRGyRiDdQ';
const PROJECT = 'notite-kappado';
const DOCS = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

export class AuthError extends Error {}

const MESSAGES = {
  EMAIL_NOT_FOUND: 'Email sau parolă greșite.',
  INVALID_PASSWORD: 'Email sau parolă greșite.',
  INVALID_LOGIN_CREDENTIALS: 'Email sau parolă greșite.',
  USER_DISABLED: 'Contul este dezactivat.',
  TOO_MANY_ATTEMPTS_TRY_LATER: 'Prea multe încercări. Încearcă mai târziu.',
};

async function postJson(url, body) {
  const r = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) {
    const code = data?.error?.message?.split(' ')[0] ?? `HTTP ${r.status}`;
    throw new AuthError(MESSAGES[code] ?? `Conectare eșuată (${code}).`);
  }
  return data;
}

/// → { uid, idToken, refreshToken, expiresAt }
export async function signIn(email, password) {
  const d = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`,
    { email, password, returnSecureToken: true },
  );
  return {
    uid: d.localId,
    idToken: d.idToken,
    refreshToken: d.refreshToken,
    expiresAt: Date.now() + (Number(d.expiresIn) - 60) * 1000,
  };
}

export async function refresh(session) {
  const r = await fetch(
    `https://securetoken.googleapis.com/v1/token?key=${API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: `grant_type=refresh_token&refresh_token=${encodeURIComponent(session.refreshToken)}`,
    },
  );
  const d = await r.json().catch(() => ({}));
  if (!r.ok) throw new AuthError('Sesiunea a expirat. Conectează-te din nou.');
  return {
    ...session,
    idToken: d.id_token,
    refreshToken: d.refresh_token,
    expiresAt: Date.now() + (Number(d.expires_in) - 60) * 1000,
  };
}

// ---------------------------------------------- valori Firestore ↔ JS

function fromValue(v) {
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('nullValue' in v) return null;
  if ('mapValue' in v) return fromFields(v.mapValue.fields ?? {});
  if ('arrayValue' in v) return (v.arrayValue.values ?? []).map(fromValue);
  return undefined;
}

function fromFields(fields) {
  const o = {};
  for (const [k, v] of Object.entries(fields)) o[k] = fromValue(v);
  return o;
}

function auth(session) {
  return { Authorization: `Bearer ${session.idToken}` };
}

/// `users/<uid>/keys/main` (cheia de date împachetată).
export async function getKeysDoc(session) {
  const r = await fetch(`${DOCS}/users/${session.uid}/keys/main`, {
    headers: auth(session),
  });
  if (r.status === 404) return null;
  if (!r.ok) throw new Error(`Nu am putut citi cheile (${r.status}).`);
  return fromFields((await r.json()).fields ?? {});
}

/// Toate documentele din `users/<uid>/secrets`: [{ id, data }].
export async function listSecrets(session) {
  const out = [];
  let page = '';
  do {
    const url = `${DOCS}/users/${session.uid}/secrets?pageSize=300${page ? `&pageToken=${encodeURIComponent(page)}` : ''}`;
    const r = await fetch(url, { headers: auth(session) });
    if (!r.ok) throw new Error(`Nu am putut citi parolele (${r.status}).`);
    const d = await r.json();
    for (const doc of d.documents ?? []) {
      out.push({
        id: doc.name.split('/').pop(),
        data: fromFields(doc.fields ?? {}),
      });
    }
    page = d.nextPageToken ?? '';
  } while (page);
  return out;
}

/// Scrie (înlocuiește) documentul criptat, ca `set({'enc': ...})` din app.
export async function putSecret(session, id, encB64) {
  const r = await fetch(`${DOCS}/users/${session.uid}/secrets/${id}`, {
    method: 'PATCH',
    headers: { ...auth(session), 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields: { enc: { stringValue: encB64 } } }),
  });
  if (!r.ok) throw new Error(`Salvarea a eșuat (${r.status}).`);
}

/// Ștergere ca în aplicație: „piatră funerară” cu data ștergerii.
export async function deleteSecret(session, id) {
  const r = await fetch(`${DOCS}/users/${session.uid}/secrets/${id}`, {
    method: 'PATCH',
    headers: { ...auth(session), 'Content-Type': 'application/json' },
    body: JSON.stringify({
      fields: {
        deleted: { booleanValue: true },
        updatedAt: { integerValue: String(Date.now()) },
      },
    }),
  });
  if (!r.ok) throw new Error(`Ștergerea a eșuat (${r.status}).`);
}
