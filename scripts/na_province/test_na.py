#!/usr/bin/env python3
"""Tests for the FSSP North American Province calendars.

Needs the running web container (renders the real engine).  Run:
    python3 -I -m unittest scripts/na_province/test_na.py     (from the repo root)
or  python3 -I scripts/na_province/test_na.py [--update-golden]
"""
import json, os, sys, unittest
sys.path.insert(0, os.path.dirname(__file__))
import napcal as n, render

GOLDEN = os.path.join(n.ROOT, 'fssp/golden_usa_chain.json')
USA_CHAIN = ['Rubrics 1960 - 1960', 'Rubrics 1960 - FSSP', 'Rubrics 1960 - USA 1960', 'Rubrics 1960 - FSSP USA']
YEARS = (2026, 2027)
_cache = {}


def yr(v, y):
    if (v, y) not in _cache:
        _cache[(v, y)] = render.year(v, y)
    return _cache[(v, y)]


def ancestors(v, rows):
    out = []
    while v and v in rows:
        out.append(v)
        v = rows[v][4] if len(rows[v]) > 4 else ''
    return out


def canadian_versions(rows):
    return [v for v in rows if 'Rubrics 1960 - FSSP Canada' in ancestors(v, rows)]


class OpenQuestionMarker(unittest.TestCase):
    def test_confirmed_is_not_open(self):
        self.assertTrue(n.is_open({'note': 'CONFIRM the date'}))
        self.assertTrue(n.is_open({'status': 'pending'}))
        self.assertFalse(n.is_open({'note': 'CONFIRMED correct by the owner'}))
        self.assertFalse(n.is_open({'note': 'ANSWERED'}))


class UsaRegression(unittest.TestCase):
    """The FSSP / USA1960 / FSSP USA output must not change when local layers are added."""

    def test_usa_chain_matches_golden(self):
        gold = json.load(open(GOLDEN, encoding='utf-8'))
        for v in USA_CHAIN:
            for y in YEARS:
                cur = {d: [x['title'], x['rank'], x['extra']] for d, x in yr(v, y).items()}
                old = gold['%s|%d' % (v, y)]
                if y == 2026 and 'FSSP' in v:
                    # the one intended change: Chair of St. Peter (FSSP, I class) moves Feb 22 -> Feb 23, 2026
                    for d in ('02-22', '02-23'):
                        cur.pop(d); old.pop(d)
                self.assertEqual(cur, old, '%s %d changed' % (v, y))


class NoUsaInCanada(unittest.TestCase):
    USA_KAL = n.read_kalendar('USA1960')

    def test_canadian_chains_do_not_inherit_usa(self):
        rows = n.read_data_txt()
        cvs = canadian_versions(rows)
        self.assertTrue(len(cvs) >= 10)
        for v in cvs:
            anc = ancestors(v, rows)
            self.assertNotIn('Rubrics 1960 - FSSP USA', anc, v)
            self.assertNotIn('Rubrics 1960 - USA 1960', anc, v)
            self.assertFalse(any(rows[a][1] == 'USA1960' for a in anc), v)

    def test_no_usa_feast_in_any_canadian_calendar(self):
        rows = n.read_data_txt()
        banned_titles = ['Petri Claver', 'Isaaci Jogues', 'Isidori Agricolae', 'Cabrini', 'Seton',
                         'Neumann', 'Pro Pace']
        ca_kal_dates = {}
        for v in canadian_versions(rows):
            # entries a Canadian layer defines itself are allowed (except the USA texts)
            for a in ancestors(v, rows):
                if rows[a][1].startswith(('Dio', 'Site', 'CAN')):
                    for d, f in n.read_kalendar(rows[a][1]).items():
                        ca_kal_dates.setdefault(v, set()).add(d)
            for y in YEARS:
                days = yr(v, y)
                base = yr('Rubrics 1960 - FSSP', y)
                for d, x in days.items():
                    txt = x['title'] + ' ' + x['extra']
                    for b in banned_titles:
                        self.assertNotIn(b, txt, '%s %d %s shows USA feast' % (v, y, d))
                # explicit dates
                for d in ('01-04', '01-05', '01-22', '09-09', '11-13', '10-25'):
                    if d in ca_kal_dates.get(v, ()):
                        continue
                    self.assertEqual(days[d]['title'], base[d]['title'], '%s %d %s' % (v, y, d))
                # Sep 26: universal 1960 day, not the USA martyrs (Canada form is pending)
                if '09-26' not in ca_kal_dates.get(v, ()):
                    self.assertEqual(days['09-26']['title'], base['09-26']['title'], '%s %d 09-26' % (v, y))

    def test_every_usa1960_entry_absent_from_canada(self):
        rows = n.read_data_txt()
        for v in canadian_versions(rows):
            for a in ancestors(v, rows):
                self.assertNotEqual(rows[a][1], 'USA1960')
        # Dec 12 lives independently in CAN1960
        self.assertEqual(n.read_kalendar('CAN1960').get('12-12'), '12-12n')
        self.assertEqual(set(n.read_kalendar('CAN1960')), {'12-12'})

    def test_can1960_dec12_is_iii_class(self):
        d = yr('Rubrics 1960 - FSSP Canada', 2026)['12-12']
        self.assertEqual(d['rank'], 'III. classis', d)


class SitesRender(unittest.TestCase):
    def test_every_generated_version_renders_full_years_and_is_recognised(self):
        man = json.load(open(os.path.join(n.ROOT, 'fssp/generated_manifest.json')))
        rows = n.read_data_txt()
        dialog = open(os.path.join(n.ROOT, 'web/www/horas/horas.dialog'), encoding='utf-8').read()
        for v in man['versions']:
            self.assertIn(v, dialog, v + ' missing from horas.dialog [versions]')
            self.assertIn(v, rows)
            for y in YEARS:
                days = yr(v, y)
                self.assertEqual(len(days), 365, '%s %d' % (v, y))


class OrdoSpotChecks(unittest.TestCase):
    def rank(self, v, y, d):
        x = yr(v, y)[d]
        return x['title'], x['rank']

    def test_sacramento_legacy_chain(self):
        # sacramento-st-stephen is held back as an open question; the legacy calendar covers it
        v = 'Rubrics 1960 - Sacramento'
        self.assertEqual(self.rank(v, 2026, '12-12')[1], 'I. classis')
        self.assertEqual(self.rank(v, 2026, '03-17')[1], 'I. classis')

    def test_indianapolis(self):
        v = 'Rubrics 1960 - Archdiocese of Indianapolis'
        self.assertEqual(self.rank(v, 2026, '12-21')[1], 'I. classis')
        self.assertIn('Dedicationis', self.rank(v, 2026, '12-21')[0])
        t, r = self.rank(v, 2026, '12-22')
        self.assertEqual(r, 'II. classis')
        self.assertIn('Thomæ', t)

    def test_fort_wayne_dedication_dec9(self):
        v = 'Rubrics 1960 - Diocese of Fort Wayne-South Bend'
        t, r = self.rank(v, 2026, '12-09')
        self.assertIn('Dedicationis', t)
        self.assertEqual(r, 'I. classis')
        self.assertNotIn('Dedicationis', self.rank(v, 2026, '12-08')[0])

    def test_charles_borromeo_only_in_seminary(self):
        man = json.load(open(os.path.join(n.ROOT, 'fssp/generated_manifest.json')))
        for v in man['versions']:
            t, r = self.rank(v, 2026, '11-04')
            if 'Denton' in v:
                self.assertEqual(r, 'I. classis', v)
                self.assertIn('Caroli', t)
            else:
                self.assertNotEqual(r, 'I. classis', '%s has Nov 4 as I class' % v)

    def test_canada_sites_have_no_usa_feast_on_key_dates(self):
        rows = n.read_data_txt()
        for v in canadian_versions(rows):
            for d in ('01-04', '01-05', '09-09', '11-13'):
                t = yr(v, 2026)[d]['title']
                for b in ('Seton', 'Neumann', 'Claver', 'Cabrini'):
                    self.assertNotIn(b, t)

    def test_chair_of_peter_2026_transferred_to_feb_23(self):
        for v in ('Rubrics 1960 - FSSP', 'Rubrics 1960 - FSSP USA', 'Rubrics 1960 - FSSP Canada'):
            d = yr(v, 2026)
            self.assertIn('Cathedra', d['02-23']['title'], v)
            self.assertEqual(d['02-23']['rank'], 'I. classis')
            self.assertNotIn('Cathedra', d['02-22']['title'])
        self.assertIn('Cathedra', yr('Rubrics 1960 - FSSP', 2027)['02-22']['title'])

    def test_fssp_layer_items(self):
        k = n.read_kalendar('FSSP')
        self.assertEqual(set(k), {'02-22', '03-07', '08-01'})
        self.assertEqual(yr('Rubrics 1960 - FSSP', 2027)['02-22']['rank'], 'I. classis')
        self.assertEqual(yr('Rubrics 1960 - FSSP', 2026)['03-07']['rank'], 'II. classis')
        self.assertEqual(yr('Rubrics 1960 - FSSP', 2026)['08-01']['rank'], 'III. classis')


class LocalFeastsWin(unittest.TestCase):
    """Every I-class local entry wins on its date, or has been transferred (2026, 2027)."""

    def test_local_i_class_feasts(self):
        import check
        rows = n.read_data_txt()
        man = json.load(open(os.path.join(n.ROOT, 'fssp/generated_manifest.json')))
        tr = json.load(open(os.path.join(n.ROOT, 'fssp/transfers_report.json')))
        moved = {(v, y, d) for v, y, d, *_ in tr['transferred']}
        ii = {(v, y, d) for v, y, d, *_ in tr['ii_class_impeded_not_transferred']}
        ii |= {(v, y, d) for v, y, d, *_ in tr['failed']}   # no free day before year end; listed in the report
        for v in man['versions']:
            if not rows[v][1].startswith(('Dio', 'Site')):
                continue
            for y in YEARS:
                for b in check.check(v, y, rows):
                    if b['layer'] != v:
                        continue   # reported under the owning layer
                    k = (v, y, b['date'])
                    self.assertTrue(k in moved or k in ii, 'unexplained: %s' % (k,) + str(b))


if __name__ == '__main__':
    if '--update-golden' in sys.argv:
        gold = {}
        for v in USA_CHAIN:
            for y in YEARS:
                gold['%s|%d' % (v, y)] = {d: [x['title'], x['rank'], x['extra']] for d, x in render.year(v, y).items()}
        json.dump(gold, open(GOLDEN, 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
        print('golden written')
    else:
        unittest.main(argv=[sys.argv[0]] + [a for a in sys.argv[1:]])
