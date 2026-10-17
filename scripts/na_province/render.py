"""Fetch a full-year ordo for a version from the running web container and parse it."""
import os, re, subprocess, urllib.parse, html

CONTAINER = os.environ.get('DO_ENGINE_CONTAINER', 'divinum-officium-fssp-northamerica-web-1')
ROW = re.compile(r"callbrevi\('(\d\d)-(\d\d)-(\d{4})'\);\">\d+</A></TD>(.*?)</TR>", re.S)


def strip(s):
    return html.unescape(re.sub(r'<[^>]*>', '', s)).strip()


def year(version, y):
    q = urllib.parse.urlencode({'kyear': y, 'kmonth': 14, 'version': version, 'compare': 0, 'yearlist': 1, 'command': ''})
    out = subprocess.run(['docker', 'exec', CONTAINER, 'curl', '-s',
                          'http://localhost:8080/cgi-bin/horas/kalendar.pl?' + q],
                         capture_output=True, text=True, check=True).stdout
    days = {}
    for m in ROW.finditer(out):
        mo, d, yy, rest = m.groups()
        tds = re.findall(r'<TD[^>]*>(.*?)</TD>', rest, re.S)
        if len(tds) < 3:
            continue
        wi = next((i for i, t in enumerate(tds) if '<B>' in t), None)
        if wi is None:
            continue
        win = strip(tds[wi])
        title, _, rank = win.partition('\u2002')
        other = ' '.join(strip(t) for i, t in enumerate(tds[:-1]) if i != wi and strip(t))
        days['%s-%s' % (mo, d)] = {'title': title.strip(), 'rank': rank.strip(), 'extra': other, 'raw': win}
    return days


if __name__ == '__main__':
    import sys, json
    r = year(sys.argv[1], int(sys.argv[2]))
    print(len(r))
    for k in sys.argv[3:]:
        print(k, r.get(k))
