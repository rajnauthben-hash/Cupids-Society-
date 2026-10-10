/* Cupid's Society back office — service worker.
 *
 * Deliberately cautious about the panel itself. A cached admin page is how you
 * end up editing yesterday's build, so the HTML is always fetched from the
 * network first and the cached copy is only a fallback for being offline.
 * Icons and the manifest are served from cache because they never change
 * without a new version below. Supabase calls are never cached at all —
 * stale stock counts would be worse than no stock counts.
 */
const VERSION = 'cs-admin-v1';
const SHELL   = [
  './manifest.webmanifest',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/icon-512-maskable.png',
  './icons/apple-touch-icon.png',
];

self.addEventListener('install', function (e) {
  e.waitUntil(
    caches.open(VERSION)
      .then(function (c) { return c.addAll(SHELL); })
      .then(function () { return self.skipWaiting(); })
  );
});

self.addEventListener('activate', function (e) {
  e.waitUntil(
    caches.keys()
      .then(function (keys) {
        return Promise.all(keys
          .filter(function (k) { return k !== VERSION; })
          .map(function (k) { return caches.delete(k); }));
      })
      .then(function () { return self.clients.claim(); })
  );
});

self.addEventListener('message', function (e) {
  if (e.data && e.data.type === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('fetch', function (e) {
  const req = e.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);

  // Never touch the database or auth — always straight to the network.
  if (url.hostname.endsWith('supabase.co')) return;

  // The panel itself: network first, cache only as an offline fallback.
  const isPage = req.mode === 'navigate'
    || (req.destination === 'document')
    || url.pathname.endsWith('/admin/')
    || url.pathname.endsWith('/admin/index.html');

  if (isPage) {
    e.respondWith(
      fetch(req)
        .then(function (res) {
          const copy = res.clone();
          caches.open(VERSION).then(function (c) { c.put(req, copy); });
          return res;
        })
        .catch(function () {
          return caches.match(req).then(function (hit) {
            return hit || caches.match('./index.html') || Response.error();
          });
        })
    );
    return;
  }

  // Everything else same-origin (icons, manifest): cache first, refresh behind.
  if (url.origin === self.location.origin) {
    e.respondWith(
      caches.match(req).then(function (hit) {
        const net = fetch(req).then(function (res) {
          if (res && res.status === 200) {
            const copy = res.clone();
            caches.open(VERSION).then(function (c) { c.put(req, copy); });
          }
          return res;
        }).catch(function () { return hit; });
        return hit || net;
      })
    );
  }
});
