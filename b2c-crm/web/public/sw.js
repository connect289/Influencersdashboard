// Eduwit CRM service worker: shows reminders and alerts pushed by the server (spec B16). Nothing is cached.
self.addEventListener("push", (event) => {
  let d = {};
  try { d = event.data ? event.data.json() : {}; } catch { d = { title: "Eduwit CRM", body: event.data ? event.data.text() : "" }; }
  const link = typeof d.link === "string" && d.link.startsWith("/") && !d.link.startsWith("//") ? d.link : "/";
  event.waitUntil(self.registration.showNotification(d.title || "Eduwit CRM", {
    body: d.body || "", icon: "/logo.jpg", badge: "/logo.jpg", tag: d.tag || undefined, data: { link },
  }));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = new URL(event.notification.data && event.notification.data.link ? event.notification.data.link : "/", self.location.origin).href;
  event.waitUntil((async () => {
    const wins = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const w of wins) if (new URL(w.url).origin === self.location.origin) { await w.focus(); return w.navigate(url); }
    return self.clients.openWindow(url);
  })());
});
