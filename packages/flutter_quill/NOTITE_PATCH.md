# flutter_quill 11.6.0 — copie locală cu o corectură

Copie a pachetului `flutter_quill` 11.6.0 (licență MIT, vezi LICENSE),
folosită prin `dependency_overrides` din pubspec.yaml-ul aplicației.

Singura modificare: `lib/src/editor/raw_editor/raw_editor_state_text_input_client_mixin.dart`,
`_updateComposingRectIfNeeded` — raportează către sistem întreaga zonă a
textului în compunere (start → end), nu doar poziția de început.

Motiv: pe iOS, la dictare, bula cu microfonul și limba era afișată peste
textul dictat.

La actualizarea flutter_quill: verifică dacă problema e rezolvată în
versiunea nouă; dacă da, șterge acest folder și override-ul.

## A doua modificare: texte-exemplu pe rânduri (șabloane)

`lib/src/editor/widgets/text/text_line.dart`: un rând gol cu atributul
`hint` (text) afișează textul gri; atingerea pune cursorul la începutul
rândului. `lineHintKey` / `lineHintOf` sunt exportate din
`flutter_quill.dart`. Atributul nu e înregistrat (scope `ignore`) și se
salvează în Delta; aplicația îl scoate de pe rândul pe care s-a scris.
