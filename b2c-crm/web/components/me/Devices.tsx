import { revalidatePath } from "next/cache";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { assertUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { when } from "@/lib/format";
import { createClient } from "@/lib/supabase/server";

type Session = { session_id: string; method: string | null; signed_in_at: string; last_seen_at: string | null; user_agent: string | null; ip: string | null; current: boolean };
type Device = { id: string; label: string | null; created_at: string; expires_at: string; last_used_at: string | null };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** "Chrome on Android" from a user-agent string: enough to recognise one's own phone or laptop. */
export function deviceName(ua: string | null | undefined): string {
  if (!ua) return "Unknown browser";
  const browser = /Edg\//.test(ua) ? "Edge" : /OPR\//.test(ua) ? "Opera" : /SamsungBrowser/.test(ua) ? "Samsung Internet" : /Firefox\//.test(ua) ? "Firefox"
    : /Chrome\//.test(ua) ? "Chrome" : /Safari\//.test(ua) ? "Safari" : "Browser";
  const os = /Android/.test(ua) ? "Android" : /iPhone|iPad|iPod/.test(ua) ? "iPhone or iPad" : /Windows/.test(ua) ? "Windows" : /Mac OS X|Macintosh/.test(ua) ? "Mac"
    : /CrOS/.test(ua) ? "ChromeOS" : /Linux/.test(ua) ? "Linux" : "another system";
  return `${browser} on ${os}`;
}

async function signOutSession(form: FormData) {
  "use server";
  await assertUser();
  const id = String(form.get("session") ?? "");
  if (!UUID.test(id)) return;
  await rpc("session_revoke", { p_session: id, p_device: null, p_user: null });
  revalidatePath("/s/me");
}

async function forgetDevice(form: FormData) {
  "use server";
  await assertUser();
  const id = String(form.get("device") ?? "");
  if (!/^[0-9a-f]{16}$/.test(id)) return;
  await rpc("session_revoke", { p_session: null, p_device: id, p_user: null });
  revalidatePath("/s/me");
}

/** Every other session is signed out (b2c.session_revoke) and every trusted device forgotten; Supabase also ends the
 *  other sessions' refresh tokens, so they cannot sign back in silently. This browser stays signed in. */
async function signOutEverywhereElse() {
  "use server";
  await assertUser();
  await rpc("session_revoke", { p_session: null, p_device: null, p_user: null });
  const supabase = await createClient();
  const { error } = await supabase.auth.signOut({ scope: "others" });
  if (error) console.warn("[devices] Supabase could not end the other sessions; the CRM still refuses them:", error.message);
  revalidatePath("/s/me");
}

/**
 * Signed-in devices on Me (spec B3.2, E10): this person's sessions (browser, address, last seen) and trusted devices
 * (7 days without the emailed code), from b2c.my_devices(). A signed-out session is refused at its next request and
 * sent to sign in again.
 */
export async function Devices() {
  const d = await rpc<{ sessions: Session[]; devices: Device[] }>("my_devices", { p_user: null }).catch(() => null);
  const sessions = d?.sessions ?? [];
  const devices = d?.devices ?? [];
  const others = sessions.filter((s) => !s.current).length + devices.length;
  return (
    <section className="panel" id="devices">
      <header><h3>Signed-in devices</h3><span className="small muted">{sessions.length} {sessions.length === 1 ? "session" : "sessions"}</span></header>
      <div className="body stack" style={{ gap: 10 }}>
        {d === null && <p className="small muted">Your devices could not be read just now.</p>}
        <div className="list">
          {sessions.map((s) => (
            <div key={s.session_id} className="li">
              <span className="t ellipsis">{deviceName(s.user_agent)}{s.current && <> <span className="chip ok">This browser</span></>}</span>
              <span className="s">Signed in {when(s.signed_in_at)}{s.last_seen_at ? ` · last seen ${when(s.last_seen_at)}` : ""}{s.ip ? ` · ${s.ip}` : ""}{s.method === "trusted_device" ? " · trusted device" : ""}</span>
              {s.current ? (
                <form action="/auth/signout" method="post"><button type="submit" className="btn quiet sm">Sign out</button></form>
              ) : (
                <form action={signOutSession}>
                  <input type="hidden" name="session" value={s.session_id} />
                  <SubmitButton className="btn quiet sm" pendingLabel="Signing out…">Sign out</SubmitButton>
                </form>
              )}
            </div>
          ))}
        </div>
        {devices.length > 0 && (
          <>
            <h4 className="small muted" style={{ margin: 0 }}>Trusted devices (no emailed code until they expire)</h4>
            <div className="list">
              {devices.map((v) => (
                <div key={v.id} className="li">
                  <span className="t ellipsis">{deviceName(v.label)}</span>
                  <span className="s">Trusted {when(v.created_at)} · until {when(v.expires_at)}{v.last_used_at ? ` · last used ${when(v.last_used_at)}` : ""}</span>
                  <form action={forgetDevice}>
                    <input type="hidden" name="device" value={v.id} />
                    <SubmitButton className="btn quiet sm" pendingLabel="Forgetting…">Forget</SubmitButton>
                  </form>
                </div>
              ))}
            </div>
          </>
        )}
        {others > 0 && (
          <form action={signOutEverywhereElse}>
            <SubmitButton className="btn ghost sm" pendingLabel="Signing out…">Sign out everywhere else</SubmitButton>
          </form>
        )}
        <p className="note">If you see a device you do not recognise, sign it out and change your password, then tell the Admin.</p>
      </div>
    </section>
  );
}
