const DB_NAME = 'do-offline';
const DB_VERSION = 1;
const DAYS_STORE = 'days';
const META_STORE = 'meta';

function openDB() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = e => {
      const db = e.target.result;
      if (!db.objectStoreNames.contains(DAYS_STORE)) {
        const store = db.createObjectStore(DAYS_STORE, { keyPath: 'key' });
        store.createIndex('calendar', 'calendar', { unique: false });
        store.createIndex('date', 'date', { unique: false });
      }
      if (!db.objectStoreNames.contains(META_STORE)) {
        db.createObjectStore(META_STORE, { keyPath: 'key' });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function saveDays(calendar, days) {
  const db = await openDB();
  const tx = db.transaction(DAYS_STORE, 'readwrite');
  const store = tx.objectStore(DAYS_STORE);
  for (const day of days) {
    store.put({ key: `${calendar}_${day.date}`, calendar, date: day.date, data: day });
  }
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

async function getDay(calendar, date) {
  const db = await openDB();
  const tx = db.transaction(DAYS_STORE, 'readonly');
  return new Promise((resolve, reject) => {
    const req = tx.objectStore(DAYS_STORE).get(`${calendar}_${date}`);
    req.onsuccess = () => resolve(req.result ? req.result.data : null);
    req.onerror = () => reject(req.error);
  });
}

async function listCachedDates(calendar) {
  const db = await openDB();
  const tx = db.transaction(DAYS_STORE, 'readonly');
  return new Promise((resolve, reject) => {
    const dates = [];
    const req = tx.objectStore(DAYS_STORE).index('calendar').openCursor(IDBKeyRange.only(calendar));
    req.onsuccess = e => {
      const cursor = e.target.result;
      if (cursor) { dates.push(cursor.value.date); cursor.continue(); }
      else resolve(dates.sort());
    };
    req.onerror = () => reject(req.error);
  });
}

async function deleteOldDays(calendar, beforeDate) {
  const db = await openDB();
  const tx = db.transaction(DAYS_STORE, 'readwrite');
  return new Promise((resolve, reject) => {
    const req = tx.objectStore(DAYS_STORE).index('calendar').openCursor(IDBKeyRange.only(calendar));
    req.onsuccess = e => {
      const cursor = e.target.result;
      if (cursor) {
        if (cursor.value.date < beforeDate) cursor.delete();
        cursor.continue();
      } else resolve();
    };
    req.onerror = () => reject(req.error);
  });
}

async function countAllDays() {
  const db = await openDB();
  const tx = db.transaction(DAYS_STORE, 'readonly');
  return new Promise((resolve, reject) => {
    const req = tx.objectStore(DAYS_STORE).count();
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}
