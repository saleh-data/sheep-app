const ROOT=self.registration.scope;
const CACHE='sheep-shell-v2-'+ROOT;
const offlineURL=new URL('offline.html',ROOT).href;
self.addEventListener('install',event=>{event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll([offlineURL,new URL('icon-192.png',ROOT).href])));self.skipWaiting();});
self.addEventListener('activate',event=>{event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>(k.startsWith('sheep-shell-')&&k.endsWith(ROOT)&&k!==CACHE)||(new URL(ROOT).pathname==='/'&&k==='sheep-shell-v1')).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));});
self.addEventListener('fetch',event=>{if(event.request.mode==='navigate'&&event.request.url.startsWith(ROOT)){event.respondWith(fetch(event.request).catch(()=>caches.match(offlineURL)));}});
