#!/usr/bin/env python3
# Diff Sku locale files: find keys present in deDE but missing in enUS (and vice versa),
# plus enUS entries whose value is identical to the (German-looking) key = likely untranslated.
import sys, re, json, io

def parse_locale(path):
    """Return dict key->value from lines of the form L["key"] = "value".
    Handles escaped quotes. Ignores anything after the closing quote of the value."""
    entries = {}
    order = []
    rx = re.compile(r'^\s*L\[(".*?(?<!\\)")\]\s*=\s*(".*?(?<!\\)")')
    with io.open(path, encoding='utf-8-sig') as f:
        for lineno, line in enumerate(f, 1):
            s = line.strip()
            if not s.startswith('L['):
                continue
            m = rx.match(line)
            if not m:
                # value may be 'true' (AceLocale shorthand) or something odd
                m2 = re.match(r'^\s*L\[(".*?(?<!\\)")\]\s*=\s*true', line)
                if m2:
                    k = decode(m2.group(1))
                    entries[k] = k
                    order.append((lineno, k))
                else:
                    print('UNPARSED %s:%d: %s' % (path, lineno, s[:120]))
                continue
            k = decode(m.group(1))
            v = decode(m.group(2))
            if k in entries and entries[k] != v:
                print('DUPLICATE key with differing value %s:%d: %r' % (path, lineno, k[:80]))
            entries[k] = v
            order.append((lineno, k))
    return entries, order

def decode(luastr):
    # strip quotes, unescape \" \\ \n
    body = luastr[1:-1]
    out = []
    i = 0
    while i < len(body):
        c = body[i]
        if c == '\\' and i + 1 < len(body):
            n = body[i+1]
            out.append({'n': '\n', 't': '\t'}.get(n, n))
            i += 2
        else:
            out.append(c)
            i += 1
    return ''.join(out)

def looks_german(s):
    if re.search(r'[äöüÄÖÜß]', s):
        return True
    words = r'\b(und|oder|nicht|mit|für|von|zum|zur|der|die|das|des|dem|ein|eine|einen|kein|keine|wird|wurde|ist|sind|du|dein|deine|bitte|Eingabe|Taste|Gegenstand|Gegenstände|Fenster|Auswahl|Einstellung|Einstellungen|beendet|gestartet|aktiviert|deaktiviert|ausgewählt|gefunden|verfügbar|Verfügbar|Fehler|erfolgreich|abgebrochen|Abbrechen|geöffnet|geschlossen|Seite|Liste|Hilfe|Neue|Neuer|Neues|Aktuelle|Aktueller|Aktuelles|wähle|Wähle|drücke|Drücke|drücken)\b'
    return re.search(words, s) is not None

de, de_order = parse_locale(sys.argv[1])
en, en_order = parse_locale(sys.argv[2])

missing_in_en = [k for _, k in de_order if k not in en]
missing_in_de = [k for _, k in en_order if k not in de]
# enUS entries whose value still looks German (value==key only counts if key looks German)
untranslated = [k for k in en if en[k] == k and looks_german(k)]
# enUS entries where value != key but value itself looks German
german_values = [k for k in en if en[k] != k and looks_german(en[k])]

report = {
    'counts': {'deDE': len(de), 'enUS': len(en),
               'missing_in_enUS': len(missing_in_en),
               'missing_in_deDE': len(missing_in_de),
               'enUS_value_eq_german_key': len(untranslated),
               'enUS_value_looks_german': len(german_values)},
    'missing_in_enUS': [{'key': k, 'de': de[k]} for k in missing_in_en],
    'missing_in_deDE': missing_in_de,
    'enUS_value_eq_german_key': untranslated,
    'enUS_value_looks_german': [{'key': k, 'en': en[k]} for k in german_values],
}
with io.open(sys.argv[3], 'w', encoding='utf-8') as f:
    json.dump(report, f, ensure_ascii=False, indent=1)
print(json.dumps(report['counts'], indent=1))
