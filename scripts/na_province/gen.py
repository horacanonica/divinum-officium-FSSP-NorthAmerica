#!/usr/bin/env python3
"""Generate FSSP North American Province calendars from fssp/na_province.yaml.

Writes (all tracked in fssp/generated_manifest.txt so reruns are clean):
  web/www/Tabulae/Kalendaria/{CAN1960,Dio*,Site*}.txt
  web/www/horas/Latin/Sancti/<MM-DD><nXX>.txt   (rank overrides / commons offices)
  web/www/horas/Latin/Tempora/Epi1-0nhf.txt     (Holy Family as local I class)
  rows in Tabulae/data.txt, Tabulae/Tempora/Generale.txt, horas/horas.dialog [versions]
Open questions (CONFIRM / pending) are never generated; see OPEN_QUESTIONS.md.
"""
import os, re, subprocess, sys, json
sys.path.insert(0, os.path.dirname(__file__))
import napcal as n

R = n.ROOT
KAL = os.path.join(n.TAB, 'Kalendaria')
SANC = n.SANCTI
TEMP = os.path.join(R, 'web/www/horas/Latin/Tempora')
MANIFEST = os.path.join(R, 'fssp/generated_manifest.json')
CONTAINER = 'divinum-officium-fssp-northamerica-web-1'
DUMP = os.path.join(os.path.dirname(__file__), 'dump.pl')

RANKS = {'I': ('Duplex I classis', 6), 'II': ('Duplex II classis', 5), 'III': ('Duplex', 3)}
KALRANK = {'I': 1, 'II': 2, 'III': 3}

# Token of the base entry that is the saint being elevated, where it is not the first one.
TOKEN_OVERRIDE = {('11-13', 'US'): '11-13', ('06-28', 'CA'): '06-28', ('06-28', 'US'): '06-28'}
# Genitive/accusative forms substituted for "N." in commune orations (checked in registry).
NAMES = {'S. Theodoræ Guérin Virginis': 'Theodóræ', 'S. Columbæ Abbatis': 'Columbæ',
         'S. Damiáni de Molokai Confessoris': 'Damiáni', 'S. Gerárdi Majella Confessoris': 'Gerárdi'}
COMMUNE = {'Common of Feasts of the BVM': 'C11', 'Common of a Virgin not a Martyr': 'C6a',
           'Common of a Confessor not a Bishop': 'C5',
           'Common of a Confessor not a Bishop (Abbot)': 'C5b', 'Common of a Virgin Martyr': 'C6'}
# Latin office titles for commons-built feasts (labels only; no liturgical text).
COMMONS_TITLE = {
    ('09-04', 'los-angeles'): 'Beatæ Mariæ Virginis Reginæ Angelorum',
    ('10-03', 'indianapolis'): 'S. Theodoræ Guérin Virginis',
    ('06-09', 'youngstown'): 'S. Columbæ Abbatis',
    ('06-27', 'rapid-city'): 'Beatæ Mariæ Virginis de Perpetuo Succursu',
    ('10-16', 'calgary'): 'S. Gerárdi Majella Confessoris',
    ('05-13', 'pequannock-ol-fatima'): 'Beatæ Mariæ Virginis a Rosario de Fatima',
    ('05-10', 'edmond-st-damien'): 'S. Damiáni de Molokai Confessoris',
}
# Sites whose data contradicts the repo; treated as open questions (see OPEN_QUESTIONS.md)
DATA_ERRORS = {'post-falls-st-joan-of-arc': 'St. Joan of Arc has no proper in the 1962 base (05-30 is St. Felix I); "propers: base" is wrong'}
FSSP_TOKEN = 'NAP-fssp'   # transfer-table token shared by every calendar that stacks on FSSP
DED_TITLE = 'In Anniversario Dedicationis Ecclesiæ Cathedralis'

_dump_cache = {}


def engine_dump(version, token):
    key = (version, token)
    if key in _dump_cache:
        return _dump_cache[key]
    subprocess.run(['docker', 'cp', DUMP, CONTAINER + ':/tmp/dump.pl'], check=True, capture_output=True)
    out = subprocess.run(['docker', 'exec', '-w', '/var/www/web/cgi-bin/horas', CONTAINER, 'perl', '-e',
                          'do "/tmp/dump.pl"; print $@ if $@', version, 'Sancti/%s.txt' % token],
                         check=True, capture_output=True, text=True).stdout
    info = {}
    for l in out.splitlines():
        if l.startswith('SECTIONS: '):
            info['sections'] = l[10:].split(',')
        elif ': ' in l or l.endswith(':'):
            k, _, v = l.partition(':')
            info[k] = v.strip()
    rk = info.get('Rank', '').replace('\\n', '').split(';;')
    info['rank_title'] = rk[0] if rk else ''
    info['rank_num'] = float(rk[2]) if len(rk) > 2 and rk[2] else 0.0
    info['commune'] = rk[3].strip() if len(rk) > 3 else ''
    info['rule'] = info.get('Rule', '').split('\\n')
    info['rule'] = [x for x in info['rule'] if x.strip()]
    _dump_cache[key] = info
    return info


class Gen:
    def __init__(self):
        self.d = n.load_yaml()
        self.rows = n.read_data_txt()
        self.files = {}      # relpath -> content (written at end)
        self.cals = {}       # version -> {date: value}
        self.newrows = []    # data.txt lines
        self.versions = []   # visible, ordered
        self.tempora = []    # Generale.txt lines
        self.sancti_names = {}
        self.report = {'tags': [], 'collisions': [], 'elevated': [], 'holy_family': []}
        self.tokens = {}

    # ---- chain helpers
    def resolve(self, version, mmdd):
        v = version
        while v:
            if v in self.cals and mmdd in self.cals[v]:
                return self.cals[v][mmdd]
            r = self.rows.get(v)
            if not r:
                return ''
            if v not in self.cals:
                k = self.cals_by_file[r[1]] if r[1] in self.cals_by_file else n.read_kalendar(r[1])
                if mmdd in k:
                    return k[mmdd]
            v = r[4] if len(r) > 4 else ''
        return ''

    cals_by_file = {}

    # ---- Sancti file registry
    def sfile(self, name, content):
        path = 'web/www/horas/Latin/Sancti/%s.txt' % name
        if path in self.files and self.files[path] != content:
            raise RuntimeError('conflicting content for ' + name)
        self.files[path] = content
        return name

    def ded_file(self, date):
        c = ('[Officium]\n%s\n\n[Rank]\n%s;;Duplex I classis;;6;;ex C8\n\n[Rule]\nex C8;\n9 lectiones\nFestum Domini\n'
             % (DED_TITLE, DED_TITLE))
        return self.sfile(date + 'ndc', c)

    def commons_file(self, date, site_or_dio, f):
        title = COMMONS_TITLE[(date, site_or_dio)]
        cm = COMMUNE[f['commune']]
        rk = f['rank']
        rn, rnum = RANKS[rk]
        rule = ['ex %s;' % cm] if rk == 'I' else ['vide %s;' % cm]
        if rk == 'I':
            rule.append('9 lectiones')
        if cm == 'C11' and rk in ('I', 'II'):
            rule += ['Psalmi Dominica', 'Ipsa Virgo Virginum', 'Doxology=Nat'] if rk == 'I' else []
        body = '[Officium]\n%s\n\n[Rank]\n%s;;%s;;%d;;%s %s\n\n[Rule]\n%s\n' % (
            title, title, rn, rnum, 'ex' if rk == 'I' else 'vide', cm, '\n'.join(rule))
        if title in NAMES:
            body += '\n[Name]\n%s\n' % NAMES[title]
        sfx = 'nc' + re.sub(r'[^a-z]', '', site_or_dio)[:6]
        return self.sfile(date + sfx, body), title

    def legend_lessons(self, tok):
        """Base saint has only a one-lesson legend ([Lectio93]): reuse it, split in three, as Nocturn II."""
        raw = open(os.path.join(SANC, tok + '.txt'), encoding='utf-8').read()
        m = re.search(r'\[Lectio93\]\n(.*?)(?=\n\[|\Z)', raw, re.S)
        text = re.sub(r'&teDeum', '', m.group(1)).strip()
        sents = re.split(r'(?<=[.!?]) ', text)
        total = sum(len(x) for x in sents)
        parts, cur = [[], [], []], 0
        acc = 0
        for sn in sents:
            idx = min(2, int(3 * acc / total))
            parts[idx].append(sn)
            acc += len(sn)
        out = ''
        for i, ps in enumerate(parts):
            out += '\n[Lectio%d]\n%s\n' % (4 + i, ' '.join(ps))
        return out

    def elev_file(self, tok, rk, base_ver, date):
        info = engine_dump(base_ver, tok)
        rn, rnum = RANKS[rk]
        title = info.get('Officium') or info['rank_title']
        if not title:
            raise RuntimeError('no title for ' + tok)
        com = info['commune']
        rule = list(info['rule'])
        if rk == 'I':
            com = re.sub(r'^vide ', 'ex ', com)
            rule = [re.sub(r'^vide ', 'ex ', rule[0])] + rule[1:] if rule else []
            if not any('lectiones' in x for x in rule):
                rule.append('9 lectiones')
        legend = ''
        if rk == 'I' and 'Lectio4' not in info.get('sections', []) and 'Lectio93' in info.get('sections', []):
            legend = self.legend_lessons(tok)
        body = '@Sancti/%s\n\n[Officium]\n%s\n\n[Rank]\n%s;;%s;;%d;;%s\n\n[Rule]\n%s\n' % (
            tok, title, title, rn, rnum, com, '\n'.join(rule)) + legend
        name = '%sn%s%s' % (tok if re.fullmatch(r'\d\d-\d\d', tok) else tok, 'l' + str(KALRANK[rk]), '')
        # make filename unique per token: MM-DD + n + l1/l2 (+ original suffix)
        m = re.fullmatch(r'(\d\d-\d\d)(.*)', tok)
        name = '%sn%s%s' % (m.group(1), 'l' + str(KALRANK[rk]), m.group(2))
        return self.sfile(name, body), title

    # ---- layer building
    def layer(self, version, label_file, base_ver, country, items, token):
        """items: list of dict(date,title,rank,kind,propers,commune,owner)"""
        cal = {}
        self.cals[version] = cal
        country_base = n.CA_BASE if country == 'CA' else n.US_BASE
        transferred_away = set()
        for it in items:
            if it.get('transferred_from_date'):
                transferred_away.add(it['transferred_from_date'])
        lines = []
        for it in items:
            date = it['date']
            rank = it['rank']
            force_tag = rank == 'as_on_feast'
            if force_tag:
                rank = 'I'
            if date.startswith('movable'):
                self.handle_movable(it, token)
                continue
            if it['kind'] == 'dedication_cathedral':
                f = self.ded_file(date)
                title = DED_TITLE
                saint = None
            elif it.get('propers') == 'commons':
                f, title = self.commons_file(date, it['owner'], it)
                saint = None
            elif it.get('use_file'):
                f = it['use_file']
                saint = it.get('use_saint')
                if it.get('use_title'):
                    title = it['use_title']
                else:
                    _i = engine_dump(n.US_BASE, f); title = _i.get('Officium') or _i['rank_title']
            else:
                # base elevation
                if it.get('special_dec12') and rank == 'I':
                    f, title, saint = '12-12s', 'Beatæ Mariæ Virginis de Guadalupe', '12-12n'
                    self.files  # file exists already
                else:
                    cbent = self.resolve(country_base, it.get('base_date', date))
                    toks = cbent.split('~') if cbent else []
                    if it.get('src_token'):
                        saint = it['src_token']
                    elif not toks:
                        raise RuntimeError('no base office for %s %s' % (it['owner'], date))
                    else:
                        saint = TOKEN_OVERRIDE.get((date, country), toks[0])
                    info = engine_dump(country_base, saint)
                    need = RANKS[rank][1]
                    chain_ent = self.resolve(base_ver, date)
                    if it.get('base_date'):
                        # office moved from another date: reuse the base file as is (no new file)
                        f, title = saint, (info.get('Officium') or info['rank_title'])
                        chain_ent = self.resolve(base_ver, date)
                        tails = [t for t in (chain_ent.split('~') if chain_ent else []) if t != saint]
                        cal[date] = f + ''.join('~' + t for t in tails)
                        lines.append('%s=%s=%s=%d=' % (date, cal[date], title, KALRANK[rank]))
                        continue
                    if force_tag and info['rank_num'] < need:
                        raise RuntimeError('as_on_feast but base is not I class: %s %s' % (it['owner'], date))
                    if info['rank_num'] >= need and chain_ent.split('~')[0] in (saint, ''):
                        self.report['tags'].append((it['owner'], date, it['title'], 'already %s class' % rank))
                        continue
                    if info['rank_num'] >= need:
                        # saint already high enough but something else sits on top in the chain
                        self.report['tags'].append((it['owner'], date, it['title'], 'already %s class (chain differs)' % rank))
                    f, title = self.elev_file(saint, rank, country_base, date)
                    self.report['elevated'].append((it['owner'], date, it['title'], f))
            # tails: whatever the chain currently has on that date, minus the saint itself & transferred ones
            chain_ent = self.resolve(base_ver, date)
            tails = [t for t in (chain_ent.split('~') if chain_ent else [])
                     if t != saint and t not in (it.get('skip_tails') or [])]
            if it.get('no_tails'):
                tails = []
            if chain_ent and not saint:
                first = chain_ent.split('~')[0]
                if re.search(r'n(dc|l\d|c)', first):
                    self.report['collisions'].append((it['owner'], date, title, first))
            if saint and chain_ent.split('~')[0] and re.search(r'ndc|nc[a-z]*$', chain_ent.split('~')[0]):
                self.report['collisions'].append((it['owner'], date, title, chain_ent.split('~')[0]))
            val = f + ''.join('~' + t for t in tails if t != f)
            cal[date] = val
            lines.append('%s=%s=%s=%d=' % (date, val, title, KALRANK[rank]))
        return lines

    def handle_movable(self, it, token):
        d = it['date']
        if d == 'movable:sunday-after-epiphany':
            self.sfile_tempora()
            self.tempora.append('Tempora/Epi1-0=Tempora/Epi1-0nhf;;%s' % token)
            self.report['holy_family'].append((it['owner'], token))
        else:
            self.report['tags'].append((it['owner'], d, it['title'], 'movable, already I class'))

    def sfile_tempora(self):
        c = ('@Tempora/Epi1-0\n\n[Rank]\n;;Duplex I classis;;6.01\n')
        self.files['web/www/horas/Latin/Tempora/Epi1-0nhf.txt'] = c

    def run(self):
        d = self.d
        # open-question filtering (strict: hide any location with an open item)
        hidden_d, hidden_s = {}, {}
        for x in d['dioceses']:
            why = [str(f['date']) for f in x['feasts'] if n.is_open(f)]
            if 'CONFIRM' in str(x.get('note', '')) or any('CONFIRM' in str(b) for b in x.get('bishop_commemorations', [])):
                why.append('diocese note')
            if why:
                hidden_d[x['id']] = why
        for s in d['sites']:
            if s['id'] in DATA_ERRORS:
                hidden_s[s['id']] = DATA_ERRORS[s['id']]
            elif n.is_open(s):
                hidden_s[s['id']] = 'own open item'
            elif s['diocese'] in hidden_d:
                hidden_s[s['id']] = 'diocese %s hidden' % s['diocese']
        self.hidden_d, self.hidden_s = hidden_d, hidden_s
        # tokens (transfer-regex markers) – none a substring of another
        # CAN base
        self.cals_by_file['CAN1960'] = {'12-12': '12-12n'}
        self.newrows.append('Rubrics 1960 - FSSP Canada,CAN1960,1960,1960,Rubrics 1960 - FSSP')
        self.rows['Rubrics 1960 - FSSP Canada'] = ['Rubrics 1960 - FSSP Canada', 'CAN1960', '1960', '1960', 'Rubrics 1960 - FSSP']
        self.files['web/www/Tabulae/Kalendaria/CAN1960.txt'] = (
            '#PENDING — Officia Propria Canadensis (1962) not yet supplied. See docs/ai/CANADA_PROPERS.md\n'
            '#Only item: Dec 12 Our Lady of Guadalupe, III class (CAN & USA; CDW decree 25 Mar 1999), same texts as USA.\n'
            '12-12=12-12n=Beatae Mariae Virginis de Guadalupe=3=\n')
        dio_ver = {}
        for x in d['dioceses']:
            if x['id'] in hidden_d:
                continue
            ctry = x['country']
            ver = 'Rubrics 1960 - ' + n.ascii_label(x['name'])
            tok = 'NAP-dio-' + x['id']
            base = n.CA_BASE if ctry == 'CA' else n.US_BASE
            items = []
            for f in x['feasts']:
                it = dict(f); it['owner'] = x['id']
                it.setdefault('title', f['title'])
                if f['date'] == '12-12' and f.get('propers') == 'base' and f['rank'] == 'I':
                    it['special_dec12'] = True
                if x['id'] == 'indianapolis' and f['date'] == '12-22':
                    it['src_token'] = '12-21'
                    it['base_date'] = '12-21'
                    it['no_tails'] = False
                if x['id'] == 'kansas-city-ks' and f['date'] == '11-17':
                    it['use_file'] = '11-17mh'
                    it['use_saint'] = '11-17mh'
                    it.pop('propers', None)
                    it['kind'] = 'other'
                items.append(it)
            # Indianapolis: Thomas moves off Dec 21 – don't commemorate him there
            for it in items:
                if x['id'] == 'indianapolis' and it['date'] == '12-21':
                    it['skip_tails'] = ['12-21']
            kfile = 'Dio' + n.camel(x['id'])
            lines = self.layer(ver, kfile, base, ctry, items, tok)
            self.emit_layer(ver, kfile, base, tok, lines, '#Propria Officia ' + x['name'] + ' (generated from fssp/na_province.yaml)', x)
            dio_ver[x['id']] = (ver, tok)
        for s in d['sites']:
            if s['id'] in hidden_s:
                continue
            dver, dtok = dio_ver[s['diocese']]
            ver = 'Rubrics 1960 - ' + n.ascii_label(s['name']) + ' ' + n.ascii_label(s['city'].replace(',', ''))
            tok = 'NAP-site-' + s['id']
            items = []
            for t in s.get('titulars', []):
                it = dict(t); it['owner'] = s['id']; it['rank'] = 'I'; it['kind'] = 'titular'
                if t['date'] == '12-12':
                    it['special_dec12'] = True
                if (t['date'], s['id']) in COMMONS_TITLE:
                    pass
                if s['id'].startswith('westwood'):
                    it['use_file'] = None
                items.append(it)
            for t in s.get('extra', []):
                it = dict(t); it['owner'] = s['id']; it['kind'] = 'extra'
                items.append(it)
            for it in items:
                if s['id'].startswith('westwood'):
                    # Philippine Duchesne: reuse repo proper 11-17mh at I class
                    info_file = self.elev_file('11-17mh', 'I', n.US_BASE, '11-17')
                    it['use_file'] = info_file[0]; it['use_title'] = info_file[1]; it['use_saint'] = '11-17mh'; it.pop('propers', None)
            kfile = 'Site' + n.camel(s['id'])
            lines = self.layer(ver, kfile, dver, s['country'], items, tok)
            self.emit_layer(ver, kfile, dver, tok, lines, '#Propria Officia ' + s['name'] + ', ' + s['city'] + ' (generated from fssp/na_province.yaml)', s, parent_tok=dtok)
        # Niagara legacy: rebase onto Canada base (no USA inheritance, gains Dec 12 OLG III)
        self.write_all()

    def emit_layer(self, ver, kfile, base, tok, lines, header, obj, parent_tok=None):
        toks = [tok] + ([parent_tok] if parent_tok else [])
        # include grand-parent (diocese) token for sites already handled by parent_tok; dioceses have none
        self.files['web/www/Tabulae/Kalendaria/%s.txt' % kfile] = header + '\n' + '\n'.join(lines) + ('\n' if lines else '')
        self.tok_of = getattr(self, 'tok_of', {})
        self.tok_of[ver] = toks
        regex = '|'.join(['1960', FSSP_TOKEN] + toks)
        # inherit parent regex tokens
        if base in self.tok_of:
            regex = '|'.join(['1960', FSSP_TOKEN] + toks + [t for t in self.tok_of[base] if t not in toks])
            self.tok_of[ver] = toks + [t for t in self.tok_of[base] if t not in toks]
        row = '%s,%s,%s,%s,%s' % (ver, kfile, regex, regex, base)
        self.rows[ver] = row.split(',')
        self.newrows.append(row)
        self.versions.append(ver)

    def write_all(self):
        # clean previous generation
        if os.path.exists(MANIFEST):
            old = json.load(open(MANIFEST))
            for p in old['files']:
                fp = os.path.join(R, p)
                if os.path.exists(fp):
                    os.remove(fp)
        for p, c in self.files.items():
            fp = os.path.join(R, p)
            os.makedirs(os.path.dirname(fp), exist_ok=True)
            open(fp, 'w', encoding='utf-8').write(c)
        all_vers = ['Rubrics 1960 - FSSP Canada'] + self.versions
        # data.txt
        dp = os.path.join(n.TAB, 'data.txt')
        lines = [l for l in open(dp, encoding='utf-8').read().splitlines()
                 if not any(l.startswith(v + ',') for v in (json.load(open(MANIFEST))['versions'] if os.path.exists(MANIFEST) else []))
                 and not l.startswith('Rubrics 1960 - FSSP Canada,')]
        # insert after Niagara row (before monastic block)
        idx = max(i for i, l in enumerate(lines) if l.startswith('Rubrics 1960 - '))
        lines[idx + 1:idx + 1] = self.newrows
        # every non-generated calendar stacking on FSSP also sees FSSP transfer lines (Chair of St. Peter, 2026)
        def anc(v):
            out = []
            while v and v in self.rows:
                out.append(v); v = self.rows[v][4] if len(self.rows[v]) > 4 else ''
            return out
        fixed = []
        for l in lines:
            p_ = l.split(',')
            if len(p_) >= 5 and 'Rubrics 1960 - FSSP' in anc(p_[0]) and p_[2] == '1960' and FSSP_TOKEN not in p_[2]:
                p_[2] = '1960|' + FSSP_TOKEN
                l = ','.join(p_)
            elif p_[0] == 'Rubrics 1960 - FSSP':
                p_[2] = '1960|' + FSSP_TOKEN
                l = ','.join(p_)
            fixed.append(l)
        lines = fixed
        # rebase Niagara onto Canada chain
        lines = [re.sub(r'^(Rubrics 1960 - Niagara,Niagara,1960,1960,)Rubrics 1960 - FSSP$', r'\1Rubrics 1960 - FSSP Canada', l) for l in lines]
        open(dp, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
        # Tempora
        tp = os.path.join(n.TAB, 'Tempora/Generale.txt')
        tl = [l for l in open(tp, encoding='utf-8').read().splitlines() if 'NAP-' not in l]
        tl += self.tempora
        open(tp, 'w', encoding='utf-8').write('\n'.join(tl) + '\n')
        # horas.dialog
        hp = os.path.join(R, 'web/www/horas/horas.dialog')
        txt = open(hp, encoding='utf-8').read().split('\n')
        i = txt.index('[versions]') + 1
        cur = txt[i].split(',')
        oldv = json.load(open(MANIFEST))['versions'] if os.path.exists(MANIFEST) else []
        cur = [v for v in cur if v not in oldv and v != 'Rubrics 1960 - FSSP Canada']
        txt[i] = ','.join(cur + all_vers)
        open(hp, 'w', encoding='utf-8').write('\n'.join(txt))
        json.dump({'files': sorted(self.files), 'versions': all_vers}, open(MANIFEST, 'w'), indent=1, ensure_ascii=False)
        json.dump({'tags': self.report['tags'], 'collisions': self.report['collisions'],
                   'elevated': self.report['elevated'], 'hidden_dioceses': self.hidden_d,
                   'hidden_sites': self.hidden_s, 'holy_family': self.report['holy_family']},
                  open(os.path.join(R, 'fssp/generation_report.json'), 'w'), indent=1, ensure_ascii=False)
        print('versions generated:', len(all_vers), 'files:', len(self.files))


if __name__ == '__main__':
    Gen().run()
