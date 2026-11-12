// Partea centrală a extensiei: conectarea, seiful deblocat, salvarea și
// furnizarea parolelor.
//
// Siguranță:
// - cheia de date și parolele decriptate stau DOAR în chrome.storage.session
//   (în memorie, șterse la închiderea browserului) și sunt accesibile doar
//   paginilor extensiei, nu și paginilor web;
// - seiful rămâne deschis până la închiderea browserului; opțional se
//   blochează singur după N minute fără folosire (Setări);
// - pe disc rămâne doar conectarea la cont (uid + jetonul de reîmprospătare,
//   ca aplicația de pe telefon), ca după repornirea browserului să ceară
//   doar parola Notițe; fără parolă nu se poate decripta nimic;
// - o pagină web primește o parolă doar pentru propriul ei site, doar în
//   cadrul principal și doar prin HTTPS (sau localhost);
// - nimic din toate acestea nu ajunge în cloud necriptat.

import {
  unwrapDataKey,
  importDataKey,
  decryptMap,
  encryptMap,
  b64encode,
  b64decode,
  uuid,
} from './lib/crypto.js';
import * as fb from './lib/firebase.js';
import { matches, siteTitle, hostOf, baseDomain } from './lib/domain.js';
import { totpCode } from './lib/totp.js';
import { healthOf, sha1Hex, pwned } from './lib/health.js';

/// Blocare automată după atâtea minute fără folosire; 0 = niciodată
/// (doar la închiderea browserului).
const LOCK_CHOICES = [0, 15, 60, 240];

async function lockAfterMs() {
  const { lockMinutes = 0 } = await L.get('lockMinutes');
  return lockMinutes > 0 ? lockMinutes * 60 * 1000 : Infinity;
}
const CLIPBOARD_CLEAR_MS = 30 * 1000;
const LOGIN_TYPES = new Set(['login', 'subscription']);

chrome.storage.session.setAccessLevel?.({
  accessLevel: 'TRUSTED_CONTEXTS',
});

// ------------------------------------------------------------- stare

const S = chrome.storage.session;
const L = chrome.storage.local;

async function getS(...keys) {
  return S.get(keys);
}

async function touch() {
  await S.set({ lastUsed: Date.now() });
}

async function settings() {
  const {
    email = '',
    autoSave = true,
    lockMinutes = 0,
  } = await L.get(['email', 'autoSave', 'lockMinutes']);
  return { email, autoSave, lockMinutes };
}

/// Conectarea ținută minte pe disc: doar uid și jetonul de reîmprospătare.
async function savedAccount() {
  const { account } = await L.get('account');
  return account?.uid && account?.refreshToken ? account : null;
}

async function rememberAccount(session) {
  await L.set({
    account: { uid: session.uid, refreshToken: session.refreshToken },
  });
}

async function authSession({ force = false } = {}) {
  let { session } = await getS('session');
  if (!session) {
    const account = await savedAccount();
    if (!account) throw new fb.AuthError('Nu ești conectat.');
    session = { ...account, idToken: '', expiresAt: 0 };
  }
  if (force || Date.now() > session.expiresAt) {
    try {
      session = await fb.refresh(session);
    } catch (e) {
      // jeton revocat (parolă schimbată, 2FA resetat…): conectare de la zero
      if (e instanceof fb.AuthError) {
        await S.remove('session');
        await L.remove('account');
      }
      throw e;
    }
    await S.set({ session });
    await rememberAccount(session);
  }
  return session;
}

async function dataKey() {
  const { dataKey: k, lastUsed = 0 } = await getS('dataKey', 'lastUsed');
  if (!k) return null;
  if (Date.now() - lastUsed > (await lockAfterMs())) {
    await lock();
    return null;
  }
  return importDataKey(b64decode(k));
}

async function lock() {
  await S.remove(['dataKey', 'items']);
  await updateBadge();
}

async function status() {
  const { session, dataKey: k, lastUsed = 0 } = await getS(
    'session',
    'dataKey',
    'lastUsed',
  );
  const unlocked = !!k && Date.now() - lastUsed <= (await lockAfterMs());
  if (k && !unlocked) await lock();
  const { email, autoSave, lockMinutes } = await settings();
  const pending = await pendingLogin();
  return {
    loggedIn: !!session || !!(await savedAccount()),
    unlocked,
    email,
    autoSave,
    lockMinutes,
    awaitingCode: pending ? pending.email : null,
  };
}

/// Conectare oprită la codul 2FA. Pe iPhone fereastra extensiei se închide
/// cât copiezi codul din aplicația de autentificare, așa că ținem minte (doar
/// în memorie, max. 3 minute) emailul și parola până vine codul.
const PENDING_LOGIN_MS = 3 * 60 * 1000;

async function pendingLogin() {
  const { pendingLogin: p } = await getS('pendingLogin');
  if (!p) return null;
  if (Date.now() - p.at > PENDING_LOGIN_MS) {
    await S.remove('pendingLogin');
    return null;
  }
  return p;
}

async function updateBadge() {
  const { dataKey: k, pending = [] } = await getS('dataKey', 'pending');
  const text = pending.length ? String(pending.length) : k ? '' : '🔒';
  await chrome.action.setBadgeText({ text: pending.length ? text : '' });
  await chrome.action.setBadgeBackgroundColor({ color: '#3F8F6B' });
  await chrome.action.setTitle({
    title: k ? 'Notițe – Parole (deblocat)' : 'Notițe – Parole (blocat)',
  });
}

// ------------------------------------------- conectare și deblocare

async function loadItems(key, session) {
  const version = await fb.getSecretsVersion(session).catch(() => 0);
  const docs = await fb.listSecrets(session);
  const items = [];
  for (const d of docs) {
    if (d.data.deleted || !d.data.enc) continue;
    try {
      const m = await decryptMap(key, d.data.enc, `secrets/${d.id}`);
      if (LOGIN_TYPES.has(m.type)) items.push(m);
    } catch {
      // document stricat sau al altei chei: îl ignorăm
    }
  }
  await S.set({ items, itemsAt: Date.now(), itemsVersion: version, checkedAt: Date.now() });
  return items;
}

async function openVault(password, session) {
  let keys;
  try {
    keys = await fb.getKeysDoc(session);
  } catch (e) {
    if (!/\(401\)/.test(e.message)) throw e;
    // acces expirat/respins: îl reîmprospătăm o dată și reîncercăm
    session = await authSession({ force: true });
    keys = await fb.getKeysDoc(session);
  }
  if (!keys?.password) {
    throw new Error(
      'Contul nu are încă seiful creat. Deschide o dată aplicația Notițe.',
    );
  }
  const bytes = await unwrapDataKey(keys.password, password);
  if (!bytes) {
    throw new Error(
      'Parola nu deschide seiful (a fost schimbată?). Folosește parola din aplicație.',
    );
  }
  await S.set({
    dataKey: b64encode(bytes),
    wrapped: keys.password,
    lastUsed: Date.now(),
  });
  await loadItems(await importDataKey(bytes), session);
  await savePending();
  await updateBadge();
}

async function login(email, password, code) {
  const session = await fb.signIn(email.trim(), password, code);
  await S.set({ session });
  await rememberAccount(session);
  await L.set({ email: email.trim() });
  await openVault(password, session);
}

async function unlock(password) {
  const session = await authSession();
  await openVault(password, session);
}

async function logout() {
  await S.clear();
  await L.remove('account');
  await updateBadge();
}

async function items({ fresh = false } = {}) {
  const key = await dataKey();
  if (!key) return null;
  // Citim TOATE parolele doar dacă s-a schimbat ceva (versiunea din
  // keys/secretsVersion), verificată cel mult o dată pe minut — altfel
  // cota zilnică Firebase (50.000 de citiri) se termină repede.
  const {
    items = [],
    itemsVersion = -1,
    checkedAt = 0,
    itemsAt = 0,
  } = await getS('items', 'itemsVersion', 'checkedAt', 'itemsAt');
  if (!fresh && Date.now() - checkedAt < 60 * 1000) return items;
  try {
    const session = await authSession();
    const v = await fb.getSecretsVersion(session);
    await S.set({ checkedAt: Date.now() });
    // și o recitire completă la 6 ore (schimbări din versiuni vechi ale
    // aplicației, care nu actualizează versiunea)
    const recent = Date.now() - itemsAt < 6 * 60 * 60 * 1000;
    if (v === itemsVersion && itemsVersion !== -1 && recent) return items;
    return await loadItems(key, session);
  } catch {
    return items; // fără internet / cotă depășită: ce avem
  }
}

// -------------------------------------------------- salvare și anulare

async function writeItem(key, session, m) {
  await fb.putSecret(session, m.id, await encryptMap(key, m, `secrets/${m.id}`));
  const { items = [] } = await getS('items');
  await S.set({ items: [...items.filter((i) => i.id !== m.id), m] });
  await bumpVersion(session);
}

/// După o scriere: anunță aplicația (versiune nouă) și ține copia locală
/// la zi fără să recitim totul.
async function bumpVersion(session) {
  const v = await fb.bumpSecretsVersion(session).catch(() => 0);
  if (v) await S.set({ itemsVersion: v, checkedAt: Date.now() });
}

function newLogin(url, username, password) {
  const now = Date.now();
  let origin = '';
  try {
    origin = new URL(url).origin;
  } catch {}
  return {
    id: uuid(),
    type: 'login',
    title: siteTitle(url),
    url: origin,
    username,
    password,
    totp: '',
    notes: 'Salvat din browser de extensia Notițe.',
    custom: [],
    passwordHistory: [],
    favorite: false,
    createdAt: now,
    updatedAt: now,
    passwordChangedAt: now,
  };
}

/// Contul existent pentru site + utilizator (dacă există).
/// Dubluri (același utilizator pe același site, ex. un import vechi + unul
/// salvat din browser): pe pagină arătăm doar contul cu parola cea mai nouă,
/// ca să nu alegi din greșeală parola veche. Cele mai noi primele.
function newestPerUser(list) {
  const when = (i) => i.passwordChangedAt || i.updatedAt || i.createdAt || 0;
  const best = new Map();
  for (const i of list) {
    const k = (i.username || '').trim().toLowerCase();
    const b = best.get(k);
    if (!b || when(i) > when(b)) best.set(k, i);
  }
  return [...best.values()].sort((a, b) => when(b) - when(a));
}

/// Contul ales de tine pe site (din panoul Notițe sau „Completează”):
/// parola generată / schimbată se salvează PE EL, nu pe alt cont al
/// aceluiași site. Ținut minte 30 de minute, în memorie.
const CHOSEN_MS = 30 * 60 * 1000;

async function choose(url, id) {
  const { chosen = {} } = await getS('chosen');
  chosen[hostOf(url)] = { id, at: Date.now() };
  await S.set({ chosen });
}

async function chosenFor(url) {
  const { chosen = {} } = await getS('chosen');
  const c = chosen[hostOf(url)];
  return c && Date.now() - c.at < CHOSEN_MS ? c.id : null;
}

async function existingLogin(url, username, { change = false } = {}) {
  const all = (await items()) ?? [];
  const user = (username || '').trim().toLowerCase();
  const site = all.filter((i) => i.type === 'login' && matches(i, url));
  const cid = await chosenFor(url);
  const pick = cid && site.find((i) => i.id === cid);
  if (pick && (!user || (pick.username || '').trim().toLowerCase() === user)) {
    return pick;
  }
  const exact = site.find(
    (i) => (i.username || '').trim().toLowerCase() === user,
  );
  if (exact) return exact;
  // formular de schimbare a parolei: utilizatorul nu apare pe pagină
  if (change && site.length === 1) return site[0];
  return undefined;
}

/// Parolă generată de Notițe pe o pagină: o ținem minte ÎNAINTE de
/// trimitere, în contul site-ului (ca „schimbare neterminată” — aplicația o
/// arată și o poate confirma). Nu se mai pierde dacă site-ul se blochează,
/// dai de două ori clic sau închizi fila.
async function rememberGenerated(tabUrl, username, password) {
  const key = await dataKey();
  if (!key) return { result: 'locked' };
  const session = await authSession();
  const old = await existingLogin(tabUrl, username, { change: true });
  // Nu știm sigur contul (mai multe conturi pe site): o ținem minte la
  // TOATE — e doar „neconfirmată”, nu înlocuiește nimic; o confirmi la cel
  // corect. Niciun cont pe site: cont nou cu parola generată.
  const all = (await items()) ?? [];
  let targets = old
    ? [old]
    : all.filter((i) => i.type === 'login' && matches(i, tabUrl));
  if (!targets.length) {
    // același nume de site pe alt domeniu (aliexpress.us ↔ aliexpress.com):
    // doar pentru a ține minte parola, nu pentru completare
    const label = baseDomain(tabUrl).split('.')[0];
    const nameOf = (i) =>
      i.url
        ? baseDomain(i.url).split('.')[0]
        : (i.title || '').toLowerCase().replace(/[^a-z0-9]/g, '');
    targets = all.filter(
      (i) => i.type === 'login' && label.length >= 3 && nameOf(i) === label,
    );
  }
  if (!targets.length) {
    const m = {
      ...newLogin(tabUrl, (username || '').trim(), password),
      pendingPassword: password,
      notes:
        'Parolă generată de extensia Notițe. Dacă site-ul a acceptat-o, ' +
        'confirm-o; altfel șterge contul.',
    };
    await writeItem(key, session, m);
    return { result: 'kept', id: m.id, count: 1 };
  }
  for (const t of targets) {
    if (t.pendingPassword === password) continue;
    await writeItem(key, session, {
      ...t,
      pendingPassword: password,
      updatedAt: Date.now(),
    });
  }
  return { result: 'kept', count: targets.length };
}

/// Parola generată și neconfirmată devine cea actuală (cea veche → istoric).
async function applyPending(id, keep) {
  const key = await dataKey();
  if (!key) return { error: 'Seiful e blocat.' };
  const all = (await items()) ?? [];
  const i = all.find((x) => x.id === id);
  if (!i?.pendingPassword) return { error: 'Nu mai există parola generată.' };
  const now = Date.now();
  const p = i.pendingPassword;
  const updated = keep
    ? {
        ...i,
        password: p,
        pendingPassword: '',
        updatedAt: now,
        passwordChangedAt: now,
        passwordHistory: [
          ...(i.password ? [{ password: i.password, until: now }] : []),
          ...(i.passwordHistory ?? []).filter((h) => h.password !== p),
        ].slice(0, 10),
      }
    : { ...i, pendingPassword: '', updatedAt: now };
  await writeItem(key, await authSession(), updated);
  // aceeași parolă ținută minte și la alte conturi ale site-ului: o scoatem
  if (keep) {
    for (const o of all) {
      if (o.id !== id && o.pendingPassword === p) {
        await writeItem(key, await authSession(), {
          ...o,
          pendingPassword: '',
          updatedAt: now,
        });
      }
    }
  }
  await touch();
  return { ok: true };
}

/// Parolele prinse și nesalvate expiră după 30 de minute.
const PENDING_TTL_MS = 30 * 60 * 1000;
async function freshPending() {
  const { pending = [] } = await getS('pending');
  const keep = pending.filter((p) => Date.now() - p.at < PENDING_TTL_MS);
  if (keep.length !== pending.length) await S.set({ pending: keep });
  return keep;
}

/// Salvează (sau actualizează) o parolă folosită pe [url].
/// → { result: 'new'|'updated'|'same', id, undo }
async function saveCredential(url, username, password) {
  const key = await dataKey();
  if (!key) return null;
  const session = await authSession();
  const user = (username || '').trim();
  const existing = await existingLogin(url, user, { change: !user });
  if (existing) {
    if (existing.password === password) {
      return { result: 'same', id: existing.id };
    }
    const now = Date.now();
    const before = structuredClone(existing);
    const updated = {
      ...existing,
      password,
      pendingPassword:
        existing.pendingPassword === password ? '' : existing.pendingPassword ?? '',
      updatedAt: now,
      passwordChangedAt: now,
      passwordHistory: [
        ...(existing.password
          ? [{ password: existing.password, until: now }]
          : []),
        ...(existing.passwordHistory ?? []).filter(
          (p) => p.password !== password,
        ),
      ].slice(0, 10),
    };
    await writeItem(key, session, updated);
    return { result: 'updated', id: updated.id, undo: { restore: before } };
  }
  const m = newLogin(url, user, password);
  await writeItem(key, session, m);
  return { result: 'new', id: m.id, undo: { remove: m.id } };
}

async function undo(u) {
  const key = await dataKey();
  if (!key || !u) return;
  const session = await authSession();
  if (u.remove) {
    await fb.deleteSecret(session, u.remove);
    const { items = [] } = await getS('items');
    await S.set({ items: items.filter((i) => i.id !== u.remove) });
    await bumpVersion(session);
  } else if (u.restore) {
    await writeItem(key, session, { ...u.restore, updatedAt: Date.now() });
  }
}

/// Parole prinse cât timp seiful era blocat: se salvează la deblocare.
async function savePending() {
  const pending = await freshPending();
  if (!pending.length) return;
  const { autoSave } = await settings();
  if (!autoSave) return; // le confirmă userul din fereastra extensiei
  const keep = [];
  for (const p of pending) {
    try {
      // conturile noi se salvează; schimbările de parolă le confirmă userul
      const old = await existingLogin(p.url, p.username);
      if (old && old.password !== p.password) keep.push(p);
      else if (!old) await saveCredential(p.url, p.username, p.password);
    } catch {
      keep.push(p);
    }
  }
  await S.set({ pending: keep });
}

// ----------------------------------------------- reguli de siguranță

function pageAllowed(url) {
  try {
    const u = new URL(url);
    return (
      u.protocol === 'https:' ||
      (u.protocol === 'http:' &&
        ['localhost', '127.0.0.1'].includes(u.hostname))
    );
  } catch {
    return false;
  }
}

/// Mesajul vine dintr-o pagină a extensiei (fereastra ei), nu de pe un
/// site: doar acolo se pot cere parolele pentru copiere.
function fromExtension(sender) {
  return (
    sender.id === chrome.runtime.id &&
    typeof sender.url === 'string' &&
    sender.url.startsWith(chrome.runtime.getURL(''))
  );
}

// ------------------------------------------- starea parolelor (punct)

/// id → 'red' | 'yellow' | 'green'. Se calculează din parola ACTUALĂ: după
/// ce o înlocuiești cu una generată, avertizarea dispare singură.
async function healthMap(list) {
  const reuse = new Map();
  for (const i of list) {
    if (i.password) reuse.set(i.password, (reuse.get(i.password) ?? 0) + 1);
  }
  const { breaches = {} } = await getS('breaches');
  const out = new Map();
  for (const i of list) {
    const h = i.password ? await sha1Hex(i.password) : '';
    out.set(i.id, healthOf(i, reuse, breaches, h));
  }
  return out;
}

/// Verifică (în fundal, câte 8) parolele încă neverificate. Rezultatele
/// (doar amprente SHA-1 → da/nu) stau în memorie, ca și seiful.
let checking = null;
function checkBreaches(list) {
  if (checking) return checking;
  checking = (async () => {
    const { breaches = {} } = await getS('breaches');
    const all = await Promise.all(
      list.filter((i) => i.password).map((i) => sha1Hex(i.password)),
    );
    const todo = [...new Set(all)].filter((h) => !(h in breaches));
    for (let k = 0; k < todo.length; k += 8) {
      const part = todo.slice(k, k + 8);
      const res = await Promise.all(part.map(pwned));
      part.forEach((h, j) => {
        if (res[j] !== null) breaches[h] = res[j];
      });
      await S.set({ breaches });
    }
  })()
    .catch(() => {})
    .finally(() => (checking = null));
  return checking;
}

function publicItem(i, url, health = '') {
  return {
    health,
    pending: !!i.pendingPassword,
    id: i.id,
    title: i.title || hostOf(i.url) || 'Fără titlu',
    username: i.username || '',
    url: i.url || '',
    hasPassword: !!i.password,
    hasTotp: !!(i.totp || '').trim(),
    match: url ? matches(i, url) : false,
  };
}

// --------------------------------------------- clipboard (30 secunde)

async function scheduleClipboardClear() {
  await chrome.alarms.create('clearClipboard', {
    when: Date.now() + CLIPBOARD_CLEAR_MS,
  });
}

async function clearClipboard() {
  try {
    if (!(await chrome.offscreen.hasDocument?.())) {
      await chrome.offscreen.createDocument({
        url: 'offscreen.html',
        reasons: ['CLIPBOARD'],
        justification: 'Șterge parola copiată din clipboard după 30 s.',
      });
    }
    await chrome.runtime.sendMessage({ type: 'offscreen-clear' });
  } catch {}
}

/// Toate operațiile de salvare, una după alta (fără dubluri, fără
/// scrieri amestecate).
let chain = Promise.resolve();
function serial(fn) {
  const p = chain.then(fn, fn);
  chain = p.catch(() => {});
  return p;
}

async function captured(msg, tabUrl, tabId) {
    let username = (msg.username || '').trim();
    const hint = usernameHint.get(tabId);
    if (!username && hint && matches({ url: hint.url }, tabUrl)) {
      username = hint.username;
    }
    // aceeași trimitere prinsă de două ori (click + submit)
    const sig = `${hostOf(tabUrl)}|${username}|${msg.password}`;
    const prev = recent.get(tabId);
    if (prev && prev.sig === sig && Date.now() - prev.at < 15000) {
      return prev.reply;
    }
    const st = await status();
    let reply;
    // Cont existent cu altă parolă: poate fi o parolă greșită tastată la
    // logare, deci NU o schimbăm singuri — întrebăm.
    const old = st.unlocked
      ? await existingLogin(tabUrl, username, { change: !!msg.change })
      : null;
    if (old && !username) username = old.username || '';
    const changed = !!old && old.password !== msg.password;
    if (!st.loggedIn) {
      reply = { result: 'loggedOut' };
    } else if (old && !changed) {
      reply = { result: 'same', id: old.id };
    } else if (!st.unlocked || !st.autoSave || changed) {
      // o păstrăm (în memorie) până o confirmă/deblochează userul
      const { pending = [] } = await getS('pending');
      const p = { url: tabUrl, username, password: msg.password, at: Date.now() };
      await S.set({
        pending: [
          ...pending.filter(
            (x) => !(matches({ url: x.url }, tabUrl) && x.username === username),
          ),
          p,
        ].slice(-20),
      });
      await updateBadge();
      reply = {
        result: !st.unlocked ? 'locked' : changed ? 'askUpdate' : 'ask',
      };
    } else {
      await touch();
      reply = await saveCredential(tabUrl, username, msg.password);
    }
    const info = { ...reply, username, site: siteTitle(tabUrl) };
    recent.set(tabId, { sig, at: Date.now(), reply: info });
    // mesajul se arată și pe pagina următoare (logarea navighează)
    if (tabId != null && reply?.result && reply.result !== 'same') {
      await S.set({ [`toast_${tabId}`]: { ...info, at: Date.now() } });
    }
    return info;
}

// ------------------------------------------------------------- mesaje

const recent = new Map(); // tabId → ultima captură (anti-dublură)
const usernameHint = new Map(); // tabId → utilizatorul din pasul anterior

async function handle(msg, sender) {
  const tabUrl = sender.tab?.url ?? '';
  const tabId = sender.tab?.id;

  switch (msg.type) {
    // ---- fereastra extensiei (popup)
    case 'status':
      return status();
    case 'login': {
      if (!fromExtension(sender)) return null;
      // doar codul: continuăm conectarea începută (fereastra s-a închis)
      const p = !msg.password && msg.code ? await pendingLogin() : null;
      const email = p ? p.email : msg.email;
      const password = p ? p.password : msg.password;
      try {
        await login(email, password, msg.code);
      } catch (e) {
        if (e instanceof fb.MfaRequired) {
          await S.set({ pendingLogin: { email, password, at: Date.now() } });
          return { needCode: true };
        }
        throw e;
      }
      await S.remove('pendingLogin');
      return status();
    }
    case 'cancelLogin':
      if (!fromExtension(sender)) return null;
      await S.remove('pendingLogin');
      return status();
    case 'unlock':
      if (!fromExtension(sender)) return null;
      await unlock(msg.password);
      return status();
    case 'lock':
      await lock();
      return status();
    case 'logout':
      if (!fromExtension(sender)) return null;
      await logout();
      return status();
    case 'setAutoSave':
      if (!fromExtension(sender)) return null;
      await L.set({ autoSave: !!msg.value });
      return status();
    case 'setLockMinutes':
      if (!fromExtension(sender)) return null;
      if (LOCK_CHOICES.includes(Number(msg.value))) {
        await S.set({ lastUsed: Date.now() });
        await L.set({ lockMinutes: Number(msg.value) });
      }
      return status();
    case 'list': {
      if (!fromExtension(sender)) return null;
      const all = await items({ fresh: !!msg.fresh });
      if (!all) return null;
      await touch();
      checkBreaches(all);
      const hm = await healthMap(all);
      return all
        .map((i) => publicItem(i, msg.url, hm.get(i.id)))
        .sort(
          (a, b) =>
            Number(b.match) - Number(a.match) ||
            a.title.localeCompare(b.title, 'ro'),
        );
    }
    case 'getItem': {
      // editare din fereastra extensiei
      if (!fromExtension(sender)) return null;
      const all = await items();
      const i = all?.find((x) => x.id === msg.id);
      if (!i) return null;
      await touch();
      return {
        id: i.id,
        title: i.title || '',
        username: i.username || '',
        password: i.password || '',
        url: i.url || '',
      };
    }
    case 'updateItem': {
      if (!fromExtension(sender)) return null;
      const key = await dataKey();
      if (!key) return { error: 'Seiful e blocat.' };
      const all = (await items()) ?? [];
      const i = all.find((x) => x.id === msg.id);
      if (!i) return { error: 'Nu am găsit contul.' };
      const now = Date.now();
      const password = String(msg.password ?? '');
      const changed = password !== (i.password || '');
      const updated = {
        ...i,
        title: String(msg.title ?? '').trim(),
        username: String(msg.username ?? '').trim(),
        url: String(msg.url ?? '').trim(),
        password,
        updatedAt: now,
        ...(changed
          ? {
              passwordChangedAt: now,
              pendingPassword:
                i.pendingPassword === password ? '' : i.pendingPassword ?? '',
              passwordHistory: [
                ...(i.password ? [{ password: i.password, until: now }] : []),
                ...(i.passwordHistory ?? []).filter(
                  (p) => p.password !== password,
                ),
              ].slice(0, 10),
            }
          : {}),
      };
      await writeItem(key, await authSession(), updated);
      await touch();
      return { ok: true };
    }
    case 'getPending': {
      if (!fromExtension(sender)) return null;
      const all = await items();
      const i = all?.find((x) => x.id === msg.id);
      if (!i?.pendingPassword) return null;
      await touch();
      await scheduleClipboardClear();
      return i.pendingPassword;
    }
    case 'applyPending':
      if (!fromExtension(sender)) return null;
      return applyPending(msg.id, !!msg.keep);
    case 'deleteItem': {
      if (!fromExtension(sender)) return null;
      const key = await dataKey();
      if (!key) return { error: 'Seiful e blocat.' };
      const sess = await authSession();
      await fb.deleteSecret(sess, msg.id);
      const { items: list = [] } = await getS('items');
      await S.set({ items: list.filter((i) => i.id !== msg.id) });
      await bumpVersion(sess);
      await touch();
      return { ok: true };
    }
    case 'reveal': {
      // doar pentru copiere din fereastra extensiei
      if (!fromExtension(sender)) return null;
      const all = await items();
      const i = all?.find((x) => x.id === msg.id);
      if (!i) return null;
      await touch();
      if (msg.field === 'totp') {
        await scheduleClipboardClear();
        return (await totpCode(i.totp))?.code ?? null;
      }
      if (msg.field === 'password') await scheduleClipboardClear();
      return msg.field === 'password' ? i.password : i.username;
    }
    case 'fillTab': {
      // „Completează” din fereastra extensiei, pe pagina deschisă
      if (!fromExtension(sender)) return null;
      const [tab] = await chrome.tabs.query({
        active: true,
        currentWindow: true,
      });
      const all = await items();
      const i = all?.find((x) => x.id === msg.id);
      if (!tab || !i) return { error: 'Nu am găsit intrarea.' };
      if (!pageAllowed(tab.url)) {
        return { error: 'Pagina nu e securizată (HTTPS); nu completez.' };
      }
      if (!matches(i, tab.url)) {
        return { error: 'Contul nu e pentru site-ul deschis.' };
      }
      await touch();
      await choose(tab.url, i.id);
      await chrome.tabs.sendMessage(
        tab.id,
        { type: 'doFill', username: i.username, password: i.password },
        { frameId: 0 },
      );
      return { ok: true };
    }
    case 'pending': {
      if (!fromExtension(sender)) return null;
      const pending = await freshPending();
      const out = [];
      for (const p of pending) {
        const old = (await status()).unlocked
          ? await existingLogin(p.url, p.username)
          : null;
        // fără parole spre fereastră: doar site și utilizator
        out.push({
          site: siteTitle(p.url),
          username: p.username,
          update: !!old,
        });
      }
      return out;
    }
    case 'savePending': {
      if (!fromExtension(sender)) return null;
      const pending = await freshPending();
      const keep = [];
      for (const [n, p] of pending.entries()) {
        if (n === msg.index) {
          if (msg.save) await saveCredential(p.url, p.username, p.password);
        } else keep.push(p);
      }
      await S.set({ pending: keep });
      await updateBadge();
      return keep;
    }

    // ---- paginile web (content.js)
    case 'pageLogins': {
      if (!tabUrl || sender.frameId !== 0) return { locked: true, items: [] };
      const st = await status();
      if (!st.unlocked) return { locked: true, loggedIn: st.loggedIn, items: [] };
      const all = (await items()) ?? [];
      checkBreaches(all);
      const hm = await healthMap(all);
      return {
        locked: false,
        secure: pageAllowed(tabUrl),
        items: newestPerUser(
          all.filter((i) => i.type === 'login' && matches(i, tabUrl)),
        ).map((i) => publicItem(i, tabUrl, hm.get(i.id))),
      };
    }
    case 'pageTotp': {
      // codul 2FA doar pentru site-ul lui, prin HTTPS, cadrul principal
      if (sender.frameId !== 0 || !pageAllowed(tabUrl)) return null;
      const st = await status();
      if (!st.unlocked) return { locked: true, loggedIn: st.loggedIn, items: [] };
      const all = (await items()) ?? [];
      const out = [];
      for (const i of all) {
        if (!(i.totp || '').trim() || !matches(i, tabUrl)) continue;
        const r = await totpCode(i.totp);
        if (r) out.push({ id: i.id, title: i.title, username: i.username, ...r });
      }
      if (out.length) await touch();
      return { locked: false, items: out };
    }
    case 'fill': {
      // parola merge DOAR spre site-ul ei, prin HTTPS, cadrul principal
      if (sender.frameId !== 0 || !pageAllowed(tabUrl)) return null;
      const all = await items();
      const i = all?.find((x) => x.id === msg.id);
      if (!i || !matches(i, tabUrl)) return null;
      await touch();
      await choose(tabUrl, i.id);
      return { username: i.username, password: i.password };
    }
    case 'generatedInPopup': {
      // „Copiază” din generatorul ferestrei extensiei: o ținem minte pentru
      // site-ul din fila deschisă
      if (!fromExtension(sender) || !msg.password) return null;
      if (!/^https?:/.test(msg.url || '')) return null;
      return serial(() => rememberGenerated(msg.url, '', msg.password));
    }
    case 'generated':
      if (!tabUrl || sender.frameId !== 0 || !msg.password) return null;
      return serial(() =>
        rememberGenerated(tabUrl, msg.username || '', msg.password),
      );
    case 'usernameStep':
      if (tabId != null && msg.username) {
        usernameHint.set(tabId, { url: tabUrl, username: msg.username });
      }
      return null;
    case 'captured': {
      if (!tabUrl || sender.frameId !== 0 || !msg.password) return null;
      // pe rând: clicul pe buton și trimiterea formularului sosesc deodată
      return serial(() => captured(msg, tabUrl, tabId));
    }
    case 'takeToast': {

      if (tabId == null) return null;
      const k = `toast_${tabId}`;
      const t = (await S.get(k))[k];
      await S.remove(k);
      return t && Date.now() - t.at < 20000 ? t : null;
    }
    case 'undo': {
      if (tabId == null) return null;
      const prev = recent.get(tabId);
      if (prev?.reply?.undo) {
        await undo(prev.reply.undo);
        recent.delete(tabId);
        return { ok: true };
      }
      return null;
    }
    case 'savePendingFromPage': {
      // butonul „Salvează” din mesajul de pe pagină (salvare cu întrebare)
      if (tabId == null) return null;
      const pending = await freshPending();
      const idx = pending.findIndex((p) => matches({ url: p.url }, tabUrl));
      if (idx < 0) return null;
      const p = pending[idx];
      const r = await saveCredential(p.url, p.username, p.password);
      pending.splice(idx, 1);
      await S.set({ pending });
      await updateBadge();
      return r;
    }
  }
  return null;
}

chrome.runtime.onMessage.addListener((msg, sender, reply) => {
  if (msg?.type?.startsWith('offscreen')) return false;
  handle(msg, sender).then(
    (r) => reply({ ok: true, data: r }),
    (e) => reply({ ok: false, error: e?.message ?? String(e) }),
  );
  return true;
});

chrome.alarms.create('lockCheck', { periodInMinutes: 1 });
chrome.alarms.onAlarm.addListener(async (a) => {
  if (a.name === 'lockCheck') await status();
  if (a.name === 'clearClipboard') await clearClipboard();
});

chrome.tabs.onRemoved.addListener((tabId) => {
  recent.delete(tabId);
  usernameHint.delete(tabId);
  S.remove(`toast_${tabId}`);
});

chrome.runtime.onStartup.addListener(updateBadge);
chrome.runtime.onInstalled.addListener(updateBadge);
