/* Service Worker — WalkTracker PWA v3.0
   Cache app shell + modules: cache-first for static assets. Offline-first. */
const CACHE = 'walktracker-v3';
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
  e.respondWith(
    caches.match(e.request).then((cached) => cached || fetch(e.request))
  );
});
