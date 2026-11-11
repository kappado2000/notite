# Notițe – Parole (extensie Chrome / Edge)

Salvează automat parolele în seiful criptat Notițe și le completează pe
site-urile lor. Aceleași date ca în aplicație (Parole → Conturi).

## Instalare (o singură dată)

1. Deschide `chrome://extensions` (sau `edge://extensions`).
2. Pornește **Modul dezvoltator** (colțul din dreapta sus; în Edge, în stânga jos).
3. **Încarcă extensia neîmpachetată** → alege folderul acesta (`Notite\extension`).
4. Fixează iconița (pioneza din meniul de extensii) și apasă pe ea.
5. Conectează-te cu emailul și parola contului Notițe.

## Ce face

- **Salvează automat** parolele noi când te înregistrezi sau te conectezi
  pe un site (mesaj „Salvat în Notițe” cu „Anulează”).
- **Parolă schimbată** la un cont existent: te **întreabă** înainte să o
  actualizeze (poate fi o parolă greșită tastată); cea veche rămâne în istoric.
- **Completează**: la câmpul de utilizator / parolă îți propune conturile
  salvate pentru acel site.
- **Generează** parole puternice pe paginile de înregistrare.
- **Coduri 2FA**: la câmpul pentru codul de verificare îți propune codul de 6
  cifre al contului (dacă are cheia 2FA salvată în Notițe); în iconiță, 🔢 îl
  copiază.
- **Caută și copiază** din iconița extensiei; parola copiată se șterge din
  clipboard după 30 de secunde.

## Siguranță

- Criptare end-to-end, aceeași ca în aplicație (AES-256-GCM, cheia
  protejată cu PBKDF2 din parola contului). În cloud ajunge doar text criptat.
- Cheia și parolele decriptate stau doar în memoria browserului, nu pe disc;
  dispar la închiderea browserului și după **15 minute** fără folosire.
- Conectarea la cont rămâne ținută minte (ca în aplicația de pe telefon):
  după repornirea browserului ceri doar parola Notițe, fără email și cod 2FA.
  „Deconectează-te” o șterge.
- Paginile web nu au acces la seif. Un site primește o parolă doar dacă e
  site-ul ei (un site fals, ex. `emag-login.xyz`, nu primește parola eMAG),
  doar prin HTTPS și doar când alegi tu contul.
- Fără servere sau coduri externe: extensia vorbește doar cu Firebase-ul
  aplicației Notițe.

## Teste

- `node --test extension/test/domain.test.mjs` — cine primește parola.
- `node --test extension/test/totp.test.mjs` — codurile 2FA (vectorii RFC 6238).
- `flutter test test/extension_crypto_test.dart` — extensia citește și scrie
  exact ca aplicația.

## Actualizare

După o versiune nouă: `chrome://extensions` → pe cardul Notițe apasă ↻.
