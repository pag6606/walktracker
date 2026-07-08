/* Service Worker — WalkTracker PWA v3.1
   Network-first para código (siempre busca updates), cache-first para assets estáticos. */
const CACHE = 'walktracker-v3.2';
const SHELL = [
  './',
  './index.html',
  './domain.js',
  './storage.js',
  './migration.js',
  './climate.js',
  './motivation.js',
  './runtime.js',
  './quotes.json',
  './manifest.webmanifest',
  './icons/icon-192.png',
  './icons/icon-512.png',
];

// Assets estáticos que no cambian (cache-first)
const STATIC_ASSETS = [
  './icons/icon-192.png',
  './icons/icon-512.png',
  './manifest.webmanifest',
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(SHELL))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);

  // Solo interceptar GET (no interferir con POST, etc.)
  if (e.request.method !== 'GET') return;

  // Assets estáticos: cache-first (nunca cambian)
  if (STATIC_ASSETS.some(a => url.pathname.endsWith(a.replace('./', '/')))) {
    e.respondWith(
      caches.match(e.request).then(cached => cached || fetch(e.request))
    );
    return;
  }

  // Código HTML/JS/JSON: network-first (siempre buscar versión nueva del server)
  e.respondWith(
    fetch(e.request)
      .then(response => {
        // Guardar versión fresca en cache
        if (response.ok) {
          const clone = response.clone();
          caches.open(CACHE).then(cache => cache.put(e.request, clone));
        }
        return response;
      })
      .catch(() => {
        // Si no hay red, usar cache (offline)
        return caches.match(e.request);
      })
  );
});