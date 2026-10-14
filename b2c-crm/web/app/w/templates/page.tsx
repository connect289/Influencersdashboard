import Link from "next/link";
import type { Metadata } from "next";
import { Empty, Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { when } from "@/lib/format";
import { createClient } from "@/lib/supabase/server";
import { EmailTemplateButton, WaTemplateButton, WaSubmitButton, type EmailTpl, type WaTpl } from "./TemplateEditors";

export const metadata: Metadata = { title: "Templates" };

const TABS = [["wa_marketing", "WhatsApp: marketing"], ["wa_sales", "WhatsApp: sales and system"], ["email_marketing", "Email: marketing"], ["email_sales", "Email: sales library"]] as const;
const STATUS_CHIP: Record<string, string> = { approved: "ok", submitted: "risk", draft: "line", rejected: "breach", paused: "risk", disabled: "breach" };

/** The Template page (spec B9.2a): who may create and edit each kind is enforced in the database too. */
export default async function TemplatesPage({ searchParams }: { searchParams: Promise<{ tab?: string }> }) {
  const me = await requireUser("workspace", "/w/templates");
  if (me.role !== "admin" && me.role !== "marketing") return <Page title="Templates"><Empty>Templates are for Marketing and the Admin.</Empty></Page>;
  const admin = me.role === "admin";
  const asked = (await searchParams).tab;
  const tab = TABS.some(([k]) => k === asked) ? asked! : "wa_marketing";
  const supabase = await createClient();
  let body: React.ReactNode;
  try {
    if (tab === "wa_marketing" || tab === "wa_sales") {
      const q = supabase.from("wa_templates").select("id, name, language, category, audience, usable_by_sales, purpose, body, variables, buttons, status, rejection_reason, tags, uses, version, archived_at, updated_at").order("name");
      const { data, error } = tab === "wa_marketing" ? await q.eq("audience", "marketing") : await q.in("audience", ["sales", "system"]);
      if (error) throw new Error(error.message);
      const rows = (data ?? []) as WaTpl[];
      const canEdit = tab === "wa_marketing" || admin;
      body = (
        <div className="stack">
          <div className="row between wrap">
            <p className="note">{tab === "wa_marketing" ? "For journeys and campaigns. Each needs Meta's approval before it can reach a student; a changed text goes back to draft." : "Counsellors open conversations with the sales templates; system templates send the assignment and consent messages. Only the Admin creates and changes them."}</p>
            {canEdit && <WaTemplateButton audience={tab === "wa_marketing" ? "marketing" : "sales"} admin={admin} />}
          </div>
          <div className="table-wrap"><table>
            <thead><tr><th>Template</th><th>Text</th><th>Meta</th><th className="right">Used</th><th /></tr></thead>
            <tbody>
              {rows.length === 0 && <tr><td colSpan={5} className="muted">None yet.</td></tr>}
              {rows.map((t) => (
                <tr key={t.id} style={{ opacity: t.archived_at ? 0.5 : 1 }}>
                  <td><b className="mono">{t.name}</b><div className="small muted">{t.language} · {t.category}{t.audience !== "marketing" ? ` · ${t.audience}${t.usable_by_sales ? " (usable by Sales)" : ""}` : ""}{t.purpose ? ` · ${t.purpose}` : ""}</div></td>
                  <td className="small" style={{ maxWidth: 380 }}>{t.body}{t.buttons?.length ? <div className="muted">Buttons: {t.buttons.map((b) => b.text).join(" · ")}</div> : null}</td>
                  <td><span className={`chip ${STATUS_CHIP[t.status] ?? "line"}`}>{t.status}</span>{t.rejection_reason && <div className="small error">{t.rejection_reason}</div>}</td>
                  <td className="right num">{t.uses}</td>
                  <td className="row" style={{ gap: 4 }}>{canEdit && <WaTemplateButton audience={t.audience} admin={admin} t={t} />}{canEdit && (t.status === "draft" || t.status === "rejected") && <WaSubmitButton id={t.id} />}</td>
                </tr>
              ))}
            </tbody>
          </table></div>
        </div>
      );
    } else if (tab === "email_marketing") {
      const { data, error } = await supabase.from("email_templates").select("id, name, language, subject, body, tags, version, uses, archived_at, updated_at").order("name");
      if (error) throw new Error(error.message);
      const rows = (data ?? []) as EmailTpl[];
      body = (
        <div className="stack">
          <div className="row between wrap"><p className="note">For journeys and campaigns. Merge fields: {"{{first_name}}"}, {"{{programme}}"}, {"{{university}}"}, {"{{city}}"}. Every email gets the unsubscribe footer and an &ldquo;I&apos;m interested, call me&rdquo; link.</p><EmailTemplateButton /></div>
          <div className="table-wrap"><table>
            <thead><tr><th>Template</th><th>Subject</th><th className="right">Used</th><th>Changed</th><th /></tr></thead>
            <tbody>
              {rows.length === 0 && <tr><td colSpan={5} className="muted">None yet.</td></tr>}
              {rows.map((t) => (
                <tr key={t.id} style={{ opacity: t.archived_at ? 0.5 : 1 }}>
                  <td><b>{t.name}</b><div className="small muted">{t.language} · v{t.version}{t.tags.length ? ` · ${t.tags.join(", ")}` : ""}</div></td>
                  <td className="small">{t.subject}</td><td className="right num">{t.uses}</td><td className="small">{when(t.updated_at)}</td>
                  <td><EmailTemplateButton t={t} /></td>
                </tr>
              ))}
            </tbody>
          </table></div>
        </div>
      );
    } else {
      const { data } = await supabase.from("sales_email_templates").select("id, name, category, subject, uses, recommended, hidden, owner_id, parent_id").is("deleted_at", null).order("uses", { ascending: false });
      body = (
        <div className="stack">
          <p className="note">Counsellors write and share these themselves (editing someone else&apos;s saves a copy). They are for one-to-one email only, never for journeys or campaigns. Counsellors manage them under <Link href="/s/me?tab=templates">Me → Email templates</Link>.</p>
          <div className="table-wrap"><table>
            <thead><tr><th>Template</th><th>Subject</th><th className="right">Used</th><th>Flags</th></tr></thead>
            <tbody>{(data ?? []).map((t) => <tr key={t.id}><td><b>{t.name}</b><div className="small muted">{t.category}{t.parent_id ? " · a copy" : ""}</div></td><td className="small">{t.subject}</td><td className="right num">{t.uses}</td><td className="small">{t.recommended ? "Recommended " : ""}{t.hidden ? "Hidden" : ""}</td></tr>)}</tbody>
          </table></div>
        </div>
      );
    }
  } catch (e) {
    body = <SetupError error={e} />;
  }
  return (
    <Page title="Templates" sub="WhatsApp and email, marketing and sales">
      <div className="tabs" role="tablist">
        {TABS.map(([k, n]) => (
          <Link key={k} href={`/w/templates?tab=${k}`} role="tab" aria-selected={tab === k}
            style={{ padding: "9px 12px", fontWeight: 600, textDecoration: "none", color: tab === k ? "var(--ink)" : "var(--muted)", borderBottom: `2px solid ${tab === k ? "var(--amber)" : "transparent"}`, whiteSpace: "nowrap" }}>{n}</Link>
        ))}
      </div>
      {body}
    </Page>
  );
}
