const CACHE_NAME = "dqor-shell-v2";
const RUNTIME_CACHE = "dqor-runtime-v2";
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
      .then((keys) => Promise.all(keys.filter((key) => key.startsWith("dqor-") && !keep.includes(key)).map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

// Navigations can contain session-specific data even at a public URL. Never
// persist HTML. Only fingerprinted/static asset paths qualify for runtime cache;
// private Active Storage images and organizer/account routes remain network-only.
const CACHEABLE_DESTINATIONS = ["style", "script", "image", "font"];
const isStaticAsset = (url) => /^\/(assets|dqor)\//.test(url.pathname) || PRECACHE_URLS.includes(url.pathname);
const mayCache = (response) => response.ok && !response.redirected &&
  !/(?:private|no-store|no-cache)/i.test(response.headers.get("Cache-Control") || "");

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === "navigate") {
    event.respondWith(fetch(request).catch(() => caches.match(OFFLINE_URL)));
    return;
  }

  if (CACHEABLE_DESTINATIONS.includes(request.destination) && isStaticAsset(url)) {
    event.respondWith(
      fetch(request).then(async (response) => {
        const cache = await caches.open(RUNTIME_CACHE);
        if (mayCache(response)) await cache.put(request, response.clone());
        else await cache.delete(request);
        return response;
      }).catch(() => caches.match(request))
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
