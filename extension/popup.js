// Fereastra extensiei. Nu păstrează parole: le cere de la fundal doar
// când le copiezi sau completezi.

import { baseDomain } from './lib/domain.js';
import { totpCode } from './lib/totp.js';

const $ = (id) => document.getElementById(id);

const send = (msg) =>
  new Promise((resolve, reject) =>
    chrome.runtime.sendMessage(msg, (r) => {
      if (chrome.runtime.lastError) return reject(new Error(chrome.runtime.lastError.message));
      if (!r?.ok) return reject(new Error(r?.error ?? 'Eroare'));
      resolve(r.data);
    }),
  );

let msgTimer = 0;
function say(text, err = false) {
  const m = $('msg');
  m.textContent = text;
  m.className = err ? 'msg err' : 'msg';
  m.hidden = false;
  clearTimeout(msgTimer);
  msgTimer = setTimeout(() => (m.hidden = true), err ? 6000 : 2500);
}

function show(view) {
  for (const v of ['vLogin', 'vLocked', 'vMain']) $(v).hidden = v !== view;
  $('lockBtn').hidden = view !== 'vMain';
}

async function activeUrl() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab?.url ?? '';
}

let all = [];

const HEALTH_TIP = {
  red: 'Compromisă: apare în scurgeri de date — schimb-o',
  yellow: 'Slabă sau folosită și la alt cont',
  green: 'În regulă',
  ignored: 'Ignorat în aplicație (nu mai e verificat)',
};

/// Adresa site-ului (doar http/https), sau null.
function siteUrl(raw) {
  const u = (raw || '').trim();
  if (!u) return null;
  try {
    const url = new URL(u.includes('://') ? u : `https://${u}`);
    return /^https?:$/.test(url.protocol) && url.hostname.includes('.') ? url : null;
  } catch {
    return null;
  }
}

/// Un cont deschis pentru editare / ștergere: actualizările din fundal nu
/// redesenează lista (altfel formularul s-ar închide singur).
let editing = false;
let healthFilter = '';

function renderFilters() {
  const box = $('filters');
  if (!box) return;
  const red = all.filter((i) => i.health === 'red').length;
  const yellow = all.filter((i) => i.health === 'yellow').length;
  const chip = (value, label) => {
    const b = document.createElement('button');
    b.className = `chip${healthFilter === value ? ' on' : ''}`;
    b.textContent = label;
    b.addEventListener('click', () => {
      healthFilter = healthFilter === value ? '' : value;
      render();
    });
    return b;
  };
  // „Detalii”: motivele sub conturi doar când vrei (ținut minte)
  const details = document.createElement('button');
  details.className = `chip${showWhy ? ' on' : ''}`;
  details.textContent = 'ℹ️ Detalii';
  details.title = showWhy
    ? 'Ascunde motivele de sub conturi'
    : 'Arată de ce e o parolă compromisă, slabă sau refolosită';
  details.addEventListener('click', () => {
    showWhy = !showWhy;
    chrome.storage.local.set({ showWhy }).catch(() => {});
    render();
  });
  box.replaceChildren(
    ...(red ? [chip('red', `🔴 Compromise (${red})`)] : []),
    ...(yellow ? [chip('yellow', `🟡 Slabe / refolosite (${yellow})`)] : []),
    ...(red || yellow ? [details] : []),
  );
}

/// Motivele (slabă / aceeași parolă ca la… / în scurgeri) sub conturi.
let showWhy = false;
chrome.storage.local
  .get('showWhy')
  .then((r) => {
    if (r?.showWhy && !showWhy) {
      showWhy = true;
      if (all.length) render();
    }
  })
  .catch(() => {});

function render() {
  editing = false;
  renderFilters();
  const q = $('q').value.trim().toLowerCase();
  const list = $('list');
  // „https://”, „www.” nu contează la căutare (altfel „tp” = orice site);
  // întâi titlurile care încep cu textul căutat, apoi restul
  const plain = (i) =>
    `${i.title} ${i.username} ${i.url}`.toLowerCase().replace(/https?:\/\/|www\./g, ' ');
  const rank = (i) => {
    const t = i.title.toLowerCase();
    if (t.startsWith(q)) return 0;
    if (t.split(/[^a-z0-9ăâîșț]+/).some((w) => w.startsWith(q))) return 1;
    if (t.includes(q)) return 2;
    if ((i.username || '').toLowerCase().includes(q)) return 3;
    return 4;
  };
  const shown = all.filter(
    (i) => (!healthFilter || i.health === healthFilter) && (!q || plain(i).includes(q)),
  );
  if (q) shown.sort((a, b) => rank(a) - rank(b) || a.title.localeCompare(b.title, 'ro'));
  if (!shown.length) {
    list.innerHTML = `<div class="empty">${all.length ? 'Niciun rezultat' : 'Nicio parolă salvată încă.'}</div>`;
    return;
  }
  list.replaceChildren(...groupRows(shown, !!q));
}

/// Ordinea conturilor aceluiași site: numerele de telefon, apoi adresele
/// de email, apoi restul; fiecare alfabetic.
function userKind(u) {
  const v = (u || '').trim();
  if (/^\+?[\d\s().-]{7,}$/.test(v)) return 0;
  if (v.includes('@')) return 1;
  return 2;
}
const byUser = (a, b) =>
  userKind(a.username) - userKind(b.username) ||
  (a.username || a.title).localeCompare(b.username || b.title, 'ro');

/// Iconița site-ului (din memoria browserului, fără cereri spre alte
/// servere); fără site sau fără iconiță: inițiala, pe un cerc.
function favicon(url, label) {
  const box = document.createElement('span');
  box.className = 'fav';
  const letter = () => {
    box.textContent = (label || '?').trim().charAt(0).toUpperCase() || '?';
    box.classList.add('letter');
  };
  const site = siteUrl(url);
  if (!site) {
    letter();
    return box;
  }
  const img = document.createElement('img');
  img.alt = '';
  img.src = chrome.runtime.getURL(
    `/_favicon/?pageUrl=${encodeURIComponent(site.origin)}&size=32`,
  );
  img.addEventListener('error', () => {
    img.remove();
    letter();
  });
  box.append(img);
  return box;
}

/// Conturile grupate pe site (ca în managerele de parole): un site cu un
/// singur cont = un rând; cu mai multe = un grup care se deschide.
function groupRows(shown, searching) {
  const groups = new Map();
  for (const i of shown) {
    const key = baseDomain(i.url) || i.title.toLowerCase();
    if (!groups.has(key)) groups.set(key, { key, items: [] });
    groups.get(key).items.push(i);
  }
  const list = [...groups.values()];
  list.sort(
    (a, b) =>
      Number(b.items.some((i) => i.match)) - Number(a.items.some((i) => i.match)) ||
      a.key.localeCompare(b.key, 'ro'),
  );
  const out = [];
  for (const g of list) {
    if (g.items.length === 1) {
      out.push(makeRow(g.items[0]));
      continue;
    }
    g.items.sort(byUser);
    const first = g.items.find((i) => i.url) ?? g.items[0];
    const head = document.createElement('div');
    head.className = `grp${g.items.some((i) => i.match) ? ' match' : ''}`;
    head.tabIndex = 0;
    const name = document.createElement('span');
    name.className = 'gname';
    name.textContent = baseDomain(first.url) || first.title;
    const count = document.createElement('span');
    count.className = 'gcount';
    count.textContent = `${g.items.length}`;
    const arrow = document.createElement('span');
    arrow.className = 'garrow';
    head.append(favicon(first.url, name.textContent), name, count, arrow);
    const body = document.createElement('div');
    body.className = 'gbody';
    body.append(...g.items.map((i) => makeRow(i, true)));
    const open = searching || openGroups.has(g.key) || g.items.some((i) => i.match);
    const set = (on) => {
      body.hidden = !on;
      head.classList.toggle('open', on);
      arrow.textContent = on ? '▾' : '▸';
      if (on) openGroups.add(g.key);
      else openGroups.delete(g.key);
    };
    set(open);
    const toggle = () => set(body.hidden);
    head.addEventListener('click', toggle);
    head.addEventListener('keydown', (e) => e.key === 'Enter' && toggle());
    out.push(head, body);
  }
  return out;
}

/// Grupurile deschise rămân deschise când lista se reface.
const openGroups = new Set();

/// Un cont. În grup: utilizatorul e rândul principal, numele dedesubt.
function makeRow(i, inGroup = false) {
  const subText = i.username || i.url;
  {
      const row = document.createElement('div');
      row.className = `it${i.match ? ' match' : ''}`;
      const txt = document.createElement('div');
      txt.className = 'txt';
      const t = document.createElement('div');
      t.className = 't';
      if (i.health) {
        const dot = document.createElement('span');
        dot.className = `dot ${i.health}`;
        dot.title = i.why || HEALTH_TIP[i.health];
        t.append(dot);
      }
      t.append(document.createTextNode(i.title));
      const s = document.createElement('div');
      s.className = 's';
      s.textContent = subText;
      if (!inGroup) row.append(favicon(i.url, i.title));
      txt.append(t, s);
      // „ℹ️ Detalii” apăsat: motivul, la vedere
      const why =
        i.health === 'red'
          ? 'Apare în scurgeri de date publice: schimb-o cât mai repede'
          : i.health === 'yellow'
            ? i.why
            : '';
      if (showWhy && why) {
        const w = document.createElement('div');
        w.className = `s why${i.health === 'red' ? ' red' : ''}`;
        w.textContent = why;
        txt.append(w);
      }
      // clic pe nume / email → deschide site-ul într-o filă nouă
      const site = siteUrl(i.url);
      if (site) {
        txt.classList.add('link');
        txt.title = `Deschide ${site.host.replace(/^www\./, '')}`;
        txt.tabIndex = 0;
        const open = () => {
          chrome.tabs.create({ url: site.href });
          window.close();
        };
        txt.addEventListener('click', open);
        txt.addEventListener('keydown', (e) => e.key === 'Enter' && open());
      }
      row.append(txt);
      const btn = (label, title, fn) => {
        const b = document.createElement('button');
        b.textContent = label;
        b.title = title;
        b.addEventListener('click', fn);
        row.append(b);
      };
      if (i.match && i.hasPassword) {
        btn('↵', 'Completează pe pagină', async () => {
          const r = await send({ type: 'fillTab', id: i.id });
          if (r?.error) say(r.error, true);
          else window.close();
        });
      }
      if (i.username) {
        btn('👤', 'Copiază utilizatorul', () => copy(i.id, 'username'));
      }
      if (i.hasPassword) {
        btn('🔑', 'Copiază parola și o arată 10 secunde', async () => {
          const v = await copy(i.id, 'password');
          if (v == null) return;
          // vizibilă 10 secunde în locul utilizatorului
          clearTimeout(s.hideTimer);
          s.textContent = v;
          s.classList.add('pw');
          s.hideTimer = setTimeout(() => {
            s.textContent = subText;
            s.classList.remove('pw');
          }, 10000);
        });
      }
      if (i.hasTotp) {
        btn('', 'Copiază codul 2FA', () => copy(i.id, 'totp'));
        // iconița 2FA din aplicație
        const img = document.createElement('img');
        img.src = 'icons/auth.svg';
        img.alt = '2FA';
        img.className = 'authicon';
        row.lastElementChild.append(img);
      }
      if (i.username || i.hasPassword) {
        btn('📤', 'Trimite (WhatsApp, email, SMS)', () => shareRow(row, i));
      }
      btn('✏️', 'Editează contul', () => editRow(row, i));
      btn('🗑️', 'Șterge contul', () => confirmDelete(row, i));
      if (!i.pending) return row;
      // parolă generată pe site și neconfirmată
      const wrap = document.createElement('div');
      const note = document.createElement('div');
      note.className = 'pend';
      const text = document.createElement('div');
      text.textContent =
        `⏳ ${i.title}: ai o parolă generată neconfirmată. Dacă ai salvat-o pe site, folosește-o.`;
      const bar = document.createElement('div');
      bar.className = 'row';
      const show = document.createElement('button');
      show.className = 'sec';
      show.textContent = 'Arată';
      show.addEventListener('click', async () => {
        const d = await send({ type: 'getPending', id: i.id });
        if (d) {
          text.textContent = `⏳ Parola generată: ${d}`;
          text.classList.add('mono');
          await navigator.clipboard.writeText(d).catch(() => {});
          say('Parola generată a fost copiată.');
        }
      });
      const no = document.createElement('button');
      no.className = 'sec';
      no.textContent = 'Renunță';
      no.addEventListener('click', async () => {
        await send({ type: 'applyPending', id: i.id, keep: false });
        await load(true);
      });
      const yes = document.createElement('button');
      yes.className = 'pri';
      yes.textContent = 'Folosește-o';
      yes.addEventListener('click', async () => {
        const r = await send({ type: 'applyPending', id: i.id, keep: true });
        if (r?.error) return say(r.error, true);
        say('Parola generată e acum cea actuală; cea veche e în istoric.');
        await load(true);
      });
      bar.append(show, no, yes);
      note.append(text, bar);
      wrap.append(row, note);
      return wrap;
  }
}

/// Editare pe loc: nume, utilizator, parolă, site.
async function editRow(row, i) {
  editing = true; // înainte de așteptare: o actualizare din fundal nu-l mai închide
  const d = await send({ type: 'getItem', id: i.id });
  if (!row.isConnected) return;
  if (!d) return say('Nu am găsit contul.', true);
  const form = document.createElement('form');
  form.className = 'edit';
  const field = (label, name, value) => {
    const l = document.createElement('label');
    l.textContent = label;
    const inp = document.createElement('input');
    inp.name = name;
    inp.value = value;
    inp.autocomplete = 'off';
    inp.spellcheck = false;
    if (name === 'password') inp.className = 'mono';
    l.append(inp);
    form.append(l);
    return inp;
  };
  field('Nume', 'title', d.title);
  field('Utilizator / email', 'username', d.username);
  const pw = field('Parolă', 'password', d.password);
  field('Site', 'url', d.url);
  // cheia 2FA, cu codul de acum dedesubt (se vede pe loc dacă e bună)
  const tfa = field('Cheie 2FA (din codul QR / „Nu poți scana?”)', 'totp', d.totp ?? '');
  tfa.className = 'mono';
  const now = document.createElement('div');
  now.className = 'tfanow';
  tfa.parentElement.append(now);
  const showCode = async () => {
    const v = tfa.value.trim();
    if (!v) {
      now.textContent = '';
      tfa.setCustomValidity('');
      return;
    }
    const r = await totpCode(v);
    if (r) {
      now.textContent = `Cod acum: ${r.code.replace(/(\d{3})(?=\d)/g, '$1 ')} · încă ${r.remaining} s`;
      now.classList.remove('bad');
      tfa.setCustomValidity('');
    } else {
      now.textContent = 'Cheie 2FA invalidă (litere A–Z și cifre 2–7, sau link otpauth://).';
      now.classList.add('bad');
      tfa.setCustomValidity('Cheie 2FA invalidă');
    }
  };
  // la fiecare secundă cât formularul e pe ecran; se oprește când dispare
  const timer = setInterval(() => {
    if (form.isConnected) showCode();
    else if (form.dataset.live) clearInterval(timer);
  }, 1000);
  tfa.addEventListener('input', showCode);
  showCode();
  // câmpuri pe mai multe rânduri, ca în aplicație
  const area = (label, name, value) => {
    const l = document.createElement('label');
    l.textContent = label;
    const t = document.createElement('textarea');
    t.name = name;
    t.value = value ?? '';
    t.rows = Math.min(10, Math.max(3, t.value.split('\n').length + 1));
    t.spellcheck = false;
    l.append(t);
    form.append(l);
  };
  area('Coduri de rezervă 2FA (câte unul pe rând)', 'recoveryCodes', d.recoveryCodes);
  area('Notițe', 'notes', d.notes);
  const bar = document.createElement('div');
  bar.className = 'row';
  const gen = document.createElement('button');
  gen.type = 'button';
  gen.className = 'sec';
  gen.textContent = '🎲 Generează';
  gen.addEventListener('click', () => {
    pw.value = generate(18, true);
  });
  const cancel = document.createElement('button');
  cancel.type = 'button';
  cancel.className = 'sec';
  cancel.textContent = 'Renunță';
  cancel.addEventListener('click', () => render());
  const save = document.createElement('button');
  save.className = 'pri';
  save.textContent = 'Salvează';
  bar.append(gen, cancel, save);
  form.append(bar);
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const f = new FormData(form);
    const r = await send({
      type: 'updateItem',
      id: i.id,
      title: f.get('title'),
      username: f.get('username'),
      password: f.get('password'),
      url: f.get('url'),
      notes: f.get('notes'),
      recoveryCodes: f.get('recoveryCodes'),
      totp: f.get('totp'),
    });
    if (r?.error) return say(r.error, true);
    say(
      f.get('password') !== d.password
        ? 'Salvat. Parola veche a trecut în istoricul contului.'
        : 'Salvat.',
    );
    await load(true);
  });
  editing = true;
  row.replaceWith(form);
  form.dataset.live = '1';
  form.querySelector('input').focus();
}

/// Trimite utilizatorul și parola pe WhatsApp, email sau SMS.
async function shareRow(row, i) {
  editing = true;
  const d = await send({ type: 'getItem', id: i.id });
  if (!d) return say('Nu am găsit contul.', true);
  if (!row.isConnected) return;
  const box = document.createElement('div');
  box.className = 'pend share';
  const opt = (label, checked) => {
    const l = document.createElement('label');
    const c = document.createElement('input');
    c.type = 'checkbox';
    c.checked = checked;
    l.append(c, ` ${label}`);
    box.append(l);
    return c;
  };
  const title = document.createElement('div');
  title.innerHTML = `<b></b>`;
  title.firstChild.textContent = `Trimite „${d.title || i.title}”`;
  box.append(title);
  const withPw = d.password ? opt('Include parola', true) : { checked: false };
  const withSite = d.url ? opt('Include site-ul', true) : { checked: false };
  const preview = document.createElement('pre');
  preview.className = 'mono';
  const warn = document.createElement('div');
  warn.className = 'warn';
  warn.textContent =
    'Mesajul pleacă necriptat. După ce a fost folosit, șterge-l din conversație la amândoi.';
  const text = () =>
    [
      d.title || i.title,
      withSite.checked && d.url ? `Site: ${d.url}` : '',
      d.username ? `Utilizator: ${d.username}` : '',
      withPw.checked && d.password ? `Parolă: ${d.password}` : '',
    ]
      .filter(Boolean)
      .join('\n');
  const update = () => {
    preview.textContent = text();
    warn.hidden = !withPw.checked;
  };
  box.addEventListener('change', update);
  update();
  const bar = document.createElement('div');
  bar.className = 'row';
  const go = (label, url) => {
    const b = document.createElement('button');
    b.className = 'sec';
    b.textContent = label;
    b.addEventListener('click', () => {
      chrome.tabs.create({ url: url(encodeURIComponent(text())) });
      window.close();
    });
    bar.append(b);
  };
  go('WhatsApp', (t) => `https://wa.me/?text=${t}`);
  go('Email', (t) => `mailto:?subject=${encodeURIComponent(d.title || i.title)}&body=${t}`);
  go('SMS', (t) => `sms:?body=${t}`);
  const copyBtn = document.createElement('button');
  copyBtn.className = 'sec';
  copyBtn.textContent = 'Copiază';
  copyBtn.addEventListener('click', async () => {
    await navigator.clipboard.writeText(text());
    say('Textul a fost copiat.');
  });
  const close = document.createElement('button');
  close.className = 'pri';
  close.textContent = 'Închide';
  close.addEventListener('click', () => render());
  bar.append(copyBtn, close);
  box.append(preview, warn, bar);
  row.replaceWith(box);
}

function confirmDelete(row, i) {
  const box = document.createElement('div');
  box.className = 'pend';
  const text = document.createElement('div');
  text.textContent = `Ștergi contul ${i.title}${i.username ? ` (${i.username})` : ''}? Merge în coșul din aplicația Notițe (Parole → ⋮ → Coș), de unde îl poți recupera 30 de zile.`;
  const bar = document.createElement('div');
  bar.className = 'row';
  const no = document.createElement('button');
  no.className = 'sec';
  no.textContent = 'Nu';
  no.addEventListener('click', () => render());
  const yes = document.createElement('button');
  yes.className = 'pri danger';
  yes.textContent = 'Șterge';
  yes.addEventListener('click', async () => {
    const r = await send({ type: 'deleteItem', id: i.id });
    if (r?.error) return say(r.error, true);
    say('Contul a fost șters.');
    await load(true);
  });
  bar.append(no, yes);
  box.append(text, bar);
  editing = true;
  row.replaceWith(box);
}

async function copy(id, field) {
  try {
    const v = await send({ type: 'reveal', id, field });
    if (v == null) return say('Nu am găsit intrarea.', true);
    await navigator.clipboard.writeText(v);
    say(
      field === 'password'
        ? 'Parola a fost copiată (se șterge după 30 s).'
        : field === 'totp'
          ? `Codul 2FA ${v} a fost copiat.`
          : 'Utilizatorul a fost copiat.',
    );
    return v;
  } catch (e) {
    say(e.message, true);
    return null;
  }
}

async function renderPending() {
  const box = $('pending');
  const pending = await send({ type: 'pending' }).catch(() => []);
  box.replaceChildren(
    ...pending.map((p, index) => {
      const d = document.createElement('div');
      d.className = 'pend';
      const text = document.createElement('div');
      text.textContent = p.update
        ? `Actualizezi parola pentru ${p.site}${p.username ? ` (${p.username})` : ''}?`
        : `Salvezi parola pentru ${p.site}${p.username ? ` (${p.username})` : ''}?`;
      const row = document.createElement('div');
      row.className = 'row';
      const no = document.createElement('button');
      no.className = 'sec';
      no.textContent = 'Nu';
      const yes = document.createElement('button');
      yes.className = 'pri';
      yes.textContent = p.update ? 'Actualizează' : 'Salvează';
      no.onclick = async () => {
        await send({ type: 'savePending', index, save: false });
        renderPending();
      };
      yes.onclick = async () => {
        try {
          await send({ type: 'savePending', index, save: true });
          say('Salvat în Notițe.');
          renderPending();
          load(true);
        } catch (e) {
          say(e.message, true);
        }
      };
      row.append(no, yes);
      d.append(text, row);
      return d;
    }),
  );
}

async function load(fresh = false) {
  all = (await send({ type: 'list', url: await activeUrl(), fresh })) ?? [];
  render();
  // verificarea scurgerilor rulează în fundal (sute de conturi durează):
  // culorile se actualizează de câteva ori, fără să închidă o editare
  if (!fresh && !load.again) {
    load.again = true;
    for (const ms of [4000, 12000, 30000, 60000]) {
      setTimeout(async () => {
        const next = await send({ type: 'list', url: await activeUrl() }).catch(() => null);
        if (!next) return;
        all = next;
        if (!editing) render();
      }, ms);
    }
  }
}

// ------------------------------------------------------- generator

function generate(len, symbols) {
  const sets = ['ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789'];
  if (symbols) sets.push('!*-_.');
  const pool = sets.join('');
  const rnd = (n) => {
    const a = new Uint32Array(1);
    const max = Math.floor(0xffffffff / n) * n;
    do crypto.getRandomValues(a);
    while (a[0] >= max);
    return a[0] % n;
  };
  const chars = sets.map((s) => s[rnd(s.length)]);
  while (chars.length < len) chars.push(pool[rnd(pool.length)]);
  for (let i = chars.length - 1; i > 0; i--) {
    const j = rnd(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join('');
}

function newPassword() {
  $('genLenV').textContent = $('genLen').value;
  $('genOut').textContent = generate(Number($('genLen').value), $('genSym').checked);
}

$('genLen').addEventListener('input', newPassword);
$('genSym').addEventListener('change', newPassword);
$('genNew').addEventListener('click', newPassword);
$('genCopy').addEventListener('click', async () => {
  const password = $('genOut').textContent;
  await navigator.clipboard.writeText(password);
  // ținută minte imediat la contul site-ului deschis (neconfirmată)
  const r = await send({
    type: 'generatedInPopup',
    url: await activeUrl(),
    password,
  }).catch(() => null);
  say(
    r?.result === 'kept'
      ? 'Copiată și ținută minte în Notițe la contul acestui site (neconfirmată).'
      : 'Parola generată a fost copiată.',
  );
});

// ---------------------------------------------------------- acțiuni

async function refresh() {
  const st = await send({ type: 'status' });
  $('autoSave').checked = st.autoSave;
  $('lockMinutes').value = String(st.lockMinutes ?? -1);
  if (!st.loggedIn && st.awaitingCode) {
    // conectarea așteaptă doar codul (parola e ținută minte câteva minute)
    $('email').value = st.awaitingCode;
    $('pass').hidden = true;
    $('pass').required = false;
    $('code').hidden = false;
    $('code').required = true;
    $('cancelCode').hidden = false;
    show('vLogin');
    $('code').focus();
  } else if (!st.loggedIn) {
    $('email').value = st.email;
    $('pass').hidden = false;
    $('pass').required = true;
    $('cancelCode').hidden = true;
    show('vLogin');
    (st.email ? $('pass') : $('email')).focus();
  } else if (!st.unlocked) {
    $('who').textContent = st.email ? `(${st.email})` : '';
    show('vLocked');
    $('upass').focus();
  } else {
    show('vMain');
    await renderPending();
    await load();
    $('q').focus();
  }
}

async function busy(form, fn) {
  const b = form.querySelector('button');
  const label = b.textContent;
  b.disabled = true;
  b.textContent = 'Se deschide seiful…';
  try {
    await fn();
    await refresh();
  } catch (e) {
    say(e.message, true);
  } finally {
    b.disabled = false;
    b.textContent = label;
  }
}

$('fLogin').addEventListener('submit', (e) => {
  e.preventDefault();
  busy(e.target, async () => {
    const code = $('code').hidden ? undefined : $('code').value;
    const r = await send({
      type: 'login',
      email: $('email').value,
      password: $('pass').hidden ? undefined : $('pass').value,
      code,
    });
    if (r?.needCode) {
      // contul are verificare în doi pași: cerem codul (parola rămâne)
      $('code').hidden = false;
      $('code').required = true;
      $('code').focus();
      throw new Error('Scrie codul de 6 cifre din aplicația de autentificare.');
    }
    $('pass').value = '';
    $('code').value = '';
    $('code').hidden = true;
  });
});

$('fUnlock').addEventListener('submit', (e) => {
  e.preventDefault();
  busy(e.target, async () => {
    await send({ type: 'unlock', password: $('upass').value });
    $('upass').value = '';
  });
});

$('cancelCode').addEventListener('click', async () => {
  await send({ type: 'cancelLogin' });
  $('code').value = '';
  $('code').hidden = true;
  $('code').required = false;
  refresh();
});

$('lockBtn').addEventListener('click', async () => {
  await send({ type: 'lock' });
  refresh();
});

for (const id of ['logoutBtn', 'logoutBtn2']) {
  $(id).addEventListener('click', async () => {
    await send({ type: 'logout' });
    refresh();
  });
}

// tema: ținută minte în extensie, aplicată imediat aici și pe pagini
function setTheme(t) {
  if (t === 'light' || t === 'dark') document.documentElement.dataset.theme = t;
  else delete document.documentElement.dataset.theme;
  $('theme').value = t || 'auto';
}
chrome.storage.local.get('theme').then((r) => setTheme(r.theme)).catch(() => {});
$('theme').addEventListener('change', (e) => {
  setTheme(e.target.value);
  chrome.storage.local.set({ theme: e.target.value }).catch(() => {});
});

$('autoSave').addEventListener('change', (e) =>
  send({ type: 'setAutoSave', value: e.target.checked }),
);

$('lockMinutes').addEventListener('change', (e) =>
  send({ type: 'setLockMinutes', value: Number(e.target.value) }),
);

$('q').addEventListener('input', render);

newPassword();
refresh().catch((e) => say(e.message, true));
