// Scans src/translations/locales/pt-BR/*.json for keys whose value is an
// empty string (i18next's "untranslated, falls back to English" marker) and
// writes a report listing exactly what needs to be translated, so a fresh
// Claude invocation can fill in only what's missing instead of the whole file.
const fs = require('fs');
const path = require('path');

const localesDir = path.join(__dirname, '..', 'src', 'translations', 'locales');
const files = ['logbook.json', 'pokemon.json', 'questlines.json', 'settings.json'];

function collectEmpty(enObj, ptObj, prefix, out) {
    for (const key of Object.keys(enObj)) {
        const enVal = enObj[key];
        if (typeof enVal === 'string') {
            const ptVal = ptObj ? ptObj[key] : undefined;
            if (ptVal === '' || ptVal === undefined) {
                out.push({ key: prefix + key, english: enVal });
            }
        } else if (enVal && typeof enVal === 'object') {
            collectEmpty(enVal, ptObj ? ptObj[key] : undefined, prefix + key + '.', out);
        }
    }
}

const report = {};
let total = 0;

for (const file of files) {
    const enPath = path.join(localesDir, 'en', file);
    const ptPath = path.join(localesDir, 'pt-BR', file);
    if (!fs.existsSync(enPath) || !fs.existsSync(ptPath)) continue;

    const en = JSON.parse(fs.readFileSync(enPath, 'utf8'));
    const pt = JSON.parse(fs.readFileSync(ptPath, 'utf8'));
    const missing = [];
    collectEmpty(en, pt, '', missing);
    if (missing.length) {
        report[file] = missing;
        total += missing.length;
    }
}

const outPath = path.join(__dirname, 'missing-translations.json');
fs.writeFileSync(outPath, JSON.stringify(report, null, 2), 'utf8');

console.log(`Found ${total} missing pt-BR translation(s) across ${Object.keys(report).length} file(s).`);
console.log(`Report written to ${outPath}`);
process.exit(total > 0 ? 1 : 0); // non-zero exit signals "translation work needed" to the caller
