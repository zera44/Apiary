// Служебний скрипт адмінки: потрібен, щоб телефон дозволив її встановити.
// Кешує лише саму сторінку й іконки (щоб відкривалась без мережі); запити до
// Supabase (відгуки, книги) не кешуються ніколи.
const CACHE = 'vulyk-admin-v1';
const SHELL = ['./feedback.html', './manifest.webmanifest', './icon-192.png', './icon-512.png'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});
// Спершу мережа (щоб бачити свіжу сторінку), без мережі - збережена копія.
self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) return;
  e.respondWith(
    fetch(req).then((res) => {
      if (res.ok) { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(req, copy)); }
      return res;
    }).catch(() => caches.match(req)),
  );
});
