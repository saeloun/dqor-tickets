const CACHE_NAME = "dqor-shell-v1";
const RUNTIME_CACHE = "dqor-runtime-v1";
const OFFLINE_URL = "/offline.html";
const PRECACHE_URLS = [OFFLINE_URL, "/icon.png", "/icon.svg"];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(PRECACHE_URLS)).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  const keep = [CACHE_NAME, RUNTIME_CACHE];
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((key) => !keep.includes(key)).map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

const CACHEABLE_DESTINATIONS = ["style", "script", "image", "font"];

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;
  if (new URL(request.url).origin !== self.location.origin) return;

  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request)
        .then((response) => {
          const copy = response.clone();
          caches.open(RUNTIME_CACHE).then((cache) => cache.put(request, copy));
          return response;
        })
        .catch(() => caches.match(request).then((cached) => cached || caches.match(OFFLINE_URL)))
    );
    return;
  }

  if (CACHEABLE_DESTINATIONS.includes(request.destination)) {
    event.respondWith(
      caches.open(RUNTIME_CACHE).then((cache) =>
        cache.match(request).then((cached) => {
          const network = fetch(request).then((response) => {
            cache.put(request, response.clone());
            return response;
          });
          if (cached) {
            network.catch(() => {});
            return cached;
          }
          return network;
        })
      )
    );
  }
});

self.addEventListener("push", (event) => {
  if (!event.data) return;

  const payload = event.data.json();
  event.waitUntil(self.registration.showNotification(payload.title, payload.options));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const path = (event.notification.data && event.notification.data.path) || "/";

  event.waitUntil(
    self.clients.matchAll({ type: "window" }).then((clientList) => {
      for (const client of clientList) {
        if (new URL(client.url).pathname === path && "focus" in client) return client.focus();
      }
      if (self.clients.openWindow) return self.clients.openWindow(path);
    })
  );
});
