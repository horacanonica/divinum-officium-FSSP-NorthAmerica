#!/usr/bin/env python3
"""Render every generated version for given years and compare against its Kalendaria entries.

Prints, per version, entries that did NOT win on their date (impeded / displaced / wrong rank).
Usage: check.py 2026 2027 [version-substring]
"""
import json, os, sys, concurrent.futures as cf
sys.path.insert(0, os.path.dirname(__file__))
import napcal as n, render

RANKTXT = {'1': 'I. classis', '2': 'II. classis', '3': 'III. classis'}


def chain_entries(version, rows):
    """(date, label, rankdigit, layer) for the version's own and ancestors' generated layers."""
    out = []
    v = version
    while v and v in rows:
        r = rows[v]
        path = os.path.join(n.TAB, 'Kalendaria', r[1] + '.txt')
        if r[1].startswith(('Dio', 'Site')):
            for l in open(path, encoding='utf-8').read().splitlines():
                if l.startswith('#') or '=' not in l:
                    continue
                p = l.split('=')
                out.append((p[0], p[2], p[3], v))
        v = r[4] if len(r) > 4 else ''
    # most-derived layer wins per date (list is ordered most-derived first)
    seen, res = set(), []
    for e in out:
        if e[0] not in seen:
            seen.add(e[0]); res.append(e)
    return res


def check(version, year, rows):
    days = render.year(version, year)
    bad = []
    for date, label, rk, layer in chain_entries(version, rows):
        d = days.get(date, {})
        ok = d.get('rank') == RANKTXT[rk] and d.get('title') == label
        if not ok:
            bad.append({'date': date, 'label': label, 'want': RANKTXT[rk], 'got': d.get('title', '') + ' | ' + d.get('rank', ''), 'layer': layer})
    return bad


if __name__ == '__main__':
    years = [int(a) for a in sys.argv[1:] if a.isdigit()]
    pats = [a for a in sys.argv[1:] if not a.isdigit()]
    rows = n.read_data_txt()
    man = json.load(open(os.path.join(n.ROOT, 'fssp/generated_manifest.json')))
    vers = [v for v in man['versions'] if not pats or any(p in v for p in pats)]
    res = {}
    with cf.ThreadPoolExecutor(4) as ex:
        futs = {(v, y): ex.submit(check, v, y, rows) for v in vers for y in years}
        for (v, y), f in futs.items():
            res.setdefault(v, {})[y] = f.result()
    json.dump(res, open(os.path.join(n.ROOT, 'fssp/check_result.json'), 'w'), indent=1, ensure_ascii=False)
    for v, ys in res.items():
        for y, bad in ys.items():
            for b in bad:
                print(y, v, b['date'], '|', b['label'][:40], '| want', b['want'], '| got', b['got'][:60], '| layer' if b['layer'] != v else '')
