import "server-only";
import { gmailTokenKey, googleOAuthClient } from "@/lib/env";
import { sendWithToken, type GmailMessage } from "@/lib/gmail";
import { refreshAccess, tokenAad, unsealToken } from "@/lib/gmail-oauth";
import { adminClient } from "@/lib/supabase/admin";

type Sent = { ok: boolean; id?: string; error?: string };

/**
 * Sending as a person through their own Gmail connection (D6). One instance per job run: the access token is fetched once
 * per person and reused. `send` answers null when the person has no usable connection (or connecting is not set up), so
 * the caller falls back to the existing path (domain-wide delegation). A failure is recorded with b2c.connection_mark:
 * invalid_grant there marks the connection revoked and tells the person to reconnect. A success is recorded once a run.
 */
export class UserGmail {
  private tokens = new Map<string, { token: string } | { error: string } | null>();
  private markedOk = new Set<string>();

  constructor(private db = adminClient()) {}

  private async mark(userId: string, ok: boolean, error?: string | null) {
    if (ok && this.markedOk.has(userId)) return;
    const { error: e } = await this.db.rpc("connection_mark", { p_user: userId, p_provider: "gmail", p_ok: ok, p_error: ok ? null : (error ?? "failed").slice(0, 300) });
    if (e) console.warn("[gmail-user] connection_mark failed", e.message);
    else if (ok) this.markedOk.add(userId);
  }

  private async token(userId: string): Promise<{ token: string } | { error: string } | null> {
    if (this.tokens.has(userId)) return this.tokens.get(userId)!;
    const client = googleOAuthClient();
    let key: Buffer | null = null;
    try { key = gmailTokenKey(); } catch (e) { console.error("[gmail-user]", (e as Error).message); }
    let t: { token: string } | { error: string } | null = null;
    if (client && key) {
      const { data: sealed, error } = await this.db.rpc("connection_token", { p_user: userId, p_provider: "gmail" });
      if (error) console.warn("[gmail-user] connection_token failed", error.message);
      else if (typeof sealed === "string" && sealed) {
        let refresh: string | null = null;
        try { refresh = unsealToken(sealed, key, tokenAad(userId)); } catch {
          t = { error: "the stored Gmail token cannot be opened (the token key changed): reconnect Gmail" };
        }
        if (refresh) {
          const r = await refreshAccess({ ...client, refreshToken: refresh });
          t = r.ok ? { token: r.token } : { error: r.error };
        }
        if (t && "error" in t) await this.mark(userId, false, t.error);
      }
    }
    this.tokens.set(userId, t);
    return t;
  }

  async send(userId: string, m: GmailMessage): Promise<Sent | null> {
    const t = await this.token(userId);
    if (!t) return null;
    if ("error" in t) return { ok: false, error: t.error };
    const r = await sendWithToken(t.token, m);
    await this.mark(userId, r.ok, r.error);
    if (!r.ok && (r.status === 401 || r.status === 403)) this.tokens.set(userId, { error: r.error ?? "refused" }); // stop using it this run
    return { ok: r.ok, id: r.id, error: r.error };
  }
}
