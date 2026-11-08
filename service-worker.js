const CACHE_NAME = "bsnu-portal-v30";
const APP_SHELL = [
  "./",
  "./index.html",
  "./admin.html",
  "./manifest.webmanifest",
  "./admin-manifest.webmanifest",
  "./admin-icon.svg",
  "./icon.svg",
  "./service-worker.js"
];

// Cache only public front-end libraries. Never cache Supabase/auth/API requests.
const CDN_HOSTS = new Set([
  "cdn.tailwindcss.com",
  "unpkg.com",
  "cdn.jsdelivr.net",
  "fonts.googleapis.com",
  "fonts.gstatic.com",
  "cdnjs.cloudflare.com"
]);

const CDN_PRECACHE = [
  "https://cdn.tailwindcss.com",
  "https://unpkg.com/react@18.3.1/umd/react.production.min.js",
  "https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js",
  "https://unpkg.com/@babel/standalone/babel.min.js",
  "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2",
  "https://fonts.googleapis.com/css2?family=Cairo:wght@300;400;500;600;700;800;900&display=swap",
  "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js",
  "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js"
].map((url) => new Request(url, { mode: "no-cors" }));

async function precachePublicLibraries(cache) {
  await Promise.all(CDN_PRECACHE.map(async (request) => {
    try {
      const response = await fetch(request);
      if (response.ok || response.type === "opaque") {
        await cache.put(request, response);
      }
    } catch (_) {
      // A failed optional CDN request must not prevent the app shell from installing.
    }
  }));
}

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(async (cache) => {
        await cache.addAll(APP_SHELL);
        await precachePublicLibraries(cache);
      })
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("message", (event) => {
  if (event.data?.type === "CACHE_OFFLINE_SHELL") {
    event.waitUntil((async () => {
      const cache = await caches.open(CACHE_NAME);
      await cache.addAll(APP_SHELL);
      await precachePublicLibraries(cache);
      event.source?.postMessage({ type: "OFFLINE_SHELL_READY" });
    })());
  }
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((key) => key.startsWith("bsnu-portal-") && key !== CACHE_NAME)
          .map((key) => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});

async function saveResponse(cache, request, response) {
  if (response && (response.ok || response.type === "opaque")) {
    try { await cache.put(request, response.clone()); } catch (_) {}
  }
  return response;
}

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  const sameOrigin = url.origin === self.location.origin;

  // App pages: network first, then the saved app shell when offline.
  if (sameOrigin && request.mode === "navigate") {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE_NAME);
      try {
        const response = await fetch(request);
        if (response.ok) await saveResponse(cache, request, response);
        return response;
      } catch (_) {
        return (await cache.match(request)) ||
          (url.pathname.endsWith("/admin.html") && await cache.match("./admin.html")) ||
          (await cache.match("./index.html")) ||
          Response.error();
      }
    })());
    return;
  }

  // Same-origin static assets: cache first, then network and save.
  if (sameOrigin) {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE_NAME);
      const cached = await cache.match(request);
      if (cached) return cached;
      try {
        return await saveResponse(cache, request, await fetch(request));
      } catch (_) {
        return Response.error();
      }
    })());
    return;
  }

  // Cache public CDN scripts/styles/fonts after first successful online visit.
  if (CDN_HOSTS.has(url.hostname) &&
      ["script", "style", "font"].includes(request.destination)) {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE_NAME);
      try {
        const response = await fetch(request);
        return await saveResponse(cache, request, response);
      } catch (_) {
        return (await cache.match(request)) || Response.error();
      }
    })());
  }
});
