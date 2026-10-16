"""Shared helpers for the FSSP North American Province calendar generator/tests.

Reads fssp/na_province.yaml and web/www/Tabulae/{data.txt,Kalendaria/*.txt}.
"""
import os, re, unicodedata, yaml

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
TAB = os.path.join(ROOT, 'web/www/Tabulae')
SANCTI = os.path.join(ROOT, 'web/www/horas/Latin/Sancti')
DATAFILE = os.path.join(ROOT, 'fssp/na_province.yaml')

US_BASE = 'Rubrics 1960 - FSSP USA'
CA_BASE = 'Rubrics 1960 - FSSP Canada'


def load_yaml():
    with open(DATAFILE, encoding='utf-8') as f:
        return yaml.safe_load(f)


def is_open(obj):
    """An item is an open question if it mentions CONFIRM or is pending."""
    s = yaml.dump(obj, allow_unicode=True)
    return 'CONFIRM' in s or 'pending' in s


def ascii_label(s):
    s = re.sub(r'\([^)]*\)', '', s).replace("'", '').replace('\u2019', '')
    s = s.replace('&', 'and').replace('–', '-').replace('—', '-').replace(',', '')
    s = unicodedata.normalize('NFKD', s).encode('ascii', 'ignore').decode()
    return re.sub(r'\s+', ' ', s).strip()


def camel(s):
    return ''.join(w[:1].upper() + w[1:] for w in re.split(r'[^A-Za-z0-9]+', s) if w)


def read_data_txt():
    rows = {}
    with open(os.path.join(TAB, 'data.txt'), encoding='utf-8') as f:
        lines = f.read().splitlines()
    for l in lines[1:]:
        if not l.strip():
            continue
        p = l.split(',')
        rows[p[0]] = p
    return rows


def read_kalendar(name):
    out = {}
    path = os.path.join(TAB, 'Kalendaria', name + '.txt')
    with open(path, encoding='utf-8') as f:
        for l in f.read().splitlines():
            if '=' in l and not l.startswith('#'):
                parts = l.split('=')
                out[parts[0]] = parts[1]
    return out


def resolve_entry(version, mmdd, rows=None):
    """Mimic get_from_directorium('kalendar'): own kalendar, then walk `base`."""
    rows = rows or read_data_txt()
    while version:
        r = rows.get(version)
        if not r:
            return ''
        k = read_kalendar(r[1])
        if mmdd in k:
            return k[mmdd]
        version = r[4] if len(r) > 4 else ''
    return ''
