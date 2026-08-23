#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Turn the hand-written patch-note TEXT files into the website's HTML pages.

Input : docs/Patch-Notes-{English,Deutsch,Francais}.txt  (synced from Sku/ by
        installer/release.ps1 -> Sync-PatchNotesToDocs)
Output: docs/patchnotes/<lang>/index.html   - the version list for that language
        docs/patchnotes/<lang>/v<ver>.html  - one page per released version

The text files are hand-wrapped at ~90 columns and carry their structure in the
indentation alone.  Levels seen in the corpus:

    0   "Changes in Sku v43.0"                     - version header
    4   "Overview" / "Navigation: waypoints ..."   - section heading
    8   "New"/"Changes"/"Bugfixes"                 - sub heading (has children)
    8   "Simple: <prose>"                          - paragraph (wraps into 12)
    12  bullet under a sub heading, or a wrap line

A deeper-indented line is a WRAP of the line above when that line ran to the
wrap column, and a CHILD of it when it stopped short - which is exactly how a
human reads the file, and the only signal the format actually carries.
Older versions (v41 and down) use tabs and "- " bullets; both are normalised.

Run:  py -3 dev/rework-docs/_gen_patchnotes_html.py
"""

import html
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
DOCS = os.path.join(ROOT, 'docs')
OUT_ROOT = os.path.join(DOCS, 'patchnotes')

# A line that reached at least this many columns was cut off by the wrap, so
# whatever follows it one level deeper is its continuation, not its child.
WRAP_MIN = 78
# ... and a line PAST this was never wrapped at all - the overview entries are
# written as one line each, up to ~590 columns.
WRAP_MAX = 100
SENTENCE_END = ('.', '!', '?', ':', ';', '."', '.)', ' »')

SEP_RE = re.compile(r'^-{10,}\s*$')
BULLET_RE = re.compile(r'^[-*•]\s+')

LANGS = [
    {
        'code': 'en',
        'html_lang': 'en',
        'name': 'English',
        'src': 'Patch-Notes-English.txt',
        'txt': '../../Patch-Notes-English.txt',
        'home': '../../index.html',
        'header': re.compile(r'^(?:Changes in Sku)\s+v?(\S+)(.*)$'),
        'label': re.compile(r'^(Simple|Simply|Technical|Technically)\s*:\s*'),
        'title': 'Sku patch notes',
        'title_one': 'Sku {ver} - patch notes',
        'intro': 'What changed in each version of Sku for World of Warcraft '
                 'The Burning Crusade Anniversary. Newest version first.',
        'toc': 'All versions',
        'back': 'All patch notes',
        'home_label': 'Sku download page',
        'newer': 'Newer version: {ver}',
        'older': 'Older version: {ver}',
        'plain': 'Every version in one plain text file',
        'latest': 'current version',
        'nav_label': 'Patch note navigation',
        'lang_nav': 'Patch notes language',
    },
    {
        'code': 'de',
        'html_lang': 'de',
        'name': 'Deutsch',
        'src': 'Patch-Notes-Deutsch.txt',
        'txt': '../../Patch-Notes-Deutsch.txt',
        'home': '../../index-de.html',
        'header': re.compile(r'^(?:Aenderungen in Sku|Änderungen in Sku|Changes in Sku)\s+v?(\S+)(.*)$'),
        'label': re.compile(r'^(Einfach|Technisch|Simple|Technical)\s*:\s*'),
        'title': 'Sku Patchnotes',
        'title_one': 'Sku {ver} - Patchnotes',
        'intro': 'Was sich in jeder Version von Sku fuer World of Warcraft '
                 'The Burning Crusade Anniversary geaendert hat. Neueste '
                 'Version zuerst.',
        'toc': 'Alle Versionen',
        'back': 'Alle Patchnotes',
        'home_label': 'Sku Downloadseite',
        'newer': 'Neuere Version: {ver}',
        'older': 'Aeltere Version: {ver}',
        'plain': 'Alle Versionen in einer Textdatei',
        'latest': 'aktuelle Version',
        'nav_label': 'Navigation in den Patchnotes',
        'lang_nav': 'Sprache der Patchnotes',
    },
    {
        'code': 'fr',
        'html_lang': 'fr',
        'name': 'Français',
        'src': 'Patch-Notes-Francais.txt',
        'txt': '../../Patch-Notes-Francais.txt',
        'home': '../../index-fr.html',
        'header': re.compile(r'^(?:Changements dans Sku|Changes in Sku)\s+v?(\S+)(.*)$'),
        'label': re.compile(r'^(Simple|Simplement|Technique|Techniquement|En clair)\s*:\s*'),
        'title': 'Notes de version de Sku',
        'title_one': 'Sku {ver} - notes de version',
        'intro': 'Ce qui a changé dans chaque version de Sku pour World of '
                 'Warcraft The Burning Crusade Anniversary. Version la plus '
                 'récente en premier.',
        'toc': 'Toutes les versions',
        'back': 'Toutes les notes de version',
        'home_label': 'Page de téléchargement de Sku',
        'newer': 'Version plus récente : {ver}',
        'older': 'Version plus ancienne : {ver}',
        'plain': 'Toutes les versions dans un seul fichier texte',
        'latest': 'version actuelle',
        'nav_label': 'Navigation dans les notes de version',
        'lang_nav': 'Langue des notes de version',
    },
]


# --------------------------------------------------------------------------
# parsing
# --------------------------------------------------------------------------

def read_lines(path):
    with open(path, encoding='utf-8-sig') as fh:
        return [ln.rstrip('\n').rstrip('\r').rstrip() for ln in fh]


def split_versions(lines, header_re):
    """-> (preamble_lines, [ {ver, suffix, lines} ]) in file order."""
    blocks = []
    cur = None
    preamble = []
    for raw in lines:
        if SEP_RE.match(raw):
            continue
        m = header_re.match(raw) if not raw[:1].isspace() else None
        if m:
            cur = {'ver': m.group(1), 'suffix': m.group(2).strip(), 'lines': []}
            blocks.append(cur)
            continue
        if cur is None:
            preamble.append(raw)
        else:
            cur['lines'].append(raw)
    return preamble, blocks


def normalise(raw):
    """-> (level, text, is_bullet, width) for one physical line, or None."""
    if not raw.strip():
        return None
    expanded = raw.expandtabs(4)
    stripped = expanded.lstrip(' ')
    indent = len(expanded) - len(stripped)
    is_bullet = bool(BULLET_RE.match(stripped))
    if is_bullet:
        stripped = BULLET_RE.sub('', stripped, count=1)
    # Round to the nearest 4-column step: the corpus mixes 4-space and tab
    # indentation and a couple of hand-typed odd columns.
    level = int(round(indent / 4.0))
    return (level, stripped, is_bullet, len(expanded))


def build_items(lines, label_re):
    """Physical lines -> logical items [{level, text, bullet, children}].

    A deeper line continues the item above it when that item's last physical
    line hit the wrap column; otherwise it opens a child item.  The one place
    where that alone is not enough is a section heading long enough to reach
    the wrap column - "Taxi flight: the landing announcements can be switched
    off - and they no longer name ..." is 152 columns on ONE line, and its
    body starts one level deeper, exactly like a wrap would.  What separates
    the two everywhere in the corpus is the body's marker: a heading is
    followed by "Simple:"/"Einfach:"/"Simple :", a wrapped paragraph never is.
    """
    root = {'level': 0, 'text': '', 'bullet': False, 'children': []}
    stack = [root]
    last = None          # the item the previous physical line belonged to
    last_width = 0
    blank_since_last = False

    for raw in lines:
        n = normalise(raw)
        if n is None:
            blank_since_last = True
            continue
        level, text, bullet, width = n

        joinable = (last is not None and not bullet and not blank_since_last
                    and not label_re.match(text))

        # Deeper indentation after a line that ran into the wrap column is the
        # rest of that line.
        if joinable and level > last['level'] and last_width >= WRAP_MIN:
            last['text'] += ' ' + text
            last_width = width
            continue

        # Same indentation is ambiguous: it is either the next entry of a list
        # or the next line of a paragraph.  Two things separate them - a list
        # entry is a finished sentence, and it is written on ONE line however
        # long (the overview entries run past 500 columns), while wrapped prose
        # breaks mid-sentence.  The width floor must NOT apply here: a line
        # ending in front of "GetAllLinkedWPsInRangeToCoords" wraps 25 columns
        # early and is still a wrap.  The colon counts as an ending on purpose,
        # it is how a list announces itself ("in the order you meet them:").
        if (joinable and level == last['level'] and not last['bullet']
                and last_width <= WRAP_MAX
                and not last['text'].rstrip().endswith(SENTENCE_END)):
            last['text'] += ' ' + text
            last_width = width
            continue

        item = {'level': level, 'text': text, 'bullet': bullet, 'children': []}
        while len(stack) > 1 and stack[-1]['level'] >= level:
            stack.pop()
        stack[-1]['children'].append(item)
        stack.append(item)
        last = item
        last_width = width
        blank_since_last = False

    return root['children']


# --------------------------------------------------------------------------
# rendering
# --------------------------------------------------------------------------

def esc(s):
    return html.escape(s, quote=False)


def with_label(text, label_re):
    """Bold a leading "Simple:" / "Technisch:" / "Technique :" marker."""
    m = label_re.match(text)
    if not m:
        return esc(text)
    return '<strong>%s</strong> %s' % (esc(m.group(0).strip()),
                                       esc(text[m.end():]))


def looks_like_heading(item):
    """A short line with children and no sentence end is a sub heading."""
    if not item['children'] or item['bullet']:
        return False
    t = item['text']
    return len(t) <= 60 and not t.endswith(('.', '!', '?', ':', ';'))


def render_items(items, depth, lang, out):
    """depth 1 -> h2, 2 -> h3, deeper -> paragraphs / list items."""
    i = 0
    while i < len(items):
        item = items[i]
        # a run of bullets at this level becomes one list
        if item['bullet']:
            j = i
            out.append('<ul>')
            while j < len(items) and items[j]['bullet']:
                chunk = ['<li>%s' % with_label(items[j]['text'], lang['label'])]
                if items[j]['children']:
                    sub = []
                    render_items(items[j]['children'], depth + 1, lang, sub)
                    chunk.append('\n'.join(sub))
                chunk.append('</li>')
                out.append('\n'.join(chunk))
                j += 1
            out.append('</ul>')
            i = j
            continue

        if depth <= 2:
            # depth 1 -> h2, depth 2 -> h3.  A depth-1 item without children is
            # not a section but a stray paragraph ("Measured for comparison: ..."
            # sits at heading indentation but is prose), so it falls through.
            tag = 'h%d' % (depth + 1)
            if depth == 1 and not item['children']:
                tag = None
            if depth == 2 and not looks_like_heading(item):
                tag = None
            if tag:
                out.append('<%s>%s</%s>' % (tag, esc(item['text']), tag))
                # "New" / "Changes" / "Bugfixes" hold one flat run of entries -
                # that is a list, and reads as one to a screen reader.  Labelled
                # prose ("Simple: ...") under a section heading is not.
                kids = item['children']
                if (depth == 2 and kids
                        and all(not k['children'] and not k['bullet']
                                and not lang['label'].match(k['text'])
                                for k in kids)):
                    out.append('<ul>')
                    for k in kids:
                        out.append('<li>%s</li>' % esc(k['text']))
                    out.append('</ul>')
                else:
                    render_items(kids, depth + 1, lang, out)
                i += 1
                continue

        # plain prose: this item and everything under it are paragraphs
        out.append('<p>%s</p>' % with_label(item['text'], lang['label']))
        if item['children']:
            render_items(item['children'], depth + 1, lang, out)
        i += 1


def render_version_body(block, lang):
    items = build_items(block['lines'], lang['label'])
    out = []
    render_items(items, 1, lang, out)
    return '\n'.join(out)


# --------------------------------------------------------------------------
# page shells
# --------------------------------------------------------------------------

def page(lang, title, body):
    return (
        '<!DOCTYPE html>\n'
        '<html lang="%s">\n'
        '<head>\n'
        '<meta charset="UTF-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1.0">\n'
        '<title>%s</title>\n'
        '<link rel="stylesheet" href="../../sku.css">\n'
        '</head>\n'
        '<body>\n%s\n</body>\n</html>\n'
    ) % (lang['html_lang'], esc(title), body)


def lang_nav(lang, page_name, available):
    """Language switcher that keeps you on the same version where it exists."""
    items = []
    for other in LANGS:
        label = esc(other['name'])
        if other['code'] == lang['code']:
            items.append('<li><span aria-current="page" lang="%s">%s</span></li>'
                         % (other['html_lang'], label))
        elif other['code'] in available:
            items.append('<li><a href="../%s/%s" lang="%s" hreflang="%s">%s</a></li>'
                         % (other['code'], page_name, other['html_lang'],
                            other['html_lang'], label))
        else:
            items.append('<li><a href="../%s/index.html" lang="%s" hreflang="%s">%s</a></li>'
                         % (other['code'], other['html_lang'],
                            other['html_lang'], label))
    return ('<nav aria-label="%s">\n<ul class="langnav">\n%s\n</ul>\n</nav>'
            % (esc(lang['lang_nav']), '\n'.join(items)))


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(text)


def main():
    # which versions exist in which language, so the language switcher can stay
    # on the same version instead of dumping you at the top of another list
    per_lang = {}
    for lang in LANGS:
        src = os.path.join(DOCS, lang['src'])
        if not os.path.exists(src):
            print('missing: %s' % src)
            continue
        preamble, blocks = split_versions(read_lines(src), lang['header'])
        per_lang[lang['code']] = (lang, preamble, blocks)

    where = {}   # version -> set(lang codes)
    for code, (_lang, _pre, blocks) in per_lang.items():
        for b in blocks:
            where.setdefault(b['ver'], set()).add(code)

    written = 0
    for code, (lang, preamble, blocks) in per_lang.items():
        outdir = os.path.join(OUT_ROOT, code)

        # ---- one page per version -------------------------------------
        for idx, block in enumerate(blocks):
            ver = block['ver']
            fname = 'v%s.html' % ver
            newer = blocks[idx - 1] if idx > 0 else None
            older = blocks[idx + 1] if idx + 1 < len(blocks) else None
            title = lang['title_one'].format(ver='v' + ver)
            if block['suffix']:
                title += ' ' + block['suffix']

            nav = ['<nav aria-label="%s">' % esc(lang['nav_label']),
                   '<ul class="pagenav">',
                   '<li><a href="index.html">%s</a></li>' % esc(lang['back'])]
            if newer:
                nav.append('<li><a href="v%s.html">%s</a></li>'
                           % (newer['ver'], esc(lang['newer'].format(ver='v' + newer['ver']))))
            if older:
                nav.append('<li><a href="v%s.html">%s</a></li>'
                           % (older['ver'], esc(lang['older'].format(ver='v' + older['ver']))))
            nav.append('<li><a href="%s">%s</a></li>'
                       % (lang['home'], esc(lang['home_label'])))
            nav.append('</ul>')
            nav.append('</nav>')
            nav_html = '\n'.join(nav)

            body = '\n'.join([
                lang_nav(lang, fname, where.get(ver, set())),
                '<h1>%s</h1>' % esc(title),
                nav_html,
                '<main>',
                render_version_body(block, lang),
                '</main>',
                '<hr>',
                nav_html,
            ])
            write(os.path.join(outdir, fname), page(lang, title, body))
            written += 1

        # ---- the version list -----------------------------------------
        lis = []
        for idx, block in enumerate(blocks):
            ver = block['ver']
            extra = ' %s' % esc(block['suffix']) if block['suffix'] else ''
            tag = ''
            if idx == 0:
                tag = ' <span class="latest">(%s)</span>' % esc(lang['latest'])
            lis.append('<li><a href="v%s.html">Sku v%s</a>%s%s</li>'
                       % (ver, esc(ver), extra, tag))

        pre_paras = []
        for para in ('\n'.join(preamble)).split('\n\n'):
            flat = ' '.join(para.split())
            if not flat or flat.startswith('- '):
                continue
            pre_paras.append('<p>%s</p>' % esc(flat))

        body = '\n'.join([
            lang_nav(lang, 'index.html', set(per_lang.keys())),
            '<h1>%s</h1>' % esc(lang['title']),
            '<p>%s</p>' % esc(lang['intro']),
            '\n'.join(pre_paras),
            '<p><a href="%s">%s</a></p>' % (lang['home'], esc(lang['home_label'])),
            '<h2>%s</h2>' % esc(lang['toc']),
            '<ul class="versionlist">',
            '\n'.join(lis),
            '</ul>',
            '<p><a href="%s" download>%s</a></p>' % (lang['txt'], esc(lang['plain'])),
        ])
        write(os.path.join(outdir, 'index.html'), page(lang, lang['title'], body))
        written += 1
        print('%s: %d versions' % (code, len(blocks)))

    # /patchnotes/ itself: a link handed around without the language part must
    # not land on a 404.
    picks = '\n'.join(
        '<li><a href="%s/index.html" lang="%s" hreflang="%s">%s - %s</a></li>'
        % (l['code'], l['html_lang'], l['html_lang'], esc(l['name']),
           esc(l['title']))
        for l in LANGS if l['code'] in per_lang)
    root = (
        '<!DOCTYPE html>\n<html lang="en">\n<head>\n'
        '<meta charset="UTF-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1.0">\n'
        '<title>Sku patch notes</title>\n'
        '<link rel="stylesheet" href="../sku.css">\n'
        '</head>\n<body>\n'
        '<h1>Sku patch notes</h1>\n'
        '<p>Choose a language:</p>\n'
        '<ul class="versionlist">\n%s\n</ul>\n'
        '<p><a href="../index.html">Sku download page</a></p>\n'
        '</body>\n</html>\n') % picks
    write(os.path.join(OUT_ROOT, 'index.html'), root)
    written += 1

    print('wrote %d files under %s' % (written, OUT_ROOT))
    return 0


if __name__ == '__main__':
    sys.exit(main())
