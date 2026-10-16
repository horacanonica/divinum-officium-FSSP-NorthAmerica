#!/usr/bin/env python3
"""Compute transfers of impeded local I-class feasts for 2026 and 2027.

For every generated layer (diocese or site) and year, any of the layer's own I-class
entries that does not win on its date is moved to the next day that is free of a
I/II-class office and not already used.  Lines are written to Tabulae/Transfer/<easter>.txt
(month*100+day of Easter) and tagged with the layer's NAP- token, so they only affect that
layer and its descendants.  Impeded II-class feasts are NOT transferred (1960: only
I-class feasts are), they are listed in fssp/transfers_report.json.

Run after gen.py; idempotent (removes its own previous lines first).
"""
import datetime, json, os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
import napcal as n, render

YEARS = (2026, 2027)
FREE = ('III. classis', 'IV. classis', '')


def easter(y):
    a = y % 19; b, c = divmod(y, 100); d, e = divmod(b, 4)
    f = (b + 8) // 25; g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30; i, k = divmod(c, 4)
    l = (32 + 2 * e + 2 * i - h - k) % 7; m = (a + 11 * h + 22 * l) // 451
    mo = (h + l - 7 * m + 114) // 31; da = (h + l - 7 * m + 114) % 31 + 1
    return mo, da


def own_entries(kfile):
    out = []
    for l in open(os.path.join(n.TAB, 'Kalendaria', kfile + '.txt'), encoding='utf-8').read().splitlines():
        if l.startswith('#') or '=' not in l:
            continue
        p = l.split('=')
        out.append((p[0], p[1], p[2], p[3]))
    return out


def main():
    rows = n.read_data_txt()
    man = json.load(open(os.path.join(n.ROOT, 'fssp/generated_manifest.json')))
    # strip previous lines
    tdir = os.path.join(n.TAB, 'Transfer')
    for fn in os.listdir(tdir):
        fp = os.path.join(tdir, fn)
        if fn.endswith('.txt') and os.path.isfile(fp):
            t = open(fp, encoding='utf-8').read()
            if 'NAP-' in t:
                open(fp, 'w', encoding='utf-8').write(''.join(l for l in t.splitlines(True) if 'NAP-' not in l))
    out_lines = {}   # easter code -> [lines]
    report = {'transferred': [], 'ii_class_impeded_not_transferred': [], 'failed': []}
    for ver in ['Rubrics 1960 - FSSP'] + man['versions']:
        r = rows.get(ver)
        if not r or not r[1].startswith(('Dio', 'Site', 'FSSP')):
            continue
        token = 'NAP-fssp' if r[1] == 'FSSP' else r[2].split('|')[2]
        entries = own_entries(r[1])
        for y in YEARS:
            days = render.year(ver, y)
            used = set()
            ec = easter(y)
            code = '%d%02d' % ec
            for date, fil, label, rk in entries:
                d = days.get(date, {})
                want = {'1': 'I. classis', '2': 'II. classis', '3': 'III. classis'}[rk]
                if r[1] == 'FSSP':   # kalendar labels differ from the Officium titles here
                    key_ = {'02-22': 'Cathedra', '03-07': 'Aquino', '08-01': 'Vincula'}[date]
                    won = d.get('rank') == want and key_ in d.get('title', '')
                else:
                    won = d.get('rank') == want and d.get('title') == label
                if won:
                    continue
                if rk != '1':
                    report['ii_class_impeded_not_transferred'].append((ver, y, date, label, d.get('title'), d.get('rank')))
                    continue
                # find next free day
                dt = datetime.date(y, int(date[:2]), int(date[3:]))
                own_dates = {e[0] for e in entries}
                for k in range(1, 60):
                    nd = dt + datetime.timedelta(days=k)
                    key = '%02d-%02d' % (nd.month, nd.day)
                    if nd.year != y:
                        break
                    dd = days.get(key, {})
                    if key in used or key in own_dates:
                        continue
                    if dd.get('rank') in FREE and not dd.get('extra', '').startswith('Transfer'):
                        break
                else:
                    nd = None
                if nd is None or nd.year != y:
                    report['failed'].append((ver, y, date, label))
                    continue
                used.add(key)
                base_ent = fil.split('~')[0]
                resolved = n_resolve(ver, key, rows)
                tails = [t for t in resolved.split('~') if t and t != base_ent] if resolved else []
                # also keep the feast's own original tails except what is already the dest
                val = base_ent + ''.join('~' + t for t in tails)
                out_lines.setdefault(code, []).append('%s=%s;;%s' % (key, val, token))
                report['transferred'].append((ver, y, date, key, label, dd.get('title'), dd.get('rank')))
    for code, lines in out_lines.items():
        fp = os.path.join(tdir, code + '.txt')
        t = open(fp, encoding='utf-8').read() if os.path.exists(fp) else ''
        if t and not t.endswith('\n'):
            t += '\n'
        seen = []
        for l in lines:
            if l not in seen:
                seen.append(l)
        open(fp, 'w', encoding='utf-8').write(t + '\n'.join(seen) + '\n')
    json.dump(report, open(os.path.join(n.ROOT, 'fssp/transfers_report.json'), 'w'), indent=1, ensure_ascii=False)
    print('transferred', len(report['transferred']), 'II-impeded', len(report['ii_class_impeded_not_transferred']), 'failed', len(report['failed']))


def n_resolve(ver, key, rows):
    return n.resolve_entry(ver, key, rows)


if __name__ == '__main__':
    main()
