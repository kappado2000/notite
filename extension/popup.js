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
      t.textContent = i.title;
      const s = document.createElement('div');
      s.className = 's';
      s.textContent = i.username || i.url;
      txt.append(t, s);
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
        btn('🔑', 'Copiază parola (se șterge după 30 s)', () => copy(i.id, 'password'));
      }
      if (i.hasTotp) {
        btn('🔢', 'Copiază codul 2FA', () => copy(i.id, 'totp'));
      }
      return row;
    }),
  );
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
  } catch (e) {
    say(e.message, true);
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
}

// ------------------------------------------------------- generator

function generate(len, symbols) {
  const sets = ['ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789'];
  if (symbols) sets.push('!@#$%&*-_=+?');
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
  await navigator.clipboard.writeText($('genOut').textContent);
  say('Parola generată a fost copiată.');
});

// ---------------------------------------------------------- acțiuni

async function refresh() {
  const st = await send({ type: 'status' });
  $('autoSave').checked = st.autoSave;
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

$('q').addEventListener('input', render);

newPassword();
refresh().catch((e) => say(e.message, true));
