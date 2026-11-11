// Pe fiecare pagină: recunoaște formularele de logare / înregistrare,
// propune contul salvat, generează parole și trimite spre salvare
// parola folosită. Nu păstrează nimic: parolele vin de la extensie doar
// la cerere, pentru site-ul curent.
(() => {
  if (window.top !== window || window.__notiteExt) return;
  window.__notiteExt = true;

  const send = (msg) =>
    new Promise((resolve) => {
      try {
        chrome.runtime.sendMessage(msg, (r) => {
          void chrome.runtime.lastError;
          resolve(r?.ok ? r.data : null);
        });
      } catch {
        resolve(null);
      }
    });

  // ------------------------------------------------------ câmpuri

  // „vizibil” = un om îl poate vedea și folosi. Google (și alții) pun pe
  // pagina cu emailul și un câmp de parolă ascuns (aria-hidden, în afara
  // ecranului, transparent) — acela nu contează.
  const visible = (el) => {
    if (!el || el.disabled || el.readOnly) return false;
    if (el.closest('[aria-hidden="true"]') || el.tabIndex < 0) return false;
    const r = el.getBoundingClientRect();
    const st = getComputedStyle(el);
    if (r.width <= 4 || r.height <= 4) return false;
    if (st.visibility === 'hidden' || st.display === 'none') return false;
    if (Number(st.opacity) === 0) return false;
    if (r.right < 0 || r.bottom < 0 || r.left > innerWidth + 50) return false;
    return true;
  };

  /// Textul care descrie un câmp: name, id, autocomplete, placeholder,
  /// aria-label și eticheta (<label>) lui.
  function hints(el) {
    const labels = [...(el.labels ?? [])].map((l) => l.textContent).join(' ');
    return `${el.name} ${el.id} ${el.autocomplete} ${el.placeholder} ${el.getAttribute('aria-label') || ''} ${labels}`.toLowerCase();
  }

  /// Câmp de parolă — și când e afișat în clar (butonul „Arată”/„Ascunde” îl
  /// face type=text), recunoscut după nume / etichetă.
  function isPasswordField(el) {
    if (!(el instanceof HTMLInputElement)) return false;
    if (el.type === 'password') return true;
    if (!['text', ''].includes(el.getAttribute('type') ?? '')) return false;
    return /pass|parol|pwd|passwd|mot de passe|kennwort/.test(hints(el));
  }

  /// Parola NOUĂ (sau confirmarea ei) dintr-un formular de schimbare.
  const isNewPassword = (el) =>
    el.autocomplete === 'new-password' ||
    /\bnew|nou[aă]?\b|noua|confirm|repet|again|retype|din nou|verify/.test(hints(el));

  const passwordFields = (root = document) =>
    [...root.querySelectorAll('input')].filter(
      (el) => isPasswordField(el) && visible(el),
    );

  const USER_SEL =
    'input[type="email"],input[type="text"],input[type="tel"],input:not([type])';

  /// Câmpul de utilizator dinaintea parolei (în același formular).
  function userFieldFor(pw) {
    const scope = pw.form ?? pw.closest('form,div,section,main') ?? document;
    const all = [...scope.querySelectorAll(`${USER_SEL},input[type="password"]`)];
    const idx = all.indexOf(pw);
    for (let i = idx - 1; i >= 0; i--) {
      const el = all[i];
      if (!isPasswordField(el) && visible(el)) return el;
    }
    const ac = scope.querySelector(
      'input[autocomplete="username"],input[autocomplete="email"],input[name*="user" i],input[name*="mail" i],input[id*="user" i],input[id*="mail" i]',
    );
    return ac && visible(ac) ? ac : null;
  }

  /// Câmpul pentru codul 2FA (6–8 cifre)?
  function isOtpField(el) {
    if (!(el instanceof HTMLInputElement) || isPasswordField(el)) return false;
    if (el.autocomplete === 'one-time-code') return true;
    const hint = `${el.name} ${el.id} ${el.placeholder} ${el.getAttribute('aria-label') || ''}`.toLowerCase();
    const max = Number(el.maxLength);
    return (
      /otp|2fa|mfa|totp|one.?time|verification|verificare|authenticat|security.?code|cod(ul)? de|token|pin/.test(hint) &&
      (!max || max < 0 || (max >= 6 && max <= 10))
    );
  }

  async function showOtpMenu(field) {
    const r = await send({ type: 'pageTotp' });
    if (!r || r.locked || !r.items.length) return;
    menu.innerHTML =
      '<div class="head">🔑 Notițe · cod 2FA</div>' +
      r.items
        .map(
          (i) =>
            `<div class="item" tabindex="0" data-otp="${esc(i.code)}"><span class="t">${esc(i.code.replace(/(\d{3})(?=\d)/g, '$1 '))}</span><span class="s">${esc(i.username || i.title)} · încă ${i.remaining} s</span></div>`,
        )
        .join('');
    const rect = field.getBoundingClientRect();
    menu.style.left = `${Math.max(8, Math.min(rect.left, innerWidth - 350))}px`;
    menu.style.top = `${Math.min(rect.bottom + 6, innerHeight - 60)}px`;
    attach();
    menu.hidden = false;
    menuFor = field;
  }

  /// Înregistrare / schimbare de parolă (nu logare)?
  function isSignup(pw) {
    if (pw.autocomplete === 'new-password') return true;
    const scope = pw.form ?? document;
    if (passwordFields(scope).length >= 2) return true;
    const text = (scope.innerText || '').slice(0, 3000).toLowerCase();
    return /înregistr|inregistr|creează cont|creeaza cont|cont nou|sign ?up|register|create (an )?account|new password|parolă nouă|parola noua/.test(
      text,
    );
  }

  function setValue(el, value) {
    if (!el) return;
    const proto = Object.getPrototypeOf(el);
    const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
    el.focus();
    if (setter) setter.call(el, value);
    else el.value = value;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }

  /// [target] = câmpul în care ai dat clic (dacă e unul de utilizator, emailul
  /// merge sigur acolo).
  function fill(username, password, target = null) {
    const all = passwordFields();
    const current = all.filter((p) => !isNewPassword(p));
    const pws = current.length ? current : all.slice(0, 1);
    const pw =
      pws.find((p) => p === target || p === document.activeElement) ?? pws[0];
    const userTarget =
      target && !isPasswordField(target) && visible(target) ? target : null;
    if (pw) {
      const u = userTarget ?? userFieldFor(pw);
      if (u && username) setValue(u, username);
      setValue(pw, password);
    } else if (userTarget) {
      if (username) setValue(userTarget, username);
    } else {
      // pasul cu utilizatorul (ex. Google, Microsoft)
      const u = [...document.querySelectorAll(USER_SEL)].find(visible);
      if (u && username) setValue(u, username);
    }
  }

  // ------------------------------------------------- generator de parole

  function generate(len = 18) {
    const sets = [
      'ABCDEFGHJKLMNPQRSTUVWXYZ',
      'abcdefghijkmnopqrstuvwxyz',
      '23456789',
      '!@#$%&*-_=+?',
    ];
    const all = sets.join('');
    const rnd = (n) => {
      const a = new Uint32Array(1);
      const max = Math.floor(0xffffffff / n) * n;
      do crypto.getRandomValues(a);
      while (a[0] >= max);
      return a[0] % n;
    };
    const chars = sets.map((s) => s[rnd(s.length)]);
    while (chars.length < len) chars.push(all[rnd(all.length)]);
    for (let i = chars.length - 1; i > 0; i--) {
      const j = rnd(i + 1);
      [chars[i], chars[j]] = [chars[j], chars[i]];
    }
    return chars.join('');
  }

  // -------------------------------------------------- interfața (Shadow DOM)

  const host = document.createElement('notite-ext');
  host.style.cssText = 'all:initial;position:fixed;z-index:2147483647;top:0;left:0;';
  const shadow = host.attachShadow({ mode: 'closed' });
  shadow.innerHTML = `
    <style>
      :host { all: initial; }
      * { box-sizing: border-box; font-family: system-ui, -apple-system, "Segoe UI", sans-serif; }
      .menu { position: fixed; min-width: 260px; max-width: 340px; background: #fff; color: #22261F;
        border: 1px solid #b9c7bd; border-radius: 12px; box-shadow: 0 8px 28px rgba(0,0,0,.18);
        padding: 6px; font-size: 14px; }
      .head { display:flex; align-items:center; gap:6px; padding: 6px 8px 8px; font-size: 12px;
        font-weight: 700; color: #3F8F6B; letter-spacing: .3px; }
      .item { display:flex; flex-direction:column; padding: 8px 10px; border-radius: 8px; cursor: pointer; }
      .item:hover, .item:focus { background: #E7F2EC; outline: none; }
      .t { font-weight: 600; } .s { font-size: 12px; color: #5E6559; }
      .note { padding: 8px 10px; font-size: 13px; color: #5E6559; }
      .toast { position: fixed; top: 16px; right: 16px; width: 340px; background: #fff; color: #22261F;
        border: 1px solid #3F8F6B; border-radius: 14px; box-shadow: 0 10px 30px rgba(0,0,0,.2);
        padding: 12px 14px; font-size: 14px; }
      .toast b { color: #2b6e50; }
      .row { display:flex; gap:8px; justify-content:flex-end; margin-top: 10px; }
      button { border: 0; border-radius: 9px; padding: 7px 12px; font-size: 13px; font-weight: 600; cursor: pointer; }
      .pri { background: #3F8F6B; color: #fff; } .sec { background: #EEF1EC; color: #22261F; }
      @media (prefers-color-scheme: dark) {
        .menu, .toast { background: #1E221C; color: #E6E8E1; border-color: #4b5a50; }
        .item:hover, .item:focus { background: #2b3a31; } .s, .note { color: #B4BBAE; }
        .sec { background: #30362D; color: #E6E8E1; } .toast b { color: #8FCFAE; }
      }
    </style>
    <div class="menu" hidden></div>
    <div class="toast" hidden></div>`;
  const menu = shadow.querySelector('.menu');
  const toastEl = shadow.querySelector('.toast');
  const attach = () => {
    if (!host.isConnected) document.documentElement.appendChild(host);
  };

  const esc = (s) =>
    String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

  let menuFor = null;

  function hideMenu() {
    menu.hidden = true;
    menuFor = null;
  }

  async function showMenu(field) {
    const pw = isPasswordField(field) ? field : passwordFields()[0];
    const signup = pw ? isSignup(pw) : false;
    const r = await send({ type: 'pageLogins' });
    if (!r) return;
    const parts = [];
    if (r.locked) {
      if (r.loggedIn === false) return; // extensia nu e conectată: nu deranjăm
      parts.push(`<div class="note">🔒 Notițe e blocat. Deschide iconița extensiei ca să-l deblochezi.</div>`);
    } else {
      if (!r.secure && r.items.length) {
        parts.push(`<div class="note">⚠️ Pagina nu e securizată (fără HTTPS); nu completez parole aici.</div>`);
      } else {
        for (const i of r.items) {
          parts.push(
            `<div class="item" tabindex="0" data-id="${esc(i.id)}"><span class="t">${esc(i.username || i.title)}</span><span class="s">${esc(i.title)}</span></div>`,
          );
        }
      }
      if (signup && pw) {
        parts.push(
          `<div class="item" tabindex="0" data-gen="1"><span class="t">🎲 Generează o parolă puternică</span><span class="s">O completez și o salvez în Notițe</span></div>`,
        );
      }
    }
    if (!parts.length) return hideMenu();
    menu.innerHTML = `<div class="head">🔑 Notițe</div>${parts.join('')}`;
    const rect = field.getBoundingClientRect();
    menu.style.left = `${Math.max(8, Math.min(rect.left, innerWidth - 350))}px`;
    menu.style.top = `${Math.min(rect.bottom + 6, innerHeight - 60)}px`;
    attach();
    menu.hidden = false;
    menuFor = field;
  }

  menu.addEventListener('mousedown', (e) => e.preventDefault());
  menu.addEventListener('click', async (e) => {
    const it = e.target.closest('.item');
    if (!it) return;
    if (it.dataset.otp) {
      if (menuFor) setValue(menuFor, it.dataset.otp);
      hideMenu();
      return;
    }
    if (it.dataset.gen) {
      const pass = generate();
      const pws = passwordFields(menuFor?.form ?? document);
      // schimbare de parolă: doar câmpurile „nouă” / „confirmă”, nu cea actuală
      const fresh = pws.filter(isNewPassword);
      const targets = fresh.length
        ? fresh
        : pws.filter((p) => !p.value || pws.length === 1);
      for (const p of targets) setValue(p, pass);
      hideMenu();
      return;
    }
    const cred = await send({ type: 'fill', id: it.dataset.id });
    if (cred) fill(cred.username, cred.password, menuFor);
    hideMenu();
  });

  document.addEventListener(
    'focusin',
    (e) => {
      const el = e.target;
      if (!(el instanceof HTMLInputElement)) return;
      if (isOtpField(el)) {
        showOtpMenu(el);
        return;
      }
      const isPw = isPasswordField(el);
      const isUser = !isPw && el.matches(USER_SEL) && (passwordFields().length > 0 || /user|mail|login|email/i.test(`${el.name} ${el.id} ${el.autocomplete}`));
      if (isPw || isUser) showMenu(el);
    },
    true,
  );
  document.addEventListener('click', (e) => {
    if (menuFor && e.target !== menuFor && !host.contains(e.target)) hideMenu();
  }, true);
  addEventListener('scroll', hideMenu, true);

  // ----------------------------------------------- prinderea parolei

  function capture(scope) {
    const pws = passwordFields(scope ?? document).filter((p) => p.value);
    if (!pws.length) {
      // pas intermediar: doar utilizatorul (ex. Google)
      const u = [...(scope ?? document).querySelectorAll(USER_SEL)].find(
        (el) => visible(el) && el.value && /mail|user|login|identifier|phone/i.test(`${el.name} ${el.id} ${el.autocomplete} ${el.type}`),
      );
      if (u) send({ type: 'usernameStep', username: u.value.trim() });
      return;
    }
    // la înregistrare / schimbare: parola nouă (sau, altfel, ultima)
    const pw = pws.filter(isNewPassword).pop() ?? pws[pws.length - 1];
    const user = userFieldFor(pws[0]);
    send({
      type: 'captured',
      username: user?.value?.trim() ?? '',
      password: pw.value,
    }).then((info) => {
      showToast(info);
      // afișat deja aici: nu-l mai repetăm pe pagina următoare dacă nu
      // s-a navigat
      if (info) setTimeout(() => send({ type: 'takeToast' }), 4000);
    });
  }

  document.addEventListener('submit', (e) => capture(e.target), true);
  document.addEventListener(
    'click',
    (e) => {
      const b = e.target.closest?.('button,input[type="submit"],input[type="button"],[role="button"],a');
      if (!b) return;
      const label = `${b.innerText || b.value || ''} ${b.id} ${b.name || ''}`.toLowerCase();
      const isSubmit = b.type === 'submit' || /log ?in|sign ?in|sign ?up|conect|autentific|intr[ăa]|înregistr|inregistr|creeaz|register|continu|next|următor|urmator|salveaz|save|submit|trimite/.test(label);
      if (isSubmit) capture(b.closest('form') ?? document);
    },
    true,
  );
  document.addEventListener(
    'keydown',
    (e) => {
      if (e.key === 'Enter' && e.target instanceof HTMLInputElement) {
        capture(e.target.form ?? document);
      }
    },
    true,
  );

  // ----------------------------------------------------------- mesaje

  let toastTimer = 0;
  function showToast(info) {
    if (!info || !info.result || info.result === 'same' || info.result === 'loggedOut') return;
    const who = info.username ? ` (${esc(info.username)})` : '';
    let html;
    if (info.result === 'new') {
      html = `🔑 Parola pentru <b>${esc(info.site)}</b>${who} a fost salvată în Notițe.
        <div class="row"><button class="sec" data-a="undo">Anulează</button><button class="pri" data-a="ok">OK</button></div>`;
    } else if (info.result === 'updated') {
      html = `🔑 Parola nouă pentru <b>${esc(info.site)}</b>${who} a fost salvată în Notițe (cea veche rămâne în istoric).
        <div class="row"><button class="sec" data-a="undo">Anulează</button><button class="pri" data-a="ok">OK</button></div>`;
    } else if (info.result === 'ask') {
      html = `Salvezi parola pentru <b>${esc(info.site)}</b>${who} în Notițe?
        <div class="row"><button class="sec" data-a="ok">Nu acum</button><button class="pri" data-a="save">Salvează</button></div>`;
    } else if (info.result === 'askUpdate') {
      html = `Ai folosit altă parolă pentru <b>${esc(info.site)}</b>${who}. O actualizez în Notițe? <span style="opacity:.75">(Dacă logarea n-a reușit, alege „Nu”.)</span>
        <div class="row"><button class="sec" data-a="ok">Nu</button><button class="pri" data-a="save">Actualizează</button></div>`;
    } else if (info.result === 'locked') {
      html = `🔒 Notițe e blocat. Parola pentru <b>${esc(info.site)}</b>${who} va fi salvată când îl deblochezi din iconița extensiei.
        <div class="row"><button class="pri" data-a="ok">OK</button></div>`;
    } else return;
    toastEl.innerHTML = html;
    attach();
    toastEl.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => (toastEl.hidden = true), 12000);
  }

  toastEl.addEventListener('click', async (e) => {
    const a = e.target.closest('button')?.dataset.a;
    if (!a) return;
    if (a === 'undo') {
      await send({ type: 'undo' });
      toastEl.innerHTML = 'Am anulat salvarea.';
      setTimeout(() => (toastEl.hidden = true), 2500);
      return;
    }
    if (a === 'save') {
      const r = await send({ type: 'savePendingFromPage' });
      if (r) return showToast({ ...r, site: location.hostname.replace(/^www\./, '') });
    }
    toastEl.hidden = true;
  });

  chrome.runtime.onMessage.addListener((msg) => {
    if (msg?.type === 'doFill') fill(msg.username, msg.password);
  });

  // mesajul rămas de la pagina anterioară (logarea a navigat)
  send({ type: 'takeToast' }).then(showToast);
})();
