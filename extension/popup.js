// Fereastra extensiei. Nu păstrează parole: le cere de la fundal doar
// când le copiezi sau completezi.

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

function render() {
  const q = $('q').value.trim().toLowerCase();
  const list = $('list');
  const shown = all.filter(
    (i) => !q || `${i.title} ${i.username} ${i.url}`.toLowerCase().includes(q),
  );
  if (!shown.length) {
    list.innerHTML = `<div class="empty">${all.length ? 'Niciun rezultat' : 'Nicio parolă salvată încă.'}</div>`;
    return;
  }
  list.replaceChildren(
    ...shown.slice(0, 200).map((i) => {
      const row = document.createElement('div');
      row.className = `it${i.match ? ' match' : ''}`;
      const txt = document.createElement('div');
      txt.className = 'txt';
      const t = document.createElement('div');
      t.className = 't';
      if (i.health) {
        const dot = document.createElement('span');
        dot.className = `dot ${i.health}`;
        dot.title = HEALTH_TIP[i.health];
        t.append(dot);
      }
      t.append(document.createTextNode(i.title));
      const s = document.createElement('div');
      s.className = 's';
      s.textContent = i.username || i.url;
      txt.append(t, s);
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
            s.textContent = i.username || i.url;
            s.classList.remove('pw');
          }, 10000);
        });
      }
      if (i.hasTotp) {
        btn('🔢', 'Copiază codul 2FA', () => copy(i.id, 'totp'));
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
    }),
  );
}

/// Editare pe loc: nume, utilizator, parolă, site.
async function editRow(row, i) {
  const d = await send({ type: 'getItem', id: i.id });
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
    });
    if (r?.error) return say(r.error, true);
    say(
      f.get('password') !== d.password
        ? 'Salvat. Parola veche a trecut în istoricul contului.'
        : 'Salvat.',
    );
    await load(true);
  });
  row.replaceWith(form);
  form.querySelector('input').focus();
}

function confirmDelete(row, i) {
  const box = document.createElement('div');
  box.className = 'pend';
  const text = document.createElement('div');
  text.textContent = `Ștergi contul ${i.title}${i.username ? ` (${i.username})` : ''}? Dispare și din aplicație.`;
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
  // verificarea scurgerilor rulează în fundal: culorile se actualizează
  if (!fresh && !load.again) {
    load.again = true;
    setTimeout(async () => {
      all = (await send({ type: 'list', url: await activeUrl() })) ?? all;
      render();
    }, 5000);
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
  $('lockMinutes').value = String(st.lockMinutes ?? 0);
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

$('autoSave').addEventListener('change', (e) =>
  send({ type: 'setAutoSave', value: e.target.checked }),
);

$('lockMinutes').addEventListener('change', (e) =>
  send({ type: 'setLockMinutes', value: Number(e.target.value) }),
);

$('q').addEventListener('input', render);

newPassword();
refresh().catch((e) => say(e.message, true));
