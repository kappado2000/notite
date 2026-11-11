// Potrivirea site-urilor: „domeniul de bază” (ex. emag.ro, bt.ro,
// google.com), ca login.bt.ro și www.bt.ro să fie același site.

const TWO_PART = new Set([
  'co.uk', 'org.uk', 'ac.uk', 'gov.uk', 'com.ro', 'org.ro', 'info.ro',
  'nom.ro', 'com.au', 'net.au', 'co.nz', 'co.jp', 'com.br', 'com.tr',
  'co.za', 'com.mx', 'com.ar', 'co.in', 'com.cn', 'com.hk', 'com.sg',
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
  return TWO_PART.has(lastTwo) ? parts.slice(-3).join('.') : lastTwo;
}

/// Un nume frumos pentru titlu: „emag.ro” → „Emag”.
export function siteTitle(url) {
  const base = baseDomain(url);
  const name = base.split('.')[0] || base;
  return name.charAt(0).toUpperCase() + name.slice(1);
}

/// Intrarea se potrivește cu pagina? După adresă; dacă intrarea nu are
/// adresă, după titlu (ex. titlul „eMAG” pe emag.ro).
export function matches(item, pageUrl) {
  const page = baseDomain(pageUrl);
  if (!page) return false;
  if (item.url) return baseDomain(item.url) === page;
  const t = (item.title || '').toLowerCase().replace(/\s+/g, '');
  const name = page.split('.')[0];
  return t.length >= 3 && (t === name || t === page);
}
