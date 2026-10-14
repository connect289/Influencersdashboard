"use client";
import { useEffect, useState, useTransition } from "react";
import { Bell, BellOff } from "lucide-react";
import { toast } from "sonner";
import { pushSubscribe } from "@/app/push-actions";

function keyBytes(b64: string): Uint8Array<ArrayBuffer> {
  const s = atob((b64 + "=".repeat((4 - (b64.length % 4)) % 4)).replace(/-/g, "+").replace(/_/g, "/"));
  const out = new Uint8Array(new ArrayBuffer(s.length));
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
}

/** Reminders and alerts on this phone or laptop (spec B16, web push). Each device is switched on separately. */
export function PushToggle({ vapidKey }: { vapidKey: string | null }) {
  const [state, setState] = useState<"unsupported" | "off" | "on" | "blocked" | "loading">("loading");
  const [busy, start] = useTransition();

  useEffect(() => {
    if (!vapidKey || !("serviceWorker" in navigator) || !("PushManager" in window) || !("Notification" in window)) return setState("unsupported");
    if (Notification.permission === "denied") return setState("blocked");
    navigator.serviceWorker.register("/sw.js").then((reg) => reg.pushManager.getSubscription()).then((s) => setState(s ? "on" : "off")).catch(() => setState("unsupported"));
  }, [vapidKey]);

  function turnOn() {
    start(async () => {
      try {
        const reg = await navigator.serviceWorker.register("/sw.js");
        if ((await Notification.requestPermission()) !== "granted") return setState("blocked");
        const s = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(vapidKey!) });
        const r = await pushSubscribe(s.toJSON(), true);
        if (!r.ok) { await s.unsubscribe(); return void toast.error(r.error); }
        setState("on");
        toast.success(r.notice ?? "Alerts are on.");
      } catch (e) {
        toast.error(e instanceof Error ? e.message : "This browser could not turn alerts on.");
      }
    });
  }

  function turnOff() {
    start(async () => {
      const reg = await navigator.serviceWorker.getRegistration("/sw.js");
      const s = await reg?.pushManager.getSubscription();
      if (s) {
        await pushSubscribe(s.toJSON(), false);
        await s.unsubscribe();
      }
      setState("off");
      toast.success("Alerts are off for this device.");
    });
  }

  return (
    <section className="panel">
      <header><h3>Alerts on this device</h3></header>
      <div className="body small stack">
        <p className="muted">Follow-up reminders (10 minutes before), new leads and missed-call flags, as notifications on this phone or laptop.</p>
        {state === "unsupported" && <p className="note">{vapidKey ? "This browser cannot show alerts. On an iPhone, add the app to the home screen first (Share → Add to Home Screen)." : "Alerts are not set up yet (the Admin adds the push keys)."}</p>}
        {state === "blocked" && <p className="note">Notifications are blocked for this site. Allow them in the browser&apos;s site settings, then come back.</p>}
        {state === "off" && <button type="button" className="btn primary" onClick={turnOn} disabled={busy}><Bell className="icon s" aria-hidden />Turn alerts on</button>}
        {state === "on" && <button type="button" className="btn ghost" onClick={turnOff} disabled={busy}><BellOff className="icon s" aria-hidden />Turn alerts off on this device</button>}
      </div>
    </section>
  );
}
