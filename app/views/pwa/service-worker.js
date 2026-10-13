// Cordially service worker: makes the app installable and shows a friendly page when offline.
// Pages are always fetched from the network (guest lists change by the minute); only the offline
// fallback and static assets are cached.
const CACHE = "cordially-v1"
const OFFLINE_URL = "/offline.html"

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll([ OFFLINE_URL, "/icon.svg" ])))
  self.skipWaiting()
})

self.addEventListener("activate", (event) => {
  event.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))))
  self.clients.claim()
})

self.addEventListener("fetch", (event) => {
  const request = event.request
  if (request.method !== "GET") return
  if (request.mode === "navigate") {
    event.respondWith(fetch(request).catch(() => caches.match(OFFLINE_URL)))
  } else if (new URL(request.url).pathname.startsWith("/assets/")) {
    event.respondWith(caches.match(request).then((hit) => hit || fetch(request).then((response) => {
      const copy = response.clone()
      if (response.ok) caches.open(CACHE).then((cache) => cache.put(request, copy))
      return response
    })))
  }
})
