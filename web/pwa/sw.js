const SHELL_CACHE = 'do-offline-shell-v2';
const SHELL_FILES = [
  '/pwa/index.html',
  '/pwa/app.js',
  '/pwa/db.js',
  '/pwa/styles.css',
  '/pwa/manifest.json',
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(SHELL_CACHE).then(cache => cache.addAll(SHELL_FILES))
  );
  self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== SHELL_CACHE).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);

  // Never intercept API or CGI calls — handled by app.js into IndexedDB
  if (url.pathname.includes('/cgi-bin/')) return;
  if (url.pathname.startsWith('/api/')) return;

  // App shell only: cache-first
  if (SHELL_FILES.includes(url.pathname)) {
    event.respondWith(
      caches.match(event.request).then(cached => cached || fetch(event.request))
    );
  }
});
