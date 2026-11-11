// Partea centrală a extensiei: conectarea, seiful deblocat, salvarea și
// furnizarea parolelor.
//
// Siguranță:
// - cheia de date și parolele decriptate stau DOAR în chrome.storage.session
//   (în memorie, șterse la închiderea browserului) și sunt accesibile doar
//   paginilor extensiei, nu și paginilor web;
// - seiful se blochează singur după 15 minute fără folosire;
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
import { matches, siteTitle, hostOf } from './lib/domain.js';

const LOCK_AFTER_MS = 15 * 60 * 1000;
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
  const { email = '', autoSave = true } = await L.get(['email', 'autoSave']);
  return { email, autoSave };
}

async function authSession() {
  let { session } = await getS('session');
  if (!session) throw new fb.AuthError('Nu ești conectat.');
  if (Date.now() > session.expiresAt) {
    session = await fb.refresh(session);
    await S.set({ session });
  }
  return session;
}

async function dataKey() {
  const { dataKey: k, lastUsed = 0 } = await getS('dataKey', 'lastUsed');
  if (!k) return null;
  if (Date.now() - lastUsed > LOCK_AFTER_MS) {
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
  const unlocked = !!k && Date.now() - lastUsed <= LOCK_AFTER_MS;
  if (k && !unlocked) await lock();
  const { email, autoSave } = await settings();
  return { loggedIn: !!session, unlocked, email, autoSave };
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
  await S.set({ items, itemsAt: Date.now() });
  return items;
}

async function openVault(password, session) {
  const keys = await fb.getKeysDoc(session);
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

async function login(email, password) {
  const session = await fb.signIn(email.trim(), password);
  await S.set({ session });
  await L.set({ email: email.trim() });
  await openVault(password, session);
}

async function unlock(password) {
  const session = await authSession();
  await openVault(password, session);
}

async function logout() {
  await S.clear();
  await updateBadge();
}

async function items({ fresh = false } = {}) {
  const key = await dataKey();
  if (!key) return null;
  const { items = [], itemsAt = 0 } = await getS('items', 'itemsAt');
  if (fresh || Date.now() - itemsAt > 2 * 60 * 1000) {
    try {
      return await loadItems(key, await authSession());
    } catch {
      return items; // fără internet: ce avem
    }
  }
  return items;
}

// -------------------------------------------------- salvare și anulare

async function writeItem(key, session, m) {
  await fb.putSecret(session, m.id, await encryptMap(key, m, `secrets/${m.id}`));
  const { items = [] } = await getS('items');
  await S.set({ items: [...items.filter((i) => i.id !== m.id), m] });
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
async function existingLogin(url, username) {
  const all = (await items()) ?? [];
  const user = (username || '').trim().toLowerCase();
  return all.find(
    (i) =>
      i.type === 'login' &&
      matches(i, url) &&
      (i.username || '').trim().toLowerCase() === user,
  );
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
  const all = (await items()) ?? [];
  const user = (username || '').trim();
  const same = all.filter(
    (i) =>
      i.type === 'login' &&
      matches(i, url) &&
      (i.username || '').trim().toLowerCase() === user.toLowerCase(),
  );
  const existing = same[0];
  if (existing) {
    if (existing.password === password) {
      return { result: 'same', id: existing.id };
    }
    const now = Date.now();
    const before = structuredClone(existing);
    const updated = {
      ...existing,
      password,
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

function publicItem(i, url) {
  return {
    id: i.id,
    title: i.title || hostOf(i.url) || 'Fără titlu',
    username: i.username || '',
    url: i.url || '',
    hasPassword: !!i.password,
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
    const old = st.unlocked ? await existingLogin(tabUrl, username) : null;
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
    case 'login':
      if (!fromExtension(sender)) return null;
      await login(msg.email, msg.password);
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
    case 'list': {
      if (!fromExtension(sender)) return null;
      const all = await items({ fresh: !!msg.fresh });
      if (!all) return null;
      await touch();
      return all
        .map((i) => publicItem(i, msg.url))
        .sort(
          (a, b) =>
            Number(b.match) - Number(a.match) ||
            a.title.localeCompare(b.title, 'ro'),
        );
    }
    case 'reveal': {
      // doar pentru copiere din fereastra extensiei
      if (!fromExtension(sender)) return null;
      const all = await items();
      const i = all?.find((x) => x.id === msg.id);
      if (!i) return null;
      await touch();
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
      return {
        locked: false,
        secure: pageAllowed(tabUrl),
        items: all
          .filter((i) => i.type === 'login' && matches(i, tabUrl))
          .map((i) => publicItem(i, tabUrl)),
      };
    }
    case 'fill': {
      // parola merge DOAR spre site-ul ei, prin HTTPS, cadrul principal
      if (sender.frameId !== 0 || !pageAllowed(tabUrl)) return null;
      const all = await items();
      const i = all?.find((x) => x.id === msg.id);
      if (!i || !matches(i, tabUrl)) return null;
      await touch();
      return { username: i.username, password: i.password };
    }
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
