// Pe fiecare pagină: recunoaște formularele de logare / înregistrare,
// propune contul salvat, generează parole și trimite spre salvare
// parola folosită. Nu păstrează nimic: parolele vin de la extensie doar
// la cerere, pentru site-ul curent.
(() => {
  if (window.__notiteExt) return;
  // Cadre încastrate: doar cele de pe același site cu pagina (ex.
  // formularul Apple de pe idmsa.apple.com); reclamele și paginile străine
  // sunt ignorate (extensia verifică oricum din nou).
  const isTop = window.top === window;
  if (!isTop) {
    // același cont pe domenii înrudite (formularul Apple din icloud.com)
    const ALIAS = { 'icloud.com': 'apple.com', 'me.com': 'apple.com', 'appleid.com': 'apple.com' };
    const site = (h) => {
      const b = h.split('.').slice(-2).join('.');
      return ALIAS[b] ?? b;
    };
    const anc = location.ancestorOrigins;
    const topOrigin = anc && anc.length ? anc[anc.length - 1] : '';
    let topHost = '';
    try {
      topHost = new URL(topOrigin).hostname;
    } catch {
      return;
    }
    if (location.protocol !== 'https:' || site(topHost) !== site(location.hostname)) return;
  }
  window.__notiteExt = true;

  /// Iconița 2FA din aplicație (lacăt-scut cu un om), aceeași peste tot.
  const AUTH_SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="16" height="16" class="auth"> <defs> <linearGradient id="authg" x1="0" y1="0" x2="0" y2="1"> <stop offset="0" stop-color="#2C644B"/> <stop offset="0.5" stop-color="#3F8F6B"/> <stop offset="1" stop-color="#62B791"/> </linearGradient> <clipPath id="authc"> <path d="M50 34 C70 34 86 36 88 40 C92 62 80 86 50 98 C20 86 8 62 12 40 C14 36 30 34 50 34 Z"/> </clipPath> </defs> <path d="M28 42 V30 A22 20 0 0 1 72 30 V42" fill="none" stroke="#2C644B" stroke-width="11"/> <path d="M50 34 C70 34 86 36 88 40 C92 62 80 86 50 98 C20 86 8 62 12 40 C14 36 30 34 50 34 Z" fill="url(#authg)"/> <g clip-path="url(#authc)" fill="#9BD1B6"> <circle cx="50" cy="55" r="11"/> <ellipse cx="50" cy="92" rx="26" ry="19"/> </g> </svg>';

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

  /// Schimbare de parolă: un câmp cu parola actuală + unul cu cea nouă.
  const isChangeForm = (pws) =>
    pws.some(isNewPassword) && pws.some((p) => !isNewPassword(p));

  /// Un câmp care e sigur utilizatorul / emailul (după nume sau tip).
  function clearUserField(scope) {
    return [...(scope ?? document).querySelectorAll(USER_SEL)].find(
      (el) =>
        visible(el) &&
        el.value &&
        !isPasswordField(el) &&
        (el.type === 'email' || /user|mail|login|identifier/.test(hints(el))),
    ) ?? null;
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
    if (sentCodeField(field)) return;
    const r = await send({ type: 'pageTotp' });
    if (!r || r.locked || !r.items.length) return;
    menu.innerHTML =
      `<div class="head">${AUTH_SVG} Notițe · cod 2FA</div>` +
      r.items
        .map(
          (i) =>
            `<div class="item" tabindex="0" data-otp="${esc(i.code)}"><span class="t">${esc(i.code.replace(/(\d{3})(?=\d)/g, '$1 '))}</span><span class="s">${esc(i.username || i.title)} · încă ${i.remaining} s</span></div>`,
        )
        .join('');
    place(field);
    attach();
    menu.hidden = false;
    menuFor = field;
  }

  /// Înregistrare / schimbare de parolă (nu logare)?
  function isSignup(pw) {
    if (pw.autocomplete === 'new-password' || isNewPassword(pw)) return true;
    const scope = pw.form ?? document;
    if (passwordFields(scope).length >= 2) return true;
    const re =
      /înregistr|inregistr|creează cont|creeaza cont|cont nou|sign ?up|register|create (an )?account|new password|parol[ăa] nou[ăa]|nou[ăa] parol[ăa]|crea[țt]i o parol|creea?z[ăa] (o )?parol|alege[țt]?i? o parol|create (a )?password|choose (a )?password|change (your )?password/;
    // textul din jurul căsuței: fereastra / secțiunea în care stă (pe unele
    // site-uri, ex. Yahoo, căsuța nu e într-un formular)
    let near = '';
    for (let el = pw.parentElement, up = 0; el && up < 8; el = el.parentElement, up++) {
      near = (el.innerText || '').slice(0, 1500);
      if (near.length > 200 || el.matches('form,[role="dialog"],dialog')) break;
    }
    const text = `${near} ${(scope.innerText || '').slice(0, 3000)}`.toLowerCase();
    return re.test(text);
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
      '!*-_.',
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
      .menu { position: fixed; min-width: 320px; max-width: 470px; background: #fff; color: #22261F;
        border: 1px solid #b9c7bd; border-radius: 12px; box-shadow: 0 8px 28px rgba(0,0,0,.18);
        padding: 6px; font-size: 14px; overflow-y: auto; overscroll-behavior: contain; }
      .head { position: sticky; top: -6px; background: inherit; z-index: 1;
        display:flex; align-items:center; gap:6px; padding: 6px 8px 8px; font-size: 12px;
        font-weight: 700; color: #3F8F6B; letter-spacing: .3px; }
      .item { display:flex; flex-direction:column; padding: 8px 10px; border-radius: 8px; cursor: pointer; }
      .item:hover, .item:focus { background: #E7F2EC; outline: none; }
      .t { font-weight: 600; }
      .dot { display:inline-block; width:9px; height:9px; border-radius:50%; margin-right:7px; vertical-align:1px; }
      .dot.red { background:#D93025; } .dot.yellow { background:#E8A200; } .dot.green { background:#2E9E5B; } .dot.ignored { background:#9AA0A6; } .s { font-size: 12px; color: #5E6559; }
      .note { padding: 8px 10px; font-size: 13px; color: #5E6559; }
      .item.acc { flex-direction: row; align-items: center; gap: 10px; }
      .acc .txt { flex: 1; min-width: 0; display: flex; flex-direction: column; }
      .acc .t, .acc .s { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
      .acc .t { font-weight: 700; font-size: 15px; }
      .acc .s { font-weight: 400; font-size: 12px; }
      .acc .dot { margin: 0 2px 0 6px; flex: none; }
      .acc .tfa { flex: none; margin-left: 6px; display: inline-flex; }
      svg.auth { vertical-align: -3px; flex: none; }
      .acc .tfa svg.auth { width: 18px; height: 18px; }
      .acc .t.n { font-weight: 500; }
      /* „Caută alt cont”: ca la Google — sub o linie, scris mic și subțire,
         fix jos în meniu (se vede întreg și când lista se derulează) */
      .item.foot { position: sticky; bottom: -6px; background: inherit; border-radius: 0 0 8px 8px;
        border-top: 1px solid #e3e8e1; margin: 4px -6px -6px; padding: 10px 16px; }
      .item.foot .t.n { font-weight: 400; font-size: 13px; }
      .item.foot .fav.srch { width: 20px; height: 20px; font-size: 13px; }
      .item.foot:hover, .item.foot:focus { background: #E7F2EC; }
      :host(.dark) .item.foot { border-top-color: #3a4237; }
      :host(.dark) .item.foot:hover, :host(.dark) .item.foot:focus { background: #2b3a31; }
      .fav.srch { background: transparent; font-size: 15px; }
      :host(.dark) .fav.srch { background: transparent; }
      .fav { flex: none; width: 24px; height: 24px; border-radius: 50%; display: inline-flex; align-items: center;
        justify-content: center; overflow: hidden; background: #E7F2EC; color: #3F8F6B; font-weight: 700; font-size: 12px; }
      .fav img { width: 20px; height: 20px; }
      .q { width: 100%; margin: 2px 0 6px; padding: 8px 10px; border: 1px solid #b9c7bd; border-radius: 9px;
        font-size: 14px; background: transparent; color: inherit; outline: none; }
      .q:focus { border-color: #3F8F6B; }
      .sep { border-top: 1px solid #e3e8e1; margin: 4px 2px; }
      .toast { position: fixed; top: 16px; right: 16px; width: 340px; background: #fff; color: #22261F;
        border: 1px solid #3F8F6B; border-radius: 14px; box-shadow: 0 10px 30px rgba(0,0,0,.2);
        padding: 12px 14px; font-size: 14px; }
      .toast b { color: #2b6e50; }
      .row { display:flex; gap:8px; justify-content:flex-end; margin-top: 10px; }
      button { border: 0; border-radius: 9px; padding: 7px 12px; font-size: 13px; font-weight: 600; cursor: pointer; }
      .pri { background: #3F8F6B; color: #fff; } .sec { background: #EEF1EC; color: #22261F; }
      :host(.dark) .menu, :host(.dark) .toast { background: #1E221C; color: #E6E8E1; border-color: #4b5a50; }
      :host(.dark) .item:hover, :host(.dark) .item:focus { background: #2b3a31; }
      :host(.dark) .s, :host(.dark) .note { color: #B4BBAE; }
      :host(.dark) .q { border-color: #4b5a50; } :host(.dark) .sep { border-color: #3a4237; }
      :host(.dark) .sec { background: #30362D; color: #E6E8E1; } :host(.dark) .toast b { color: #8FCFAE; }
      :host(.dark) .fav { background: #2b3a31; color: #8FCFAE; }
    </style>
    <div class="menu" hidden></div>
    <div class="toast" hidden></div>`;
  const menu = shadow.querySelector('.menu');
  const toastEl = shadow.querySelector('.toast');

  // tema aleasă în Setările extensiei: automată (ca sistemul), luminoasă,
  // închisă
  const darkMq = matchMedia('(prefers-color-scheme: dark)');
  let theme = 'auto';
  const applyTheme = () =>
    host.classList.toggle('dark', theme === 'dark' || (theme === 'auto' && darkMq.matches));
  applyTheme();
  darkMq.addEventListener?.('change', applyTheme);
  try {
    chrome.storage.local.get('theme', (r) => {
      void chrome.runtime.lastError;
      theme = r?.theme || 'auto';
      applyTheme();
    });
    chrome.storage.onChanged.addListener((ch, area) => {
      if (area === 'local' && ch.theme) {
        theme = ch.theme.newValue || 'auto';
        applyTheme();
      }
    });
  } catch {}
  const attach = () => {
    if (!host.isConnected) document.documentElement.appendChild(host);
  };

  const esc = (s) =>
    String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

  let menuFor = null;

  /// Sub câmp (sau deasupra, dacă jos nu e loc), cât încape pe ecran;
  /// lista lungă se derulează în interiorul panoului.
  /// Meniul își ia înălțimea după conținut (toate conturile site-ului, la
  /// vedere). Întâi în fața căsuței (stânga) sau în dreapta ei, la aceeași
  /// înălțime; fără loc în lateral: sub căsuță, deasupra sau pe toată
  /// înălțimea ecranului. Derulare doar dacă nici așa nu încape.
  function place(field) {
    // în pagină ÎNAINTE de măsurare (altfel înălțimea iese 0 și meniul
    // rămâne mic, cu derulare); unele site-uri îl scot din pagină
    attach();
    const rect = field.getBoundingClientRect();
    const wasHidden = menu.hidden;
    // măsurăm înălțimea naturală, nevăzut
    menu.style.visibility = 'hidden';
    menu.hidden = false;
    menu.style.maxHeight = 'none';
    menu.style.top = '0px';
    menu.style.bottom = '';
    const need = menu.scrollHeight + 2;
    const width = menu.offsetWidth;
    menu.hidden = wasHidden;
    menu.style.visibility = '';
    const gap = 6;
    // în fața căsuței (stânga), altfel în dreapta: meniul de parole al
    // browserului (Chrome) apare sub / deasupra căsuței și l-ar acoperi
    const side =
      rect.left - gap - 8 >= width
        ? rect.left - gap - width
        : innerWidth - rect.right - gap - 8 >= width
          ? rect.right + gap
          : null;
    if (side != null) {
      const h = Math.min(need, innerHeight - 16);
      menu.style.left = `${side}px`;
      menu.style.bottom = '';
      menu.style.top = `${Math.max(8, Math.min(rect.top, innerHeight - 8 - h))}px`;
      menu.style.maxHeight = `${innerHeight - 16}px`;
      return;
    }
    menu.style.left = `${Math.max(8, Math.min(rect.left, innerWidth - width - 8))}px`;
    const below = innerHeight - rect.bottom - gap - 8;
    const above = rect.top - gap - 8;
    if (need <= below) {
      menu.style.top = `${rect.bottom + gap}px`;
      menu.style.maxHeight = `${below}px`;
    } else if (need <= above) {
      menu.style.top = '';
      menu.style.bottom = `${innerHeight - rect.top + gap}px`;
      menu.style.maxHeight = `${above}px`;
    } else {
      // pe tot ecranul: centrat pe verticală, cât e nevoie
      const h = Math.min(need, innerHeight - 16);
      menu.style.top = `${Math.max(8, (innerHeight - h) / 2)}px`;
      menu.style.maxHeight = `${innerHeight - 16}px`;
    }
  }

  function hideMenu() {
    menu.hidden = true;
    menuFor = null;
  }

  // panoul nu rămâne „agățat”: dispare când câmpul pierde focusul, nu mai e
  // vizibil (pagina s-a schimbat după logare) sau la Esc
  setInterval(() => {
    if (menu.hidden || !menuFor) return;
    if (!menuFor.isConnected || !visible(menuFor)) hideMenu();
  }, 400);
  document.addEventListener(
    'focusout',
    (e) => {
      const f = e.target;
      setTimeout(() => {
        const a = document.activeElement;
        if (menuFor === f && a !== f && a !== host && !host.contains(a)) hideMenu();
      }, 150);
    },
    true,
  );
  document.addEventListener(
    'keydown',
    (e) => {
      if (e.key === 'Escape' && !menu.hidden) hideMenu();
    },
    true,
  );

const HEALTH_TIP = {
  red: 'Compromisă: apare în scurgeri de date — schimb-o',
  yellow: 'Slabă sau folosită și la alt cont',
  green: 'În regulă',
  ignored: 'Ignorat în aplicație (nu mai e verificat)',
};

  let lastGenerated = '';

  /// Iconița paginii (cea din fila browserului), pentru meniul de conturi.
  function pageIcon() {
    const link = document.querySelector(
      'link[rel~="icon"][href], link[rel="shortcut icon"][href], link[rel="apple-touch-icon"][href]',
    );
    try {
      return new URL(link?.href || '/favicon.ico', location.href).href;
    } catch {
      return '';
    }
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
      // pagină fără HTTPS (în afara rețelei de acasă): nu completăm și nici
      // nu afișăm nimic — un avertisment care stă pe ecran doar încurcă
      if (!r.secure) return hideMenu();
      {
        // iconița site-ului în față, utilizatorul, numele contului dedesubt,
        // starea parolei la final; telefoanele, apoi adresele de email
        const kind = (u) =>
          /^\+?[\d\s().-]{7,}$/.test((u || '').trim()) ? 0 : (u || '').includes('@') ? 1 : 2;
        const sorted = [...r.items].sort(
          (a, b) =>
            kind(a.username) - kind(b.username) ||
            (a.username || a.title).localeCompare(b.username || b.title, 'ro'),
        );
        const icon = pageIcon();
        for (const i of sorted) {
          parts.push(
            `<div class="item acc" tabindex="0" data-id="${esc(i.id)}"><span class="fav" data-l="${esc((i.title || '?').charAt(0).toUpperCase())}">${icon ? `<img src="${esc(icon)}" alt="">` : esc((i.title || '?').charAt(0).toUpperCase())}</span><span class="txt"><span class="t">${esc(i.title || i.username)}</span>${i.username && i.title ? `<span class="s">${esc(i.username)}</span>` : ''}</span>${i.hasTotp ? `<span class="tfa" title="Are 2FA în Notițe: codul se completează după parolă">${AUTH_SVG}</span>` : ''}${i.health ? `<span class="dot ${esc(i.health)}" title="${esc(HEALTH_TIP[i.health] ?? '')}"></span>` : ''}</div>`,
          );
        }
      }
      parts.push(
        // în listă, ca un rând obișnuit (ca la Google): iconița în locul
        // emblemei site-ului, textul de aceeași mărime
        `<div class="item acc foot" tabindex="0" data-search="1" title="Caută printre toate conturile tale din Notițe"><span class="fav srch">🔍</span><span class="txt"><span class="t n">Caută alt cont</span></span></div>`,
      );
      // o parolă generată e deja în câmpuri: NU mai oferim alta (ar înlocui-o
      // pe cea pe care poate site-ul a acceptat-o deja)
      const already =
        lastGenerated &&
        passwordFields().some((p) => p.value === lastGenerated);
      // pe paginile de parolă nouă: generatorul PRIMUL, deasupra conturilor
      if (signup && pw && already) {
        parts.unshift(
          `<div class="note">✓ Parola generată e deja pusă în câmp și ținută minte în Notițe. Apasă „Salvează” pe site.</div>`,
        );
      } else if (signup && pw) {
        parts.unshift(
          `<div class="item" tabindex="0" data-gen="1"><span class="t">🎲 Generează o parolă puternică</span><span class="s">O completez și o salvez în Notițe</span></div>`,
          '<div class="sep"></div>',
        );
      }
    }
    if (!parts.length) return hideMenu();
    menu.innerHTML = `<div class="head">🔑 Notițe</div>${parts.join('')}`;
    // iconița care nu se încarcă: inițiala contului
    for (const img of menu.querySelectorAll('.fav img')) {
      img.addEventListener('error', () => {
        const box = img.parentElement;
        box.textContent = box.dataset.l || '?';
      });
    }
    place(field);
    attach();
    menu.hidden = false;
    menuFor = field;
  }

  menu.addEventListener('mousedown', (e) => {
    if (!e.target.closest('.q')) e.preventDefault();
  });

  // ---- „Alt cont din Notițe…”: contul e salvat pentru alt site (ex. afm.ro,
  // iar logarea e pe afmb2cprod.b2clogin.com). Îl alegi tu și confirmi.
  let searchTimer = 0;
  function showSearch() {
    const field = menuFor;
    menu.innerHTML = `<div class="head">🔑 Notițe · alt cont</div><input class="q" type="search" placeholder="Caută: nume, site sau e-mail" autocomplete="off" spellcheck="false"><div class="res"></div>`;
    const q = menu.querySelector('.q');
    const res = menu.querySelector('.res');
    const run = async () => {
      const r = await send({ type: 'searchLogins', q: q.value });
      if (!r || menuFor !== field) return;
      if (r.locked) {
        res.innerHTML = `<div class="note">🔒 Notițe e blocat.</div>`;
        return;
      }
      res.innerHTML = r.items.length
        ? r.items
            .map(
              (i) =>
                `<div class="item" tabindex="0" data-other="${esc(i.id)}" data-site="${esc(i.site || i.title)}" data-user="${esc(i.username || i.title)}"><span class="t">${esc(i.username || i.title)}</span><span class="s">${esc(i.title)}${i.site && i.site.toLowerCase() !== i.title.toLowerCase() ? ` · ${esc(i.site)}` : ''}</span></div>`,
            )
            .join('') +
          (r.total > r.items.length
            ? `<div class="note">Încă ${r.total - r.items.length} — scrie mai mult ca să restrângi.</div>`
            : '')
        : `<div class="note">Niciun cont găsit.</div>`;
    };
    q.addEventListener('input', () => {
      clearTimeout(searchTimer);
      searchTimer = setTimeout(run, 150);
    });
    q.addEventListener('keydown', (e) => {
      e.stopPropagation();
      if (e.key === 'Escape') hideMenu();
      if (e.key === 'Enter' && e.isTrusted) {
        e.preventDefault();
        const first = menu.querySelector('[data-other]');
        if (first) showConfirm(first);
      }
    });
    run();
    q.focus();
  }

  function showConfirm(it) {
    const here = location.hostname.replace(/^www\./, '');
    menu.innerHTML = `<div class="head">🔑 Notițe · alt cont</div><div class="note"><b>${esc(it.dataset.user)}</b> e salvat pentru <b>${esc(it.dataset.site || 'alt site')}</b>.<br><br>Verifică adresa din bara browserului: ești pe <b>${esc(here)}</b>. Îl folosești și aici?</div><div class="item" tabindex="0" data-use="${esc(it.dataset.other)}" data-remember="1"><span class="t">✓ Da, și ține minte</span><span class="s">Data viitoare apare direct aici</span></div><div class="item" tabindex="0" data-use="${esc(it.dataset.other)}"><span class="t">Doar acum</span><span class="s">Nu-l leg de acest site</span></div>`;
  }

  menu.addEventListener('click', async (e) => {
    const it = e.target.closest('.item');
    if (!it) return;
    // doar clicuri reale: pagina nu poate apăsa în locul tău
    if (!e.isTrusted) return;
    if (it.dataset.search) return showSearch();
    if (it.dataset.other) return showConfirm(it);
    if (it.dataset.use) {
      const target = menuFor;
      const cred = await send({
        type: 'fillOther',
        id: it.dataset.use,
        remember: !!it.dataset.remember,
      });
      if (cred) {
        fill(cred.username, cred.password, target);
        armAutoOtp();
      }
      hideMenu();
      return;
    }
    if (it.dataset.otp) {
      if (menuFor) setValue(menuFor, it.dataset.otp);
      hideMenu();
      return;
    }
    if (it.dataset.gen) {
      const pws = passwordFields(menuFor?.form ?? document);
      // schimbare de parolă: doar câmpurile „nouă” / „confirmă”, nu cea actuală
      const fresh = pws.filter(isNewPassword);
      const targets = fresh.length
        ? fresh
        : pws.filter((p) => !p.value || pws.length === 1);
      // lungimea maximă cerută de site (altfel site-ul o taie pe tăcute)
      const max = Math.min(
        18,
        ...targets.map((p) => (p.maxLength >= 8 ? p.maxLength : 18)),
      );
      const pass = generate(max);
      lastGenerated = pass;
      for (const p of targets) setValue(p, pass);
      // ținută minte în Notițe imediat, înainte de „Salvează” pe site
      const u = clearUserField(menuFor?.form ?? document);
      send({ type: 'generated', password: pass, username: u?.value?.trim() ?? '' })
        .then((r) => {
          if (r?.result === 'kept') {
            showToast({ result: 'generatedKept', site: location.hostname, count: r.count });
          }
        })
        .catch(() => {});
      hideMenu();
      return;
    }
    const cred = await send({ type: 'fill', id: it.dataset.id });
    if (cred) {
      fill(cred.username, cred.password, menuFor);
      armAutoOtp();
    }
    hideMenu();
  });

  // ------------------------------------------- cod 2FA pus automat
  // După ce ai completat parola din Notițe, pe pagina de cod (același site,
  // aceeași filă, câteva minute) codul se pune singur. Butonul de trimitere
  // îl apeși tu. Extensia decide dacă e voie; aici doar găsim câmpul.

  const autoTried = new WeakSet();
  let autoBusy = false;
  let autoUntil = Date.now() + 3 * 60 * 1000;

  const usable = (el) =>
    el instanceof HTMLInputElement && visible(el) && !el.disabled && !el.readOnly && !el.value;

  /// Căsuțe separate pentru cifre (6 sau 8 câmpuri de câte un caracter).
  function splitOtp() {
    const boxes = [...document.querySelectorAll('input')].filter(
      (el) => el.maxLength === 1 && /^(text|tel|number|)$/.test(el.type) && usable(el),
    );
    if (boxes.length < 6) return null;
    let box = boxes[0].parentElement;
    for (let up = 0; box && up < 4; up++, box = box.parentElement) {
      const group = boxes.filter((b) => box.contains(b));
      if (group.length === 6 || group.length === 8) {
        const hint =
          group.some((b) => b.autocomplete === 'one-time-code' || b.inputMode === 'numeric') ||
          /cod|code|verif|2fa|autentific|authenticat/i.test((box.innerText || '').slice(0, 500) + document.title);
        return hint ? group : null;
      }
    }
    return null;
  }

  function otpTargets(focused) {
    if (focused && isOtpField(focused) && usable(focused)) return [focused];
    const one = [...document.querySelectorAll('input')].find((el) => isOtpField(el) && usable(el));
    return one ? [one] : splitOtp();
  }

  /// true dacă a pus codul (atunci nu mai arătăm meniul).
  /// Căsuța cere un cod trimis pe email / SMS / WhatsApp, nu codul din
  /// aplicația de autentificare: acolo nu punem și nu propunem cod 2FA.
  function sentCodeField(el) {
    const box =
      el.closest('form,[role="dialog"],dialog') ??
      el.parentElement?.parentElement?.parentElement ??
      document.body;
    const text = `${(box.innerText || '').slice(0, 2000)} ${el.placeholder || ''} ${el.getAttribute('aria-label') || ''}`.toLowerCase();
    if (/aplica[țt]i[ae] de autentificare|authenticat(or|ion) app|google authenticator/.test(text)) {
      return false;
    }
    return /am trimis|(ți|ti)-am trimis|trimis (un |prin |pe |la )|e-?mail|\bsms\b|whatsapp|mesaj text|we sent|sent (a |you |to )|text message|check your (email|phone)/.test(
      text,
    );
  }

  async function autoOtp(focused = null) {
    if (autoBusy || Date.now() > autoUntil) return false;
    const targets = otpTargets(focused);
    if (!targets || targets.some((t) => autoTried.has(t))) return false;
    if (sentCodeField(targets[0])) return false;
    targets.forEach((t) => autoTried.add(t));
    autoBusy = true;
    try {
      const r = await send({ type: 'autoTotp' });
      if (!r?.code || !targets.every((t) => t.isConnected && !t.value)) return false;
      if (targets.length === 1) setValue(targets[0], r.code);
      else [...r.code].forEach((c, i) => targets[i] && setValue(targets[i], c));
      autoUntil = 0; // o singură dată pe pagină
      hideMenu();
      showToast({ result: 'otpFilled', username: r.username });
      return true;
    } finally {
      autoBusy = false;
    }
  }

  // câmpul de cod apare adesea după logare, fără reîncărcarea paginii
  let autoTimer = 0;
  const autoObs = new MutationObserver(() => {
    if (Date.now() > autoUntil) return autoObs.disconnect();
    clearTimeout(autoTimer);
    autoTimer = setTimeout(() => autoOtp(), 400);
  });
  autoObs.observe(document.documentElement, { childList: true, subtree: true });
  setTimeout(() => autoOtp(), 600);
  /// După „Completează”: pagina de cod poate veni în aceeași pagină.
  function armAutoOtp() {
    autoUntil = Date.now() + 3 * 60 * 1000;
    try {
      autoObs.observe(document.documentElement, { childList: true, subtree: true });
    } catch {}
  }

  function maybeShow(el) {
    if (!(el instanceof HTMLInputElement)) return;
    if (isOtpField(el)) {
      autoOtp(el).then((done) => {
        if (!done) showOtpMenu(el);
      });
      return;
    }
    const isPw = isPasswordField(el);
    const isUser = !isPw && el.matches(USER_SEL) && (passwordFields().length > 0 || /user|mail|login|email/i.test(`${el.name} ${el.id} ${el.autocomplete}`));
    if (isPw || isUser) showMenu(el);
  }

  document.addEventListener('focusin', (e) => maybeShow(e.target), true);
  document.addEventListener('click', (e) => {
    if (host.contains(e.target) || e.target === host) return;
    // clic din nou în câmpul deja selectat: panoul reapare
    if (e.target instanceof HTMLInputElement && menu.hidden) {
      maybeShow(e.target);
      return;
    }
    if (menuFor && e.target !== menuFor) hideMenu();
  }, true);
  // derularea paginii ascunde panoul; derularea ÎN panou (lista lungă), nu
  addEventListener(
    'scroll',
    (e) => {
      if (e.target === host || host.contains(e.target)) return;
      hideMenu();
    },
    true,
  );

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
    const change = isChangeForm(pws);
    const user = change ? clearUserField(scope) : userFieldFor(pws[0]);
    send({
      type: 'captured',
      username: user?.value?.trim() ?? '',
      password: pw.value,
      change,
    }).then((info) => {
      showToast(info);
      // afișat deja aici: nu-l mai repetăm pe pagina următoare dacă nu
      // s-a navigat
      if (info && isTop) setTimeout(() => send({ type: 'takeToast' }), 4000);
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
    } else if (info.result === 'generatedKept') {
      html = `🔑 Parola generată e ținută minte în Notițe (${info.count > 1 ? `la cele ${info.count} conturi` : 'la contul'} <b>${esc(info.site)}</b>). După ce o salvezi pe site, confirm-o din iconița Notițe („Folosește-o”) sau din aplicație.
        <div class="row"><button class="pri" data-a="ok">OK</button></div>`;
    } else if (info.result === 'otpFilled') {
      html = `${AUTH_SVG} Codul 2FA din Notițe${who} a fost completat. Apasă tu butonul de confirmare de pe site.
        <div class="row"><button class="pri" data-a="ok">OK</button></div>`;
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
    if (msg?.type === 'doFill') {
      fill(msg.username, msg.password);
      armAutoOtp();
    }
  });

  // mesajul rămas de la pagina anterioară (logarea a navigat)
  if (isTop) send({ type: 'takeToast' }).then(showToast);
})();
