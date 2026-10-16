#!/usr/bin/env python3
"""Summarise Matins for a version/date: nocturns, lessons, empty lessons, unresolved N. (Latin column)."""
import re, subprocess, sys, urllib.parse, html

C = 'divinum-officium-fssp-northamerica-web-1'


def matins(version, mdy, lang2='Latin', hora='prayMatutinum'):
    q = urllib.parse.urlencode({'date': mdy, 'version': version, 'lang2': lang2, 'command': hora})
    out = subprocess.run(['docker', 'exec', C, 'curl', '-s', 'http://localhost:8080/cgi-bin/horas/officium.pl?' + q],
                         capture_output=True, text=True, check=True).stdout
    return html.unescape(re.sub(r'<[^>]*>', ' ', out))


if __name__ == '__main__':
    v, d = sys.argv[1], sys.argv[2]
    t = matins(v, d)
    lines = [l.strip() for l in t.splitlines() if l.strip()]
    heads = [l for l in lines if re.fullmatch(r'(Lectio \d+|Nocturnus \w+|Lectio brevis.*)', l)]
    print('rank line:', next((l for l in lines if 'classis' in l), ''))
    print('nocturns:', sum(1 for h in heads if h.startswith('Nocturnus')), 'lectiones:', sum(1 for h in heads if h.startswith('Lectio ')))
    print('has unresolved N. :', bool(re.search(r'\bN\. ', t)))
    if '-v' in sys.argv:
        i = 0
        for k, l in enumerate(lines):
            if re.fullmatch(r'Lectio \d+', l):
                print(l, '::', ' '.join(lines[k + 1:k + 4])[:230].replace('\n', ' '))
