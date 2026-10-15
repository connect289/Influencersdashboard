import { revalidatePath } from "next/cache";
import { cookies } from "next/headers";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { assertUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { gmailTokenKey, googleOAuthClient } from "@/lib/env";
import { when } from "@/lib/format";
import { googleSa } from "@/lib/gmail";
import { FLASH, FLASH_COOKIE, tokenAad, unsealToken } from "@/lib/gmail-oauth";
import { adminClient } from "@/lib/supabase/admin";

type Connection = { provider: string; account_email: string; status: "connected" | "revoked" | "error" | "disconnected"; scopes: string[]; last_ok_at: string | null; last_error: string | null; connected_at: string };

const STATUS: Record<Connection["status"], [string, string]> = {
  connected: ["Connected", "ok"],
  error: ["Last send failed", "risk"],
  revoked: ["Access removed in Google", "breach"],
  disconnected: ["Not connected", "line"],
};

function ready(): boolean {
  try { return !!googleOAuthClient() && !!gmailTokenKey(); } catch { return false; }
}

/** Disconnect: Google's grant is given back (best effort), then b2c.connection_disconnect forgets the sealed token. */
async function disconnectGmail() {
  "use server";
  const me = await assertUser();
  try {
    const key = gmailTokenKey();
    const { data: sealed } = await adminClient().rpc("connection_token", { p_user: me.user_id, p_provider: "gmail" });
    if (key && typeof sealed === "string" && sealed) {
      const token = unsealToken(sealed, key, tokenAad(me.user_id!));
      await fetch("https://oauth2.googleapis.com/revoke", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ token }), signal: AbortSignal.timeout(10_000) });
    }
  } catch (e) {
    console.warn("[gmail] revoke at Google failed; the connection is removed anyway:", e instanceof Error ? e.message : String(e));
  }
  await rpc("connection_disconnect", { p_provider: "gmail" });
  revalidatePath("/s/me");
}

/**
 * "Connect my Gmail" on Me (spec B17 personal connectors, D6): the person's own mailbox by OAuth, its status from
 * b2c.my_connections() (a revocation in Google shows here after the next send), and Connect, Reconnect or Disconnect.
 */
export async function GmailConnection() {
  const [conns, flashCode] = await Promise.all([
    rpc<Connection[]>("my_connections").catch(() => null),
    cookies().then((c) => c.get(FLASH_COOKIE)?.value ?? null),
  ]);
  const gmail = conns?.find((c) => c.provider === "gmail") ?? null;
  const live = gmail && gmail.status !== "disconnected";
  const [label, tone] = STATUS[gmail?.status ?? "disconnected"];
  const flash = flashCode ? FLASH[flashCode] ?? null : null;
  const canConnect = ready();
  const delegation = !!googleSa();
  return (
    <section className="panel" id="connections">
      <header><h3>My Gmail</h3><span className={`chip ${tone}`}>{label}</span></header>
      <div className="body stack" style={{ gap: 8 }}>
        {flash && <div className={`banner ${flashCode === "connected" ? "info" : "danger"}`} role="status">{flash}</div>}
        {conns === null && <p className="small muted">Your connection could not be read just now.</p>}
        {live && (
          <dl className="kv small">
            <dt>Mailbox</dt><dd className="mono">{gmail.account_email}</dd>
            <dt>Connected</dt><dd>{when(gmail.connected_at)}</dd>
            <dt>Last good send</dt><dd>{gmail.last_ok_at ? when(gmail.last_ok_at) : "none yet"}</dd>
            {gmail.last_error && <><dt>Last error</dt><dd style={{ color: "var(--red)" }}>{gmail.last_error}</dd></>}
          </dl>
        )}
        {gmail?.status === "revoked" && <p className="small">Spark can no longer send from your mailbox: someone removed its access in Google. Reconnect to send from your own Gmail again.</p>}
        <div className="row" style={{ gap: 8, flexWrap: "wrap" }}>
          {canConnect && (
            <a className={`btn sm ${live && gmail.status === "connected" ? "ghost" : "primary"}`} href="/auth/google/gmail">
              {live ? "Reconnect Gmail" : "Connect my Gmail"}
            </a>
          )}
          {live && (
            <form action={disconnectGmail}>
              <SubmitButton className="btn quiet sm" pendingLabel="Disconnecting…">Disconnect</SubmitButton>
            </form>
          )}
        </div>
        {!canConnect && <p className="note">Connecting your own Gmail is not set up yet (the Admin adds the Google OAuth client and the token key).</p>}
        <p className="note">
          Emails you write to students go from your own @eduwit.in mailbox{live ? "" : delegation ? ". Until you connect, Spark sends them through the company's Google Workspace delegation" : ". Until you connect, they cannot be sent as you"}.
          Spark asks Google only to send and read mail; the access is stored encrypted and you can disconnect at any time.
        </p>
      </div>
    </section>
  );
}
