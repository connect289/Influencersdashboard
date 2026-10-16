import "server-only";
import { adminClient } from "@/lib/supabase/admin";

/**
 * Connector health for the Connectors page (spec B17, D5): after each batch of external calls the jobs report the
 * outcome to b2c.connector_report (last success, last error, figures such as WhatsApp's quality rating). Reporting
 * never throws: a failed report must not fail the job that made the calls. Dry runs make no external call and report
 * nothing.
 */
export type ConnectorKey = "b2b" | "whatsapp" | "gmail_system" | "gmail_marketing" | "claude" | "telephony" | "directory" | "calendar";

export async function reportConnector(key: ConnectorKey, ok: boolean, detail?: Record<string, unknown> | null, error?: string | null): Promise<void> {
  try {
    const { error: e } = await adminClient().rpc("connector_report", { p_key: key, p_ok: ok, p_detail: detail ?? null, p_error: ok ? null : (error ?? "failed").slice(0, 500) });
    if (e) console.warn(`[connector] ${key}: report failed`, e.message);
  } catch (e) {
    console.warn(`[connector] ${key}: report failed`, e instanceof Error ? e.message : String(e));
  }
}

/** Outcomes of one batch per connector, reported once at the end: a success and, if any call failed, the last error. */
export class ConnectorTally {
  private seen = new Map<ConnectorKey, { ok: number; failed: number; error: string | null; detail: Record<string, unknown> }>();

  add(key: ConnectorKey, ok: boolean, error?: string | null, detail?: Record<string, unknown>): void {
    const t = this.seen.get(key) ?? { ok: 0, failed: 0, error: null, detail: {} };
    if (ok) t.ok++;
    else { t.failed++; t.error = error ?? "failed"; }
    if (detail) Object.assign(t.detail, detail);
    this.seen.set(key, t);
  }

  async report(): Promise<void> {
    for (const [key, t] of this.seen) {
      const detail = { ...t.detail, last_batch: { ok: t.ok, failed: t.failed, at: new Date().toISOString() } };
      if (t.ok) await reportConnector(key, true, detail);
      if (t.failed) await reportConnector(key, false, t.ok ? null : detail, t.error);
    }
    this.seen.clear();
  }
}
