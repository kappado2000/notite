// Potrivirea site-urilor: „domeniul de bază” (ex. emag.ro, bt.ro,
// google.com), ca login.bt.ro și www.bt.ro să fie același site.

const TWO_PART = new Set([
  'co.uk', 'org.uk', 'ac.uk', 'gov.uk', 'com.ro', 'org.ro', 'info.ro',
  'nom.ro', 'com.au', 'net.au', 'co.nz', 'co.jp', 'com.br', 'com.tr',
  'co.za', 'com.mx', 'com.ar', 'co.in', 'com.cn', 'com.hk', 'com.sg',
]);

// Găzduiri comune: fiecare subdomeniu e ALT proprietar (afm.b2clogin.com și
// altceva.b2clogin.com sunt firme diferite) — site-ul e numele complet.
const SHARED = new Set([
  'b2clogin.com', 'azurewebsites.net', 'onmicrosoft.com', 'cloudapp.net',
  'github.io', 'gitlab.io', 'herokuapp.com', 'web.app', 'firebaseapp.com',
  'appspot.com', 'netlify.app', 'vercel.app', 'pages.dev', 'workers.dev',
  'blogspot.com', 'wordpress.com', 'wixsite.com', 'myshopify.com',
  'cloudfront.net', 'amazonaws.com', 'glitch.me', 'onrender.com',
  'fly.dev', 'ngrok.io', 'ngrok-free.app', 'sharepoint.com',
]);

export function hostOf(url) {
  if (!url) return '';
  let s = String(url).trim().toLowerCase();
  if (!/^[a-z][a-z0-9+.-]*:\/\//.test(s)) s = 'https://' + s;
  try {
    return new URL(s).hostname.replace(/^www\./, '');
  } catch {
    return '';
  }
}

export function baseDomain(url) {
  const host = hostOf(url);
  if (!host || /^\d+\.\d+\.\d+\.\d+$/.test(host)) return host;
  const parts = host.split('.');
  if (parts.length <= 2) return host;
  const lastTwo = parts.slice(-2).join('.');
  return TWO_PART.has(lastTwo) || SHARED.has(lastTwo)
    ? parts.slice(-3).join('.')
    : lastTwo;
}

/// Un nume frumos pentru titlu: „emag.ro” → „Emag”.
export function siteTitle(url) {
  const base = baseDomain(url);
  const name = base.split('.')[0] || base;
  return name.charAt(0).toUpperCase() + name.slice(1);
}

/// Intrarea se potrivește cu pagina? După adresă; dacă intrarea nu are
/// adresă, după titlu (ex. titlul „eMAG” pe emag.ro).
// Același cont pe mai multe domenii ale aceleiași firme (Apple ID cu
// adresă @icloud.com se folosește pe apple.com și invers).
const SAME_ACCOUNT = {
  'icloud.com': 'apple.com',
  'me.com': 'apple.com',
  'appleid.com': 'apple.com',
  'gmail.com': 'google.com',
};

function accountSite(url) {
  const b = baseDomain(url);
  return SAME_ACCOUNT[b] ?? b;
}

export function matches(item, pageUrl) {
  const page = accountSite(pageUrl);
  if (!page) return false;
  // „Alte site-uri” ale contului (adăugate de tine: „Folosește și aici”)
  for (const u of item.sites ?? []) {
    if (u && accountSite(u) === page) return true;
  }
  if (item.url) return accountSite(item.url) === page;
  const t = (item.title || '').toLowerCase().replace(/\s+/g, '');
  const name = page.split('.')[0];
  return t.length >= 3 && (t === name || t === page);
}
