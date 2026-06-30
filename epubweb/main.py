from pathlib import Path
from fastapi import FastAPI, Form, Depends, HTTPException
from fastapi.responses import HTMLResponse, FileResponse, JSONResponse, StreamingResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials
import subprocess, threading, uuid, re, time, json, io, zipfile, os, secrets
import calendar as cal_lib
from datetime import datetime, timedelta
from typing import Optional

app = FastAPI()

_security = HTTPBasic(auto_error=False)

def _admin(creds = Depends(_security)):
    expected_user = os.environ.get("ADMIN_USER", "")
    expected_pass = os.environ.get("ADMIN_PASS", "")
    if not expected_user or not expected_pass:
        raise HTTPException(503, detail="Admin not configured — set ADMIN_USER and ADMIN_PASS")
    if creds is None:
        raise HTTPException(401, headers={"WWW-Authenticate": 'Basic realm="DO Admin"'})
    ok = (secrets.compare_digest(creds.username.encode(), expected_user.encode()) and
          secrets.compare_digest(creds.password.encode(), expected_pass.encode()))
    if not ok:
        raise HTTPException(401, headers={"WWW-Authenticate": 'Basic realm="DO Admin"'})

OUTPUT_BASE  = Path("/epub-output")
OUTPUT_BASE.mkdir(parents=True, exist_ok=True)
SETTINGS_FILE = OUTPUT_BASE / ".settings.json"

EPUBGEN_SH   = "/var/www/standalone/tools/epubgen2/epubgen2.sh"
EPUBGEN_DIR  = "/var/www/standalone/tools/epubgen2"
DATA_TXT      = Path("/var/www/web/www/Tabulae/data.txt")
KALENDARIA_DIR = Path("/var/www/web/www/Tabulae/Kalendaria")

jobs = {}
active_outputs = {}

KNOWN_SUFFIXES = {
    "Sacramento": "_Sac", "FSSPUSA": "_FSSPUSA", "Chesapeake": "_Ches",
    "Guadalajara": "_GLD", "FSSP": "_FSSP", "1960": "",
    "Nashua": "_Nas", "Arlington": "_Arl",
}
BASE_CALENDARS  = [("FSSPUSA","_FSSPUSA","FSSP USA"),("FSSP","_FSSP","FSSP"),("1960","","Rubrics 1960")]
_PARISH_PARENTS = {"Rubrics 1960 - FSSP USA", "Rubrics 1960 - FSSP"}
_EXCLUDE_CODES  = {"USA1960", "FSSP", "1960"}


def load_calendars():
    parish, seen = [], set()
    if DATA_TXT.exists() and KALENDARIA_DIR.exists():
        with open(DATA_TXT) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#') or line.startswith('version'):
                    continue
                parts = line.split(',')
                if len(parts) < 5:
                    continue
                version_name, code, parent = parts[0], parts[1], parts[4]
                if (version_name.startswith('Rubrics 1960 - ')
                        and code not in seen and code not in _EXCLUDE_CODES
                        and parent in _PARISH_PARENTS
                        and (KALENDARIA_DIR / f"{code}.txt").exists()):
                    parish.append((code, KNOWN_SUFFIXES.get(code, f"_{code}"),
                                   version_name[len('Rubrics 1960 - '):]))
                    seen.add(code)
    return parish + [b for b in BASE_CALENDARS if b[0] not in seen]


CALENDARS      = load_calendars()
RUBRICS_SUFFIX = {code: suffix for code, suffix, _ in CALENDARS}
CAL_LABEL      = {code: label for code, _, label in CALENDARS}
DEFAULT_CAL    = next((c[0] for c in CALENDARS if c[0] == "Sacramento"),
                      CALENDARS[0][0] if CALENDARS else "")

LANGUAGES = [
    "Latin","English","Spanish","French","German","Italian",
    "Portuguese","Polish","Czech","Danish","Hungarian","Dutch",
    "Polish-Newer","Latin-Bea",
]
MONTH_NAMES = [
    "January","February","March","April","May","June",
    "July","August","September","October","November","December",
]
YEAR_NOW = datetime.now().year


# ──────────────────────────────────────────────────────────────
# Settings & cleanup scheduler
# ──────────────────────────────────────────────────────────────

def _load_settings() -> dict:
    if SETTINGS_FILE.exists():
        try:
            return json.loads(SETTINGS_FILE.read_text())
        except Exception:
            pass
    return {"cleanup_schedule": "never", "last_cleanup": None}


def _save_settings(s: dict):
    SETTINGS_FILE.write_text(json.dumps(s, indent=2))


def _do_clear_all():
    for d in OUTPUT_BASE.iterdir():
        if d.is_dir():
            import shutil
            shutil.rmtree(d, ignore_errors=True)


def _do_clear_calendar(cal_code: str):
    import shutil
    for d in _dirs_for_calendar(cal_code):
        shutil.rmtree(d, ignore_errors=True)


def _cleanup_loop():
    while True:
        time.sleep(3600 * 6)
        s = _load_settings()
        schedule = s.get("cleanup_schedule", "never")
        if schedule == "never":
            continue
        last_raw = s.get("last_cleanup")
        now = datetime.now()
        if last_raw:
            last = datetime.fromisoformat(last_raw)
            delta = now - last
            if schedule == "weekly"  and delta < timedelta(days=7):
                continue
            if schedule == "monthly" and delta < timedelta(days=30):
                continue
        _do_clear_all()
        s["last_cleanup"] = now.isoformat()
        _save_settings(s)


threading.Thread(target=_cleanup_loop, daemon=True).start()


# ──────────────────────────────────────────────────────────────
# File helpers
# ──────────────────────────────────────────────────────────────

def _dirs_for_calendar(cal_code: str) -> list:
    result = []
    for d in sorted(OUTPUT_BASE.iterdir()):
        if not d.is_dir():
            continue
        parts = d.name.split('_', 2)
        if len(parts) >= 2 and parts[1] == cal_code:
            result.append(d)
    return result


def _calendars_with_files() -> dict:
    out = {}
    if not OUTPUT_BASE.exists():
        return out
    for d in OUTPUT_BASE.iterdir():
        if not d.is_dir():
            continue
        parts = d.name.split('_', 2)
        if len(parts) < 2:
            continue
        code  = parts[1]
        count = len(list(d.glob("*.epub")))
        if count:
            if code not in out:
                out[code] = {"label": CAL_LABEL.get(code, code), "count": 0}
            out[code]["count"] += count
    return out


# ──────────────────────────────────────────────────────────────
# Shared CSS
# ──────────────────────────────────────────────────────────────

_SHARED_CSS = """
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:Georgia,serif;background:#f5f0e8;color:#2c1f0e;min-height:100vh;padding:2rem 1rem}
.container{max-width:680px;margin:0 auto}
h1{font-size:1.7rem;margin-bottom:.2rem;color:#3b1f0a}
.subtitle{color:#7a5c3a;margin-bottom:2rem;font-style:italic}
h2{font-size:1.05rem;color:#3b1f0a;margin-bottom:.9rem;font-weight:bold}
.card{background:#fff;border:1px solid #d6c9b0;border-radius:6px;padding:1.4rem 1.5rem;margin-bottom:1.3rem}
.form-row{margin-bottom:1.05rem}
label{display:block;font-weight:bold;font-size:.8rem;color:#5c3d1e;margin-bottom:.3rem;text-transform:uppercase;letter-spacing:.05em}
select,input[type=number]{width:100%;padding:.5rem .65rem;font-size:.93rem;border:1px solid #c4b49a;border-radius:4px;background:#fdf8f0;color:#2c1f0e}
select:focus,input:focus{outline:none;border-color:#8b5e3c;box-shadow:0 0 0 2px rgba(139,94,60,.15)}
.radio-row{display:flex;gap:1.5rem;align-items:center;flex-wrap:wrap;margin-top:.2rem}
.radio-label{display:flex;align-items:center;gap:.4rem;font-weight:normal;text-transform:none;letter-spacing:0;font-size:.93rem;cursor:pointer}
.radio-label input{width:auto}
#monthWrap{display:none;align-items:center;gap:.4rem}
#monthSelect{width:auto;padding:.4rem .55rem}
.btn{background:#6b2d0f;color:#fff;border:none;padding:.65rem 1.6rem;font-size:.93rem;border-radius:4px;cursor:pointer;transition:background .2s}
.btn:hover{background:#8b3d1a}
.btn:disabled{background:#aaa;cursor:not-allowed}
.btn-sm{padding:.35rem .85rem;font-size:.8rem}
.btn-danger{background:#991b1b}
.btn-danger:hover{background:#b91c1c}
.btn-neutral{background:#4b5563}
.btn-neutral:hover{background:#374151}
/* progress */
.stage-row{display:flex;align-items:center;gap:.55rem;margin-bottom:.75rem}
.stage-dot{width:10px;height:10px;border-radius:50%;flex-shrink:0}
.dot-running{background:#d97706;animation:pulse 1.2s infinite}
.dot-done{background:#16a34a}
.dot-error{background:#dc2626}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.35}}
.stage-text{font-weight:bold;font-size:.93rem}
.progress-track{background:#ede4d5;border-radius:99px;height:13px;overflow:hidden}
.progress-fill{background:linear-gradient(90deg,#6b2d0f,#a04020);height:100%;border-radius:99px;transition:width .6s ease;width:0%}
.progress-meta{display:flex;justify-content:space-between;font-size:.8rem;color:#888;margin-top:.45rem}
/* calendar cards */
.cal-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:.75rem;margin-bottom:.5rem}
.cal-card{border:1px solid #d6c9b0;border-radius:5px;padding:.9rem 1rem;background:#fdfaf5;text-decoration:none;color:#2c1f0e;display:block;transition:border-color .15s,background .15s}
.cal-card:hover{border-color:#8b5e3c;background:#fff}
.cal-card-name{font-weight:bold;font-size:.95rem;margin-bottom:.2rem}
.cal-card-count{font-size:.78rem;color:#888}
.empty-note{color:#999;font-style:italic;font-size:.88rem}
/* cleanup */
.cleanup-row{display:flex;align-items:center;gap:.75rem;flex-wrap:wrap}
.cleanup-meta{font-size:.8rem;color:#888;margin-top:.5rem}
/* file list (calendar page) */
.file-group{margin-bottom:1.1rem}
.group-title{font-size:.78rem;font-weight:bold;color:#7a5c3a;text-transform:uppercase;letter-spacing:.06em;padding-bottom:.3rem;border-bottom:1px solid #e8dcc8;margin-bottom:.4rem}
.file-item{display:flex;align-items:center;gap:.5rem;padding:.38rem 0;border-bottom:1px solid #f4ede0}
.file-item:last-child{border-bottom:none}
.file-name{font-family:monospace;font-size:.82rem;flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.file-size{font-size:.77rem;color:#999;white-space:nowrap}
.dl-btn{background:#2c5282;color:#fff;text-decoration:none;padding:.26rem .65rem;border-radius:3px;font-size:.77rem;white-space:nowrap}
.dl-btn:hover{background:#2b6cb0}
.back-link{font-size:.85rem;color:#6b2d0f;text-decoration:none;display:inline-block;margin-bottom:1.2rem}
.back-link:hover{text-decoration:underline}
"""


# ──────────────────────────────────────────────────────────────
# HTML — Public download page
# ──────────────────────────────────────────────────────────────

def _main_html() -> str:
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>FSSP Divine Office — EPUB Downloads</title>
  <style>{_SHARED_CSS}</style>
</head>
<body>
<div class="container">
  <h1>FSSP Divine Office</h1>
  <p class="subtitle">EPUB files — Divinum Officium, FSSP North America</p>

  <div class="card">
    <h2>Download Files</h2>
    <div id="calCards"><p class="empty-note">Loading…</p></div>
  </div>
</div>

<script>
async function loadCalCards() {{
  const data = await (await fetch('/calendars')).json();
  const el = document.getElementById('calCards');
  const entries = Object.entries(data);
  if (!entries.length) {{
    el.innerHTML = '<p class="empty-note">No files available yet — check back soon.</p>';
    return;
  }}
  el.innerHTML = '<div class="cal-grid">' + entries.map(([code, info]) =>
    `<a class="cal-card" href="/calendar/${{encodeURIComponent(code)}}">
       <div class="cal-card-name">${{info.label}}</div>
       <div class="cal-card-count">${{info.count}} file${{info.count===1?'':'s'}}</div>
     </a>`
  ).join('') + '</div>';
}}
loadCalCards();
</script>
</body>
</html>"""


# ──────────────────────────────────────────────────────────────
# HTML — Admin page (generator + settings, requires auth)
# ──────────────────────────────────────────────────────────────

def _admin_html() -> str:
    lang_opts = "\n".join(
        f'<option value="{l}"{" selected" if l=="Latin" else ""}>{l}</option>'
        for l in LANGUAGES)
    cal_opts = "\n".join(
        f'<option value="{c}"{" selected" if c==DEFAULT_CAL else ""}>{lbl}</option>'
        for c, _, lbl in CALENDARS)
    month_opts = "\n".join(
        f'<option value="{i+1}">{n}</option>'
        for i, n in enumerate(MONTH_NAMES))

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Admin — EPUB Generator</title>
  <style>{_SHARED_CSS}</style>
</head>
<body>
<div class="container">
  <a class="back-link" href="/">← Public Download Page</a>
  <h1>EPUB Generator</h1>
  <p class="subtitle">Admin — Breviarium Divinum Officium FSSP Fork</p>

  <div class="card">
    <form id="genForm" onsubmit="startGeneration(event)">
      <div class="form-row">
        <label for="lang2">Second Language</label>
        <select name="lang2" id="lang2">{lang_opts}</select>
      </div>
      <div class="form-row">
        <label for="cal_code">Calendar</label>
        <select name="cal_code" id="cal_code">{cal_opts}</select>
      </div>
      <div class="form-row">
        <label for="year">Year</label>
        <input type="number" name="year" id="year" value="{YEAR_NOW}" min="2020" max="2035">
      </div>
      <div class="form-row">
        <label>Range</label>
        <div class="radio-row">
          <label class="radio-label">
            <input type="radio" name="range_type" value="year" checked onchange="updateRange(this)"> Whole Year
          </label>
          <label class="radio-label">
            <input type="radio" name="range_type" value="month" onchange="updateRange(this)"> Single Month
          </label>
          <span id="monthWrap">
            <select name="month" id="monthSelect" disabled>{month_opts}</select>
          </span>
        </div>
      </div>
      <button type="submit" class="btn" id="genBtn">Generate EPUB</button>
    </form>
  </div>

  <div class="card" id="progressCard" style="display:none">
    <div class="stage-row">
      <span class="stage-dot dot-running" id="stageDot"></span>
      <span class="stage-text" id="stageText">Starting…</span>
    </div>
    <div class="progress-track"><div class="progress-fill" id="progressFill"></div></div>
    <div class="progress-meta">
      <span id="progressPct">0%</span>
      <span id="progressEta"></span>
    </div>
  </div>

  <div class="card">
    <h2>Auto-Cleanup</h2>
    <div class="cleanup-row">
      <select id="scheduleSelect" style="width:auto">
        <option value="never">Never</option>
        <option value="weekly">Weekly</option>
        <option value="monthly">Monthly</option>
      </select>
      <button class="btn btn-sm btn-neutral" onclick="saveSchedule()">Save Schedule</button>
      <button class="btn btn-sm btn-danger" onclick="clearAll()">Clear All Files Now</button>
    </div>
    <div class="cleanup-meta" id="cleanupMeta"></div>
  </div>
</div>

<script>
let currentJobId = null;

function updateRange(radio) {{
  const w = document.getElementById('monthWrap');
  w.style.display = radio.value === 'month' ? 'flex' : 'none';
  document.getElementById('monthSelect').disabled = (radio.value === 'year');
}}

async function startGeneration(e) {{
  e.preventDefault();
  const btn = document.getElementById('genBtn');
  btn.disabled = true; btn.textContent = 'Generating…';
  const fd = new FormData(e.target);
  const resp = await fetch('/generate', {{method:'POST', body:fd}});
  if (resp.status === 401) {{
    alert('Session expired — reload the page to log in again.');
    btn.disabled=false; btn.textContent='Generate EPUB'; return;
  }}
  const data = await resp.json();
  if (data.error) {{ alert('Error: '+data.error); btn.disabled=false; btn.textContent='Generate EPUB'; return; }}
  currentJobId = data.job_id;
  const card = document.getElementById('progressCard');
  card.style.display = 'block';
  card.scrollIntoView({{behavior:'smooth',block:'nearest'}});
  if (data.already_done) {{
    setStage('done','Already generated — ready to download.');
    setProgress(100,0); btn.disabled=false; btn.textContent='Generate EPUB';
  }} else {{
    setStage('running','Starting…'); setProgress(0,null);
    setTimeout(pollStatus, 2000);
  }}
}}

async function pollStatus() {{
  if (!currentJobId) return;
  try {{
    const data = await (await fetch('/status/'+currentJobId)).json();
    if (data.status==='running') {{
      setStage('running', data.stage||'Processing…');
      setProgress(data.progress, data.eta_seconds);
      setTimeout(pollStatus, 2000);
    }} else {{
      const btn = document.getElementById('genBtn');
      btn.disabled=false; btn.textContent='Generate EPUB';
      if (data.status==='done') {{ setStage('done','Complete'); setProgress(100,0); }}
      else {{ setStage('error','Generation failed.'); }}
    }}
  }} catch(e) {{ setTimeout(pollStatus,3000); }}
}}

function setStage(state,text) {{
  document.getElementById('stageDot').className='stage-dot dot-'+state;
  document.getElementById('stageText').textContent=text;
}}
function setProgress(pct, eta) {{
  document.getElementById('progressFill').style.width=pct+'%';
  document.getElementById('progressPct').textContent=pct+'%';
  document.getElementById('progressEta').textContent = (eta>0) ? 'About '+fmtEta(eta)+' remaining' : '';
}}
function fmtEta(s) {{
  if (s<90) return Math.round(s)+'s';
  if (s<3600) return Math.round(s/60)+' min';
  return Math.floor(s/3600)+'h '+Math.round((s%3600)/60)+'m';
}}

async function saveSchedule() {{
  const val = document.getElementById('scheduleSelect').value;
  const resp = await fetch('/settings', {{method:'POST',
    headers:{{'Content-Type':'application/json'}},
    body:JSON.stringify({{cleanup_schedule:val}})}});
  if (resp.status === 401) {{ alert('Session expired — reload to log in again.'); return; }}
  showCleanupMeta(await resp.json());
}}

async function clearAll() {{
  if (!confirm('Delete ALL generated EPUB files? This cannot be undone.')) return;
  const resp = await fetch('/clear', {{method:'POST'}});
  if (resp.status === 401) {{ alert('Session expired — reload to log in again.'); return; }}
  window.location.reload();
}}

async function loadSettings() {{
  const resp = await fetch('/settings');
  if (!resp.ok) return;
  const data = await resp.json();
  document.getElementById('scheduleSelect').value = data.cleanup_schedule || 'never';
  showCleanupMeta(data);
}}

function showCleanupMeta(data) {{
  const el = document.getElementById('cleanupMeta');
  const last = data.last_cleanup ? new Date(data.last_cleanup).toLocaleDateString() : 'Never';
  el.textContent = 'Last cleanup: ' + last;
}}

loadSettings();
</script>
</body>
</html>"""


MAIN_HTML  = _main_html()
ADMIN_HTML = _admin_html()


# ──────────────────────────────────────────────────────────────
# HTML — Calendar detail page (generated per-request)
# ──────────────────────────────────────────────────────────────

def _calendar_html(cal_code: str) -> str:
    label = CAL_LABEL.get(cal_code, cal_code)
    dirs  = _dirs_for_calendar(cal_code)

    groups = []
    total_files = 0
    for d in dirs:
        epubs = sorted(d.glob("*.epub"))
        if not epubs:
            continue
        parts = d.name.split('_', 2)
        period = parts[0]
        lang   = parts[2] if len(parts) > 2 else "Latin"
        total_size = sum(e.stat().st_size for e in epubs)
        groups.append({"dir": d, "period": period, "lang": lang,
                       "files": epubs, "total_size": total_size})
        total_files += len(epubs)

    def fmt_size(b):
        if b < 1048576:
            return f"{b//1024} KB"
        return f"{b/1048576:.1f} MB"

    files_html = ""
    if not groups:
        files_html = '<p class="empty-note">No files generated yet for this calendar.</p>'
    else:
        for g in groups:
            period_label = g["period"]
            if len(period_label) == 7 and period_label[4] == '-':
                y, m = period_label.split('-')
                period_label = f"{MONTH_NAMES[int(m)-1]} {y}"
            files_html += f'<div class="file-group"><div class="group-title">{period_label} — {g["lang"]}</div>'
            for epub in g["files"]:
                size_str = fmt_size(epub.stat().st_size)
                dl_url = f"/download/{g['dir'].name}/{epub.name}"
                files_html += (
                    f'<div class="file-item">'
                    f'<span class="file-name" title="{epub.name}">{epub.name}</span>'
                    f'<span class="file-size">{size_str}</span>'
                    f'<a class="dl-btn" href="{dl_url}" download="{epub.name}">Download</a>'
                    f'</div>'
                )
            files_html += '</div>'

    dl_all_btn = (
        f'<a class="btn" style="text-decoration:none;display:inline-block;margin-bottom:1rem" '
        f'href="/calendar/{cal_code}/download-all">Download All as ZIP</a>'
        if total_files > 0 else ""
    )

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>{label} — EPUB Downloads</title>
  <style>{_SHARED_CSS}</style>
</head>
<body>
<div class="container">
  <a class="back-link" href="/">← Back</a>
  <h1>{label}</h1>
  <p class="subtitle">{total_files} file{"s" if total_files != 1 else ""} generated</p>

  {dl_all_btn}

  <div class="card">
    <h2>Files</h2>
    {files_html}
  </div>

  <div class="card">
    <h2>Delete</h2>
    <p style="font-size:.88rem;color:#666;margin-bottom:.75rem">
      Remove all generated EPUB files for {label}.
      Admin login required.
    </p>
    <button class="btn btn-danger btn-sm" onclick="clearCalendar()">
      Delete All {label} Files
    </button>
  </div>
</div>
<script>
async function clearCalendar() {{
  if (!confirm('Delete all EPUB files for {label}? This cannot be undone.')) return;
  const resp = await fetch('/calendar/{cal_code}/clear', {{method:'POST'}});
  if (resp.ok) window.location.href = '/';
  else if (resp.status === 401) alert('Admin login required. Visit /admin to authenticate first.');
  else alert('Error deleting files.');
}}
</script>
</body>
</html>"""


# ──────────────────────────────────────────────────────────────
# Background generation
# ──────────────────────────────────────────────────────────────

_STAGE_MAP = {
    'Starting to generate hours':  'Generating hours',
    'Starting to create TOCs':     'Building table of contents',
    'Starting to create OPFs':     'Building OPF metadata',
    'Starting to create EPUBs':    'Packaging EPUB',
}


def _run(job_id: str, cal_code: str, lang2: str, year: int, month: Optional[int]):
    job = jobs[job_id]
    m_from = month or 1
    m_to   = month or 12
    total  = sum(cal_lib.monthrange(year, m)[1] for m in range(m_from, m_to + 1)) * 8
    job.update(total=total, completed=0, start_time=time.monotonic(), stage='Starting…')

    cmd = ["bash", EPUBGEN_SH, "-y", str(year), "-r", cal_code, "-l", lang2,
           "-o", str(OUTPUT_BASE / job["output_key"])]
    if month:
        cmd += ["-M", str(month), "-N", str(month)]

    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, cwd=EPUBGEN_DIR)
        for raw in proc.stdout:
            line = re.sub(r'\x1b\[[0-9;]*m', '', raw).strip()
            if not line:
                continue
            if line.startswith('Generating '):
                job['completed'] += 1
            else:
                for key, label in _STAGE_MAP.items():
                    if key in line:
                        job['stage'] = label
                        break
            job['log'].append(line)
            if len(job['log']) > 2000:
                job['log'] = job['log'][-1000:]
        proc.wait()
        job['status'] = 'done' if proc.returncode == 0 else 'error'
        if proc.returncode != 0:
            job['log'].append(f'[exit {proc.returncode}]')
    except Exception as exc:
        job['status'] = 'error'
        job['log'].append(f'Exception: {exc}')
    finally:
        active_outputs.pop(job['output_key'], None)


# ──────────────────────────────────────────────────────────────
# Routes
# ──────────────────────────────────────────────────────────────

@app.get("/", response_class=HTMLResponse)
def index():
    return MAIN_HTML


@app.get("/admin", response_class=HTMLResponse, dependencies=[Depends(_admin)])
def admin_page():
    return ADMIN_HTML


@app.post("/generate", dependencies=[Depends(_admin)])
def generate(
    cal_code:   str = Form(...),
    lang2:      str = Form("Latin"),
    year:       int = Form(...),
    range_type: str = Form("year"),
    month:      int = Form(1),
):
    valid_cals = {c[0] for c in CALENDARS}
    if cal_code not in valid_cals:
        return JSONResponse({"error": "Invalid calendar"}, status_code=400)
    if lang2 not in LANGUAGES:
        return JSONResponse({"error": "Invalid language"}, status_code=400)

    m = month if range_type == "month" else None
    output_key = f"{year}-{m:02d}_{cal_code}_{lang2}" if m else f"{year}_{cal_code}_{lang2}"

    if output_key in active_outputs:
        return JSONResponse({"job_id": active_outputs[output_key], "output_key": output_key})

    suffix   = RUBRICS_SUFFIX.get(cal_code, f"_{cal_code}")
    out_dir  = OUTPUT_BASE / output_key
    expected = out_dir / (f"breviarium{year}-{m:02d}{suffix}.epub" if m
                          else f"breviarium{year}{suffix}.epub")
    if expected.exists():
        jid = str(uuid.uuid4())
        jobs[jid] = {"status": "done", "log": [], "output_key": output_key,
                     "total": 1, "completed": 1, "stage": "Complete",
                     "start_time": time.monotonic()}
        return JSONResponse({"job_id": jid, "output_key": output_key, "already_done": True})

    out_dir.mkdir(parents=True, exist_ok=True)
    jid = str(uuid.uuid4())
    jobs[jid] = {"status": "running", "log": [], "output_key": output_key,
                 "total": 0, "completed": 0, "stage": "Starting…",
                 "start_time": time.monotonic()}
    active_outputs[output_key] = jid
    threading.Thread(target=_run, args=(jid, cal_code, lang2, year, m), daemon=True).start()
    return JSONResponse({"job_id": jid, "output_key": output_key})


@app.get("/status/{job_id}")
def status(job_id: str):
    if job_id not in jobs:
        return JSONResponse({"error": "Not found"}, status_code=404)
    job     = jobs[job_id]
    total   = job.get("total", 0)
    done    = job.get("completed", 0)
    elapsed = time.monotonic() - job.get("start_time", time.monotonic())
    if job["status"] == "done":
        progress = 100
    elif total > 0 and done > 0:
        progress = min(90, int(done / total * 90))
        if job.get("stage", "").startswith("Packaging"):
            progress = max(progress, 92)
    else:
        progress = 0
    eta = None
    if job["status"] == "running" and done > 2 and total > done and elapsed > 3:
        eta = int((total - done) / (done / elapsed))
    return JSONResponse({
        "status": job["status"], "progress": progress,
        "stage": job.get("stage", "Starting…"), "eta_seconds": eta,
    })


@app.get("/calendars")
def calendars_with_files():
    return JSONResponse(_calendars_with_files())


@app.get("/calendar/{cal_code}", response_class=HTMLResponse)
def calendar_page(cal_code: str):
    valid = {c[0] for c in CALENDARS}
    if cal_code not in valid:
        return HTMLResponse("Calendar not found.", status_code=404)
    return _calendar_html(cal_code)


@app.get("/calendar/{cal_code}/download-all")
def download_all(cal_code: str):
    valid = {c[0] for c in CALENDARS}
    if cal_code not in valid:
        return JSONResponse({"error": "Not found"}, status_code=404)
    dirs = _dirs_for_calendar(cal_code)
    buf  = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as zf:
        for d in dirs:
            for epub in sorted(d.glob("*.epub")):
                zf.write(epub, f"{d.name}/{epub.name}")
    buf.seek(0)
    label = CAL_LABEL.get(cal_code, cal_code)
    return StreamingResponse(
        buf,
        media_type="application/zip",
        headers={"Content-Disposition": f'attachment; filename="{label}-epubs.zip"'},
    )


@app.post("/calendar/{cal_code}/clear", dependencies=[Depends(_admin)])
def clear_calendar(cal_code: str):
    valid = {c[0] for c in CALENDARS}
    if cal_code not in valid:
        return JSONResponse({"error": "Not found"}, status_code=404)
    _do_clear_calendar(cal_code)
    return JSONResponse({"ok": True})


@app.post("/clear", dependencies=[Depends(_admin)])
def clear_all():
    _do_clear_all()
    return JSONResponse({"ok": True})


@app.get("/settings")
def get_settings():
    return JSONResponse(_load_settings())


@app.post("/settings", dependencies=[Depends(_admin)])
def post_settings(body: dict):
    s = _load_settings()
    if "cleanup_schedule" in body:
        s["cleanup_schedule"] = body["cleanup_schedule"]
    _save_settings(s)
    return JSONResponse(s)


@app.get("/files")
def list_files():
    result = []
    if not OUTPUT_BASE.exists():
        return JSONResponse(result)
    for d in sorted(OUTPUT_BASE.iterdir()):
        if not d.is_dir():
            continue
        for epub in sorted(d.glob("*.epub")):
            result.append({"key": d.name, "filename": epub.name, "size": epub.stat().st_size})
    return JSONResponse(result)


@app.get("/download/{output_key}/{filename}")
def download(output_key: str, filename: str):
    if ".." in output_key or ".." in filename or "/" in output_key or "/" in filename:
        return JSONResponse({"error": "Invalid path"}, status_code=400)
    if not filename.endswith(".epub"):
        return JSONResponse({"error": "Not found"}, status_code=404)
    path = OUTPUT_BASE / output_key / filename
    if not path.exists():
        return JSONResponse({"error": "Not found"}, status_code=404)
    return FileResponse(path=path, filename=filename, media_type="application/epub+zip")
