// Makes the site installable as an app (no browser address bar) and lets it
// open offline. Network-first: online you always get the latest files, and
// the last copy fetched is what's used when you're offline. Other sites
// (Supabase, Google fonts/search) and the big Bible data files, which the
// page keeps in its own IndexedDB cache, are left alone.
var CACHE = "journal-app-v1";
var SHELL = ["./", "index.html", "manifest.webmanifest", "icons/icon-192.png", "icons/icon-512.png"];

self.addEventListener("install", function (event) {
  event.waitUntil(
    caches.open(CACHE).then(function (cache) { return cache.addAll(SHELL); }).then(function () { return self.skipWaiting(); })
  );
});

self.addEventListener("activate", function (event) {
  event.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(keys.filter(function (k) { return k !== CACHE; }).map(function (k) { return caches.delete(k); }));
    }).then(function () { return self.clients.claim(); })
  );
});

self.addEventListener("fetch", function (event) {
  var request = event.request;
  if (request.method !== "GET") return;
  var url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  if (url.pathname.indexOf("/data/") !== -1 && url.pathname.indexOf("words-of-jesus") === -1) return;
  event.respondWith(
    fetch(request).then(function (response) {
      if (response && response.ok) {
        var copy = response.clone();
        caches.open(CACHE).then(function (cache) { cache.put(request, copy); });
      }
      return response;
    }).catch(function () {
      return caches.match(request).then(function (hit) {
        return hit || (request.mode === "navigate" ? caches.match("index.html") : undefined);
      });
    })
  );
});
