// Document ascuns, folosit doar ca să golească clipboardul după ce ai
// copiat o parolă (serviciul din fundal nu are acces la clipboard).
chrome.runtime.onMessage.addListener((msg) => {
  if (msg?.type !== 'offscreen-clear') return;
  const t = document.getElementById('t');
  t.value = ' ';
  t.select();
  document.execCommand('copy');
  t.value = '';
  setTimeout(() => window.close(), 500);
});
