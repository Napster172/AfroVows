# Translations

`public/i18n.js` swaps the English on screen for the chosen language. Each `public/i18n/<lang>.js`
maps English text to a translation. Numbers and dates in a phrase are replaced by `{0}`, `{1}`…,
so `"4 of 20 to-dos"` matches the key `"{0} of {1} to-dos"`. Text without a match stays in English.

To fix a translation: edit the line in `tools/i18n/<lang>.txt` (format `index|translation`, the index
points into `master.json`), then run `python3 tools/i18n/build.py` to regenerate `public/i18n/*.js`.
To add new English text: append it to `master.json` and add a line to each `<lang>.txt`.
