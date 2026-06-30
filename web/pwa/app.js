'use strict';

const API_URL = '/cgi-bin/horas/offline_pack.pl';

const CALENDARS = [
  { label: 'FSSP',         version: 'Rubrics 1960 - FSSP' },
  { label: 'General 1960', version: 'Rubrics 1960 - 1960' },
  { label: 'USA 1960',     version: 'Rubrics 1960 - USA 1960' },
  { label: 'Sacramento',   version: 'Rubrics 1960 - Sacramento' },
  { label: 'Guadalajara',  version: 'Rubrics 1960 - Guadalajara' },
  { label: 'Chesapeake',   version: 'Rubrics 1960 - Chesapeake' },
  { label: 'Nashua',       version: 'Rubrics 1960 - Nashua' },
  { label: 'Arlington',    version: 'Rubrics 1960 - Arlington' },
];

const HORAS = [
  { key: 'matins',   label: 'Matutinum',    short: 'Mat' },
  { key: 'lauds',    label: 'Laudes',       short: 'Lau' },
  { key: 'prime',    label: 'Prima',        short: 'Pri' },
  { key: 'terce',    label: 'Tertia',       short: 'Ter' },
  { key: 'sext',     label: 'Sexta',        short: 'Sex' },
  { key: 'none',     label: 'Nona',         short: 'Non' },
  { key: 'vespers',  label: 'Vesperae',     short: 'Ves' },
  { key: 'compline', label: 'Completorium', short: 'Com' },
];

// --- State ---
let state = {
  calendar: null,   // friendly label e.g. "FSSP"
  version: null,    // full version string e.g. "Rubrics 1960 - FSSP"
  date: null,       // YYYY-MM-DD
  hora: 'lauds',
  dayData: null,
};

// --- Read tracking (localStorage) ---
function isRead(cal, date, hora) {
  return localStorage.getItem(`do-read:${cal}:${date}:${hora}`) === '1';
}
function markReadLocal(cal, date, hora) {
  localStorage.setItem(`do-read:${cal}:${date}:${hora}`, '1');
}

// --- Font size ---
let fontSize = parseFloat(localStorage.getItem('do-font-size') || '1.0');
function applyFontSize() {
  fontSize = Math.max(0.8, Math.min(3.0, parseFloat(fontSize.toFixed(1))));
  document.documentElement.style.setProperty('--reading-font-size', fontSize + 'rem');
  const lbl = document.getElementById('font-size-label');
  if (lbl) lbl.textContent = fontSize.toFixed(1) + '×';
  localStorage.setItem('do-font-size', fontSize);
}

// --- Theme ---
let theme = localStorage.getItem('do-theme') || 'dark';
function applyTheme() {
  document.documentElement.setAttribute('data-theme', theme);
  document.querySelectorAll('input[name="theme"]').forEach(r => { r.checked = r.value === theme; });
  localStorage.setItem('do-theme', theme);
}

// --- Screens ---
function showScreen(id) {
  document.querySelectorAll('.screen').forEach(s => s.classList.remove('active'));
  document.getElementById('screen-' + id).classList.add('active');
  // Reset scroll
  if (id === 'download') refreshCachedSection();
}

// --- Toast ---
let toastTimer;
function showToast(msg, duration = 2200) {
  const el = document.getElementById('toast');
  el.textContent = msg;
  el.classList.remove('hidden');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.add('hidden'), duration);
}

// --- Status dots ---
function updateStatusDots() {
  const online = navigator.onLine;
  document.querySelectorAll('.status-dot').forEach(el => {
    el.className = 'status-dot ' + (online ? 'online' : 'offline');
    el.title = online ? 'Online' : 'Offline — showing cached content';
  });
}

// --- Date utils ---
function todayISO() {
  const d = new Date();
  return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`;
}
function pad(n) { return String(n).padStart(2, '0'); }
function addDaysISO(iso, n) {
  const d = new Date(iso + 'T00:00:00');
  d.setDate(d.getDate() + n);
  return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`;
}
function formatDateDisplay(iso) {
  return new Date(iso + 'T00:00:00').toLocaleDateString('en-US', {
    weekday: 'short', month: 'short', day: 'numeric'
  });
}

// --- Calendar utils ---
function calLabel(version) {
  return CALENDARS.find(c => c.version === version)?.label || version;
}
function selectedVersion() {
  return document.getElementById('cal-picker').value;
}
function selectedCalLabel() {
  return calLabel(selectedVersion());
}

// --- Download ---
async function downloadRange(version, startDate, days, lang) {
  const btn = document.getElementById('btn-download');
  const progressWrap = document.getElementById('download-progress');
  const fill = document.getElementById('progress-fill');

  btn.disabled = true;
  progressWrap.classList.remove('hidden');
  fill.style.width = '5%';

  const params = new URLSearchParams({ calendar: version, start: startDate, days, lang });

  try {
    const res = await fetch(`${API_URL}?${params}`);
    fill.style.width = '40%';

    if (!res.ok) {
      let msg = res.statusText;
      try { const e = await res.json(); msg = e.error || msg; } catch {}
      throw new Error(msg);
    }

    const data = await res.json();
    fill.style.width = '75%';

    const cal = calLabel(version);
    await saveDays(cal, data.days);
    fill.style.width = '100%';

    showToast(`✓ Downloaded ${data.days.length} day${data.days.length !== 1 ? 's' : ''}`);
    setTimeout(async () => {
      progressWrap.classList.add('hidden');
      fill.style.width = '0%';
      btn.disabled = false;
      await refreshCachedSection();
    }, 600);

  } catch (err) {
    progressWrap.classList.add('hidden');
    fill.style.width = '0%';
    btn.disabled = false;
    showToast('Download failed: ' + err.message, 5000);
  }
}

// --- Cached section (download screen) ---
async function refreshCachedSection() {
  const section = document.getElementById('cached-section');
  const datesEl = document.getElementById('cached-dates');
  const cal = selectedCalLabel();
  const dates = await listCachedDates(cal);

  if (dates.length === 0) {
    section.classList.add('hidden');
    return;
  }

  section.classList.remove('hidden');
  const shown = dates.slice(0, 12);
  const extra = dates.length - shown.length;
  datesEl.innerHTML = shown.map(d => {
    const display = new Date(d + 'T00:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    return `<span class="date-chip">${display}</span>`;
  }).join('') + (extra > 0 ? `<span class="date-chip muted">+${extra} more</span>` : '');
}

// --- Reading screen ---
async function openReading(cal, version, date, hora) {
  state.calendar = cal;
  state.version = version;
  state.date = date;
  state.hora = hora || state.hora;
  showScreen('reading');
  await loadAndRender(cal, date);
}

async function loadAndRender(cal, date) {
  const dayData = await getDay(cal, date);
  state.dayData = dayData;

  document.getElementById('btn-date').textContent = formatDateDisplay(date);

  // Prev/next nav: disable if no data cached in that direction
  await updateNavButtons(cal, date);

  updateHoraTabs(cal, date);

  if (!dayData) {
    document.getElementById('office-content').innerHTML =
      '<p class="error-msg">No data cached for this date.<br>Go back and download it first.</p>';
    document.getElementById('mark-read-bar').classList.add('hidden');
    return;
  }

  renderHora(state.hora);
}

function renderHora(horaKey) {
  state.hora = horaKey;
  const content = document.getElementById('office-content');
  const markBar = document.getElementById('mark-read-bar');

  if (!state.dayData) return;

  const hourData = state.dayData.hours[horaKey];
  if (!hourData) {
    content.innerHTML = '<p class="error-msg">This hour is not available in the cached data.</p>';
    markBar.classList.add('hidden');
    return;
  }

  content.innerHTML = hourData.html;
  document.getElementById('content-area').scrollTo(0, 0);

  updateHoraTabs(state.calendar, state.date);

  const alreadyRead = isRead(state.calendar, state.date, horaKey);
  const horaLabel = HORAS.find(h => h.key === horaKey)?.label || horaKey;
  if (alreadyRead) {
    markBar.classList.add('hidden');
  } else {
    markBar.classList.remove('hidden');
    document.getElementById('btn-mark-read').textContent = `✓ Mark ${horaLabel} as read`;
  }
}

function updateHoraTabs(cal, date) {
  document.querySelectorAll('.hora-tab').forEach(tab => {
    const key = tab.dataset.key;
    const read = isRead(cal, date, key);
    const active = key === state.hora;
    tab.className = `hora-tab${active ? ' active' : ''}${read ? ' read' : ''}`;
    tab.querySelector('.tab-dot').textContent = read ? '✓' : (active ? '●' : '·');
  });
  updatePillStrip(cal, date);
}

function updatePillStrip(cal, date) {
  const pill = document.getElementById('header-pill');
  pill.innerHTML = HORAS.map(h => {
    const read = isRead(cal, date, h.key);
    const active = h.key === state.hora;
    const dot = read ? '✓' : (active ? '●' : '·');
    return `<button class="pill-tab${active ? ' active' : ''}${read ? ' read' : ''}" data-key="${h.key}">${dot}${h.short}</button>`;
  }).join('');
  pill.querySelectorAll('.pill-tab').forEach(btn => {
    btn.addEventListener('click', () => {
      expandHeader();
      renderHora(btn.dataset.key);
    });
  });
}

async function updateNavButtons(cal, date) {
  const prevDate = addDaysISO(date, -1);
  const nextDate = addDaysISO(date, 1);
  const [prevData, nextData] = await Promise.all([getDay(cal, prevDate), getDay(cal, nextDate)]);
  document.getElementById('btn-prev-day').disabled = !prevData;
  document.getElementById('btn-next-day').disabled = !nextData;
}

// --- Header collapse ---
let lastScrollTop = 0;

function initHeaderCollapse() {
  const area = document.getElementById('content-area');
  area.addEventListener('scroll', () => {
    const cur = area.scrollTop;
    const header = document.getElementById('reading-header');
    if (cur > lastScrollTop && cur > 80) {
      header.classList.add('collapsed');
    } else if (cur < lastScrollTop - 10) {
      header.classList.remove('collapsed');
    }
    lastScrollTop = Math.max(0, cur);
  }, { passive: true });
}

function expandHeader() {
  document.getElementById('reading-header').classList.remove('collapsed');
}

// --- Storage screen ---
async function showStorage() {
  showScreen('storage');
  const container = document.getElementById('storage-content');
  container.innerHTML = '<p class="loading">Loading…</p>';

  const total = await countAllDays();
  let html = '';

  for (const cal of CALENDARS) {
    const dates = await listCachedDates(cal.label);
    if (dates.length === 0) continue;

    const first = new Date(dates[0] + 'T00:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
    const last  = new Date(dates[dates.length-1] + 'T00:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });

    html += `
      <div class="storage-cal">
        <div class="storage-cal-header">
          <strong>${cal.label}</strong>
          <span class="count">${dates.length} day${dates.length !== 1 ? 's' : ''}</span>
        </div>
        <div class="storage-range">${first} – ${last}</div>
        <div class="storage-actions">
          <label>Clear before</label>
          <input type="date" class="clear-before" data-cal="${cal.label}" value="${dates[0]}">
          <button class="btn-clear" data-cal="${cal.label}">Clear</button>
        </div>
      </div>`;
  }

  if (!html) {
    html = '<p class="empty-msg">No cached data yet.</p>';
  } else {
    html += `<p class="storage-note">~${(total * 8 * 12).toLocaleString()} KB estimated · Storage persists when installed to home screen</p>`;
  }

  container.innerHTML = html;

  container.querySelectorAll('.btn-clear').forEach(btn => {
    btn.addEventListener('click', async () => {
      const cal = btn.dataset.cal;
      const input = container.querySelector(`.clear-before[data-cal="${CSS.escape(cal)}"]`);
      const before = input?.value;
      if (!before) return;
      await deleteOldDays(cal, before);
      showToast('Old days cleared');
      showStorage();
    });
  });
}

// --- Settings sheet ---
function openSettings() {
  document.getElementById('settings-sheet').classList.remove('hidden');
  document.getElementById('sheet-backdrop').classList.remove('hidden');
}
function closeSettings() {
  document.getElementById('settings-sheet').classList.add('hidden');
  document.getElementById('sheet-backdrop').classList.add('hidden');
}

// --- Wire all events ---
function wireEvents() {
  // Download screen
  const daysSel = document.getElementById('days-count');
  function updateDownloadLabel() {
    document.getElementById('download-label').textContent = `⬇ Download ${daysSel.value} days`;
  }
  daysSel.addEventListener('change', updateDownloadLabel);
  document.getElementById('cal-picker').addEventListener('change', async () => {
    localStorage.setItem('do-last-calendar', selectedVersion());
    await refreshCachedSection();
  });

  document.getElementById('btn-download').addEventListener('click', async () => {
    const ver = selectedVersion();
    const start = document.getElementById('start-date').value || todayISO();
    const days = parseInt(daysSel.value, 10);
    const lang = document.querySelector('input[name="lang"]:checked').value;
    await downloadRange(ver, start, days, lang);
  });

  document.getElementById('btn-go-reading').addEventListener('click', async () => {
    const ver = selectedVersion();
    const cal = calLabel(ver);
    const today = todayISO();
    const todayData = await getDay(cal, today);
    const dates = await listCachedDates(cal);
    const date = todayData ? today : (dates[0] || today);
    await openReading(cal, ver, date);
  });

  document.getElementById('btn-storage').addEventListener('click', showStorage);

  // Reading screen
  document.getElementById('btn-back-to-home').addEventListener('click', () => showScreen('download'));

  document.getElementById('btn-prev-day').addEventListener('click', async () => {
    const prev = addDaysISO(state.date, -1);
    state.date = prev;
    lastScrollTop = 0;
    await loadAndRender(state.calendar, prev);
  });
  document.getElementById('btn-next-day').addEventListener('click', async () => {
    const next = addDaysISO(state.date, 1);
    state.date = next;
    lastScrollTop = 0;
    await loadAndRender(state.calendar, next);
  });

  // Tap date label → date picker modal
  document.getElementById('btn-date').addEventListener('click', () => {
    document.getElementById('modal-date-input').value = state.date;
    document.getElementById('date-picker-modal').classList.remove('hidden');
  });
  document.getElementById('btn-date-cancel').addEventListener('click', () => {
    document.getElementById('date-picker-modal').classList.add('hidden');
  });
  document.getElementById('btn-date-go').addEventListener('click', async () => {
    const d = document.getElementById('modal-date-input').value;
    if (d) {
      document.getElementById('date-picker-modal').classList.add('hidden');
      state.date = d;
      lastScrollTop = 0;
      await loadAndRender(state.calendar, d);
    }
  });

  // Hora tabs
  document.querySelectorAll('.hora-tab').forEach(tab => {
    tab.addEventListener('click', () => renderHora(tab.dataset.key));
  });

  // Mark as read
  document.getElementById('btn-mark-read').addEventListener('click', () => {
    markReadLocal(state.calendar, state.date, state.hora);
    const label = HORAS.find(h => h.key === state.hora)?.label || state.hora;
    showToast(`✓ ${label} marked as read`);
    updateHoraTabs(state.calendar, state.date);
    document.getElementById('mark-read-bar').classList.add('hidden');
  });

  // Settings
  document.getElementById('btn-settings').addEventListener('click', openSettings);
  document.getElementById('btn-close-settings').addEventListener('click', closeSettings);
  document.getElementById('sheet-backdrop').addEventListener('click', closeSettings);

  document.getElementById('btn-font-up').addEventListener('click', () => {
    fontSize = parseFloat((fontSize + 0.1).toFixed(1));
    applyFontSize();
  });
  document.getElementById('btn-font-down').addEventListener('click', () => {
    fontSize = parseFloat((fontSize - 0.1).toFixed(1));
    applyFontSize();
  });

  document.querySelectorAll('input[name="theme"]').forEach(r => {
    r.addEventListener('change', () => { theme = r.value; applyTheme(); });
  });

  // Storage screen
  document.getElementById('btn-back-from-storage').addEventListener('click', () => showScreen('download'));

  // Online/offline
  window.addEventListener('online', updateStatusDots);
  window.addEventListener('offline', updateStatusDots);
}

// --- Init ---
async function init() {
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('/pwa/sw.js', { scope: '/pwa/' })
      .catch(e => console.warn('SW:', e));
  }

  applyFontSize();
  applyTheme();
  updateStatusDots();

  // Populate calendar picker
  const picker = document.getElementById('cal-picker');
  picker.innerHTML = CALENDARS.map(c => `<option value="${c.version}">${c.label}</option>`).join('');
  const savedCal = localStorage.getItem('do-last-calendar');
  if (savedCal && CALENDARS.find(c => c.version === savedCal)) picker.value = savedCal;

  document.getElementById('start-date').value = todayISO();
  document.getElementById('download-label').textContent =
    `⬇ Download ${document.getElementById('days-count').value} days`;

  wireEvents();
  initHeaderCollapse();

  await refreshCachedSection();
  showScreen('download');
}

document.addEventListener('DOMContentLoaded', init);
