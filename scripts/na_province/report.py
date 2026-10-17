#!/usr/bin/env python3
"""Write docs/LOCAL_PROPERS_BY_LOCATION.md.

For every layer (FSSP, USA, Canada, each diocese and parish/site, and the legacy
hand-written calendars) list each local feast: its class, whether it is a proper
office or an elevation of a general-calendar office, what it displaces, and what the
Divinum Officium engine does with it in 2026 and 2027 (occurrence, transfer, and
first/second Vespers = concurrence).  Everything about collisions is read from the
running engine, not inferred.

Usage: report.py            (needs the web container; takes a few minutes)
"""
import concurrent.futures as cf, datetime, html, json, os, re, subprocess, sys, urllib.parse
sys.path.insert(0, os.path.dirname(__file__))
import napcal as n, render

YEARS = (2026, 2027)
CLASS = {'1': 'I', '2': 'II', '3': 'III', '4': 'IV'}
SANCTI = os.path.join(n.ROOT, 'web/www/horas/Latin/Sancti')
OUT = os.path.join(n.ROOT, 'docs/LOCAL_PROPERS_BY_LOCATION.md')

_days = {}
def days(ver, y):
    k = (ver, y)
    if k not in _days:
        _days[k] = render.year(ver, y)
    return _days[k]


def sancti(f):
    p = os.path.join(SANCTI, f + '.txt')
    return open(p, encoding='utf-8').read() if os.path.exists(p) else ''


def office_title(f, depth=0):
    t = sancti(f)
    m = re.search(r'\[Officium\]\n(.+)', t)
    if m:
        return m.group(1).strip()
    m = re.search(r'\[Rank\](?: \(rubrica 196\))?\n([^;\n]+);;', t)
    if m:
        return m.group(1).strip()
    m = re.match(r'@Sancti/([^\n:]+)', t)
    if m and depth < 4:
        return office_title(m.group(1), depth + 1)
    return f


def base_rank_text(f, depth=0):
    t = sancti(f)
    m = re.search(r'\[Rank\] \(rubrica 196\)\n[^;\n]+;;([^;\n]+);;', t) or re.search(r'\[Rank\]\n[^;\n]+;;([^;\n]+);;', t)
    if m:
        return m.group(1).strip()
    m = re.match(r'@Sancti/([^\n:]+)', t)
    if m and depth < 4:
        return base_rank_text(m.group(1), depth + 1)
    return ''


def kind_of(date, f):
    """('Elevated'|'Proper'|'Rank only', detail) for a Kalendaria file reference."""
    t = sancti(f)
    m = re.match(r'@Sancti/([^\n:]+)', t)
    if m:
        base = m.group(1)
        return 'Elevated', 'general office %s (%s) raised' % (base, base_rank_text(base) or 'rank not stated')
    if f == date:
        return 'Rank only', 'general office %s (%s), class changed in the calendar' % (f, base_rank_text(f) or '')
    rule = re.search(r'\[Rule\]\n(.*?)(?:\n\[|\Z)', t, re.S)
    commune = ''
    if rule:
        mm = re.search(r'ex (C\d+\w*)', rule.group(1))
        if mm:
            commune = mm.group(1)
    return 'Proper', 'own office file %s%s' % (f, ', texts from Commune %s' % commune if commune else '')


def own_entries(kfile):
    out = []
    path = os.path.join(n.TAB, 'Kalendaria', kfile + '.txt')
    if not os.path.exists(path):
        return out
    for l in open(path, encoding='utf-8').read().splitlines():
        if l.startswith('#') or '=' not in l or l.startswith('*'):
            continue
        p = l.split('=')
        if len(p) < 4 or not re.match(r'\d\d-\d\d$', p[0]):
            continue
        files = p[1].split('~')
        out.append({'date': p[0], 'file': files[0], 'tails': files[1:], 'label': p[2], 'cls': CLASS.get(p[3], p[3])})
    return out


def vespers(ver, y, date):
    q = urllib.parse.urlencode({'date': date.strftime('%m-%d-%Y'), 'version': ver, 'lang2': 'English', 'command': 'prayVesperae'})
    out = subprocess.run(['docker', 'exec', render.CONTAINER, 'curl', '-s', 'http://localhost:8080/cgi-bin/horas/officium.pl?' + q],
                         capture_output=True, text=True).stdout
    txt = html.unescape(re.sub(r'<[^>]+>', '\n', out))
    L = [l.strip() for l in txt.splitlines() if l.strip()]
    for i, l in enumerate(L):
        if '~' in l and 'classis' in l:
            seg = []
            for x in L[i:i + 8]:
                if x.startswith(('Divinum Officium', 'Rubrics 1960', 'Compare')):
                    break
                seg.append(x)
                if x.startswith('Vespera') or x.startswith('A capitulo'):
                    break
            return ' / '.join(seg)
    return '(not parsed)'


def md_date(mmdd):
    return datetime.date(2000, int(mmdd[:2]), int(mmdd[3:])).strftime('%b %-d')


def entry_block(ver, parent, e, tr, y_vespers):
    lines = []
    kind, detail = kind_of(e['date'], e['file'])
    lines.append('- **%s: %s** — class **%s** — %s (%s)' % (md_date(e['date']), e['label'], e['cls'], kind, detail))
    if e['tails']:
        names = []
        for t in e['tails']:
            tt = t if t != e['date'] else e['date']
            names.append('%s' % office_title(tt))
        lines.append('  - Commemorated with it (Lauds): ' + '; '.join(names))
    for y in YEARS:
        d = days(ver, y).get(e['date'], {})
        p = days(parent, y).get(e['date'], {}) if parent else {}
        won = d.get('title') == e['label'] or d.get('rank', '').startswith(e['cls'] + '.')
        won = d.get('title') == e['label']
        wd = datetime.date(y, int(e['date'][:2]), int(e['date'][3:])).strftime('%a')
        if won:
            if p.get('title') == d.get('title') or not p:
                note = 'office is raised in place (before: %s)' % (p.get('rank') or '—')
            else:
                shown = d.get('extra') or 'nothing'
                note = 'displaces **%s** (%s); commemorations shown: %s' % (p.get('title'), p.get('rank'), shown)
                pt = p.get('title', '')
                if pt and pt in d.get('extra', ''):
                    note += ' → displaced office is **commemorated**'
                else:
                    elsewhere = [k for k, v in days(ver, y).items() if v.get('title') == pt and k != e['date']] if p.get('rank', '').startswith(('I.', 'II.')) else []
                    if elsewhere:
                        note += ' → displaced office **moves to %s**' % ', '.join(md_date(k) for k in sorted(elsewhere))
                    elif p.get('rank', '').startswith(('I.', 'II.')):
                        note += ' → displaced %s office is **omitted this year** (only I class feasts are transferred)' % p.get('rank')
                    else:
                        note += ' → displaced office is omitted'
            lines.append('  - %d (%s): wins. %s' % (y, wd, note))
        else:
            fate = [t for t in tr['transferred'] if t[0] == ver and t[1] == y and t[2] == e['date']]
            imp = [t for t in tr['ii_class_impeded_not_transferred'] if t[0] == ver and t[1] == y and t[2] == e['date']]
            fail = [t for t in tr['failed'] if t[0] == ver and t[1] == y and t[2] == e['date']]
            if fate:
                what = 'impeded by **%s** (%s) → **transferred to %s**' % (d.get('title'), d.get('rank'), md_date(fate[0][3]))
            elif imp:
                what = 'impeded by **%s** (%s) → **not transferred** (II class); shown only as a commemoration if listed: %s' % (d.get('title'), d.get('rank'), d.get('extra') or 'none')
            elif fail:
                what = 'impeded by **%s** and **no free day found before year end**' % d.get('title')
            else:
                what = 'not shown: day is **%s** (%s); commemorations: %s' % (d.get('title'), d.get('rank'), d.get('extra') or 'none')
            lines.append('  - %d (%s): %s' % (y, wd, what))
    for y in YEARS:
        dd = datetime.date(y, int(e['date'][:2]), int(e['date'][3:]))
        eve = y_vespers[(ver, y, e['date'], 'eve')]
        day = y_vespers[(ver, y, e['date'], 'day')]
        lines.append('  - Concurrence %d — I Vespers (eve, %s): %s' % (y, (dd - datetime.timedelta(1)).strftime('%b %-d'), eve))
        lines.append('  - Concurrence %d — II Vespers (%s): %s' % (y, dd.strftime('%b %-d'), day))
    return lines


RULES = '''## How to read this document

Each entry shows: **date — name — class** (I, II or III as set in the calendar), then:

- **Proper** = an office that is not in the general calendar for that date (own texts, or built from a Common).
- **Elevated** = a general-calendar office that is kept but raised to a higher class here.
- **Rank only** = the general office on that date with its class changed in the calendar.
- *Commemorated with it* = the `~` tail in the Kalendaria line: that office is commemorated at Lauds.
- For 2026 and 2027, what the Divinum Officium engine does on that date: wins, displaces, or is displaced.
- Concurrence lines quote the engine's own header for First Vespers (the evening before) and Second Vespers (the evening of the feast day).

### Rules the engine applies (Rubrics of 1960, as implemented in this fork)

1. **Layers add up.** A parish inherits its diocese, which inherits FSSP USA or FSSP Canada, which inherits the FSSP proper, which inherits the 1960 calendar. A lower layer overrides a higher layer on the same date.
2. **Occurrence (two offices on one day).** The office of higher class is said. The other is *commemorated* if the day's rubrics allow it (the Commemorations shown in the entry), otherwise *omitted*. Sundays of Advent, Lent, Passiontide and Easter, and the great privileged days (Ash Wednesday, Holy Week, the Easter and Pentecost octave days), exclude everything.
3. **Transfer.** A local **I class** feast that is impeded is moved to the next day that has no I or II class office and is not used by another local feast. These moves are written to `Tabulae/Transfer/<Easter code>.txt` by `scripts/na_province/transfers.py` for 2026 and 2027 only. A **II class** local feast that is impeded is not transferred. It is listed in `fssp/transfers_report.json`.
4. **Concurrence (Vespers meeting).** The engine decides each evening which day owns Vespers and which is commemorated. The header quoted in each entry reads, for example, "Vespera de præcedenti; commemoratio de sequenti" (Vespers of the day just ending, with the next day commemorated) or "Vespera de sequenti; commemoratio de præcedenti" (Vespers of tomorrow's feast, with today commemorated). Where the engine shows no commemoration line, none is made.
5. **Dedication anniversaries** of a cathedral church are I class in that diocese; the saint of the day is commemorated at Lauds (the `~` tail).
6. **Years beyond 2027.** Collision outcomes after 2027 have not been computed. Re-run `transfers.py` and this report when the window moves.

The outcomes are read from the running engine, so they are correct for the files in this repository. Whether the engine matches the printed rubrics in every edge case is a separate question for the Latin and rubrical review.
'''


def main():
    rows = n.read_data_txt()
    man = json.load(open(os.path.join(n.ROOT, 'fssp/generated_manifest.json')))
    gen = json.load(open(os.path.join(n.ROOT, 'fssp/generation_report.json')))
    tr = json.load(open(os.path.join(n.ROOT, 'fssp/transfers_report.json')))
    yaml_data = n.load_yaml()
    gen_versions = list(man['versions'])
    legacy_order = ['Sacramento', 'Guadalajara', 'Chesapeake', 'Richmond', 'Nashua', 'Arlington', 'Scranton',
                    'Baltimore', 'Maple Hill', 'OLG Seminary', 'Quincy', 'Niagara']
    legacy = ['Rubrics 1960 - ' + x for x in legacy_order if 'Rubrics 1960 - ' + x in rows]

    layers = {}   # version -> dict(entries, parent)
    def add(ver):
        r = rows[ver]
        layers[ver] = {'entries': own_entries(r[1]), 'parent': r[4] if len(r) > 4 else '', 'kfile': r[1]}
    for v in ['Rubrics 1960 - FSSP', 'Rubrics 1960 - FSSP USA', 'Rubrics 1960 - FSSP Canada'] + gen_versions + legacy:
        if v in rows:
            add(v)

    # Vespers for all entries (parallel)
    jobs = []
    for v, L in layers.items():
        for e in L['entries']:
            for y in YEARS:
                d = datetime.date(y, int(e['date'][:2]), int(e['date'][3:]))
                jobs.append((v, y, e['date'], 'eve', d - datetime.timedelta(1)))
                jobs.append((v, y, e['date'], 'day', d))
    vesp = {}
    print('vespers requests', len(jobs), flush=True)
    with cf.ThreadPoolExecutor(6) as ex:
        futs = {j[:4]: ex.submit(vespers, j[0], j[1], j[4]) for j in jobs}
        vesp = {k: f.result() for k, f in futs.items()}
    # warm the year renders in parallel
    pairs = {(v, y) for v, L in layers.items() if L['entries'] for y in YEARS}
    pairs |= {(L['parent'], y) for v, L in layers.items() if L['entries'] and L['parent'] for y in YEARS}
    with cf.ThreadPoolExecutor(4) as ex:
        list(ex.map(lambda k: days(*k), sorted(pairs)))

    def section(ver, title, note=''):
        L = layers[ver]
        out = ['#### %s' % title]
        if note:
            out.append(note)
        if not L['entries']:
            out.append('- No local feasts of its own (inherits everything above).')
        for e in L['entries']:
            out += entry_block(ver, L['parent'], e, tr, vesp)
        return out

    def tags_for(ver):
        # generation_report tags: [owner id, date, title, reason]
        return gen.get('tags', [])

    md = ['# FSSP North American Province — local propers by location', '',
          'Generated by `scripts/na_province/report.py` from the Kalendaria files and the running engine. '
          'Do not edit by hand: change `fssp/na_province.yaml` (or the legacy Kalendaria) and regenerate.', '',
          RULES, '']

    md += ['## 1. FSSP (all FSSP calendars)', '']
    md += section('Rubrics 1960 - FSSP', 'FSSP proper (Fraternity-wide)')
    md += ['', '## 2. FSSP USA (all United States calendars)', '']
    md += section('Rubrics 1960 - FSSP USA', 'USA supplement')
    md += ['', '## 3. FSSP Canada (all Canadian calendars)', '']
    md += section('Rubrics 1960 - FSSP Canada', 'Canada supplement',
                  'Placeholder: only Our Lady of Guadalupe (Dec 12, III class) is set. The rest of the Canadian proper is pending (`CAN1960`).')

    tagmap = {}
    for t in gen.get('tags', []):
        tagmap.setdefault(t[0], []).append(t)

    ids = {'Rubrics 1960 - ' + n.ascii_label(x['name']): x for x in yaml_data['dioceses']}
    sites_by_ver = {}
    for s in yaml_data['sites']:
        v = 'Rubrics 1960 - ' + n.ascii_label(s['name']) + ' ' + n.ascii_label(s['city'].replace(',', ''))
        sites_by_ver[v] = s
    for country, head in (('US', '## 4. United States — dioceses and parishes'), ('CA', '## 5. Canada — dioceses and parishes')):
        md += ['', head, '']
        for dv in [v for v in gen_versions if v in ids and ids[v]['country'] == country]:
            dio = ids[dv]
            md += ['### %s' % dio['name'], '']
            md += section(dv, 'Diocese-level propers')
            for t in tagmap.get(dio['id'], []):
                md.append('- *No calendar entry needed:* %s on %s — %s.' % (t[2], md_date(t[1]) if re.match(r'\d\d-\d\d$', str(t[1])) else t[1], t[3]))
            for sv in [v for v in gen_versions if v in sites_by_ver and sites_by_ver[v]['diocese'] == dio['id']]:
                s = sites_by_ver[sv]
                md += ['', '#### Parish / site: %s, %s' % (s['name'], s['city'])]
                sub = section(sv, 'Parish-level propers (inherits the diocese above)')
                md += sub[1:]
                for t in tagmap.get(s['id'], []):
                    md.append('- *No calendar entry needed:* %s on %s — %s.' % (t[2], md_date(t[1]) if re.match(r'\d\d-\d\d$', str(t[1])) else t[1], t[3]))
            md.append('')

    md += ['', '## 6. Legacy hand-written calendars (kept unchanged)', '']
    for v in legacy:
        md += ['### %s' % v.replace('Rubrics 1960 - ', ''), '']
        md += section(v, 'Propers (chain: %s)' % ' → '.join(x.replace('Rubrics 1960 - ', '') for x in _chain(rows, v)))
        md.append('')

    md += ['', '## 7. Not published yet (open questions)', '']
    for k, why in sorted(gen.get('hidden_dioceses', {}).items()):
        md.append('- Diocese **%s** — blocked by: %s' % (k, ', '.join(why)))
    for k, why in sorted(gen.get('hidden_sites', {}).items()):
        md.append('- Site **%s** — %s' % (k, why if isinstance(why, str) else ', '.join(why)))
    md.append('')
    md.append('See `docs/ai/GROK_HANDOFF.md` for the questions.')
    open(OUT, 'w', encoding='utf-8').write('\n'.join(md) + '\n')
    print('wrote', OUT, len(md), 'lines')


def _chain(rows, v):
    out = []
    while v in rows and v not in out:
        out.append(v)
        v = rows[v][4] if len(rows[v]) > 4 else ''
    return out


if __name__ == '__main__':
    main()
