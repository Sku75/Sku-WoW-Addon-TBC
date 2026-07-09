#!/usr/bin/env python3
# Scan Sku code for locale problems:
#  1. L["key"] usages whose key is not registered in enUS locale -> falls back to raw (German) key
#  2. German-looking string literals NOT wrapped in L[] (hardcoded German reaching all clients)
import sys, re, io, os, json

ROOT = sys.argv[1]  # Sku/
EN = os.path.join(ROOT, 'locales', 'enUS.lua')
OUT = sys.argv[2]

def decode(body):
    out, i = [], 0
    while i < len(body):
        c = body[i]
        if c == '\\' and i + 1 < len(body):
            out.append({'n': '\n', 't': '\t'}.get(body[i+1], body[i+1])); i += 2
        else:
            out.append(c); i += 1
    return ''.join(out)

rx_entry = re.compile(r'^\s*L\["(.*?(?<!\\))"\]\s*=')
en_keys = set()
with io.open(EN, encoding='utf-8-sig') as f:
    for line in f:
        m = rx_entry.match(line)
        if m:
            en_keys.add(decode(m.group(1)))

GERMAN_RX = re.compile(r'[äöüÄÖÜß]|\b(Eingabe|Taste|Gegenstand|Gegenstände|Auswahl|Einstellung(en)?|abgebrochen|Abbrechen|aktiviert|deaktiviert|ausgewählt|gefunden|verfügbar|Fehler|erfolgreich|geöffnet|geschlossen|Seite|Hilfe|Wähle|Drücke|drücke|nicht|keine?|wirklich|Stufe|Menge|Preis|Gebot|Kaufen|Verkaufen|Briefe?|Anhänge?|Empfänger|Betreff|Gold|Silber|Kupfer|Fenster|beendet|gestartet|Neue[rs]?|Aktuelle[rs]?|zurück|weiter|Nächste[rs]?|vergriffen|leer|voll)\b')

rx_Luse = re.compile(r'L\["(.*?(?<!\\))"\]')
rx_str = re.compile(r'"((?:[^"\\]|\\.)*)"')

missing_keys = {}   # key -> [file:line, ...]
hardcoded = []      # {file, line, text}

for dirpath, dirnames, filenames in os.walk(ROOT):
    rel = os.path.relpath(dirpath, ROOT).replace('\\', '/')
    if rel.startswith(('locales', 'Libs', 'SkuDB', 'SkuAudioData')) :
        continue
    for fn in filenames:
        if not fn.endswith('.lua'):
            continue
        path = os.path.join(dirpath, fn)
        relf = os.path.relpath(path, ROOT).replace('\\', '/')
        with io.open(path, encoding='utf-8-sig', errors='replace') as f:
            for lineno, line in enumerate(f, 1):
                code = line
                # strip full-line and trailing comments crudely (avoid urls "--" inside strings is rare)
                ci = code.find('--')
                if ci != -1:
                    # keep if the -- is inside a string: count quotes before it
                    if code[:ci].count('"') % 2 == 0:
                        code = code[:ci]
                if not code.strip():
                    continue
                spans = []
                for m in rx_Luse.finditer(code):
                    k = decode(m.group(1))
                    spans.append((m.start(1)-1, m.end(1)+1))
                    if k not in en_keys and k != '':
                        missing_keys.setdefault(k, []).append('%s:%d' % (relf, lineno))
                for m in rx_str.finditer(code):
                    # skip strings that are part of an L[...] usage
                    if any(s <= m.start() < e for s, e in spans):
                        continue
                    txt = decode(m.group(1))
                    if len(txt) < 3:
                        continue
                    if GERMAN_RX.search(txt):
                        hardcoded.append({'file': relf, 'line': lineno, 'text': txt[:160]})

report = {
    'counts': {'enUS_keys': len(en_keys),
               'used_keys_missing_in_enUS': len(missing_keys),
               'hardcoded_german_literals': len(hardcoded)},
    'used_keys_missing_in_enUS': [
        {'key': k, 'sites': v} for k, v in sorted(missing_keys.items())],
    'hardcoded_german_literals': hardcoded,
}
with io.open(OUT, 'w', encoding='utf-8') as f:
    json.dump(report, f, ensure_ascii=False, indent=1)
print(json.dumps(report['counts'], indent=1))
