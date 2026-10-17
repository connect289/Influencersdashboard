import { Suspense } from "react";
import { AdminShell, Card } from "@/components/admin/AdminShell";
import { SettingForm } from "@/components/admin/SettingForm";
import { requireAdmin, hasRole } from "@/lib/server/admin";
import { rpc } from "@/lib/server/db";
import { parseSettings } from "@/lib/settings";

export const metadata = { title: "Flags and settings" };

async function Settings() {
  const s = await requireAdmin("viewer");
  const v = parseSettings(await rpc<Record<string, unknown>>("web_settings_all"));
  const editor = hasRole(s, "content_editor");
  const admin = hasRole(s, "super_admin");
  return (
    <AdminShell session={s} title="Flags and settings">
      <Card title="Feature flags (super admin)">
        <SettingForm name="web_advisor_enabled" label="Witty on the website" kind="bool" value={v.web_advisor_enabled} disabled={!admin} help="Off: the hero shows search, the guided finder and free counselling. Turn on only after A-AGENT-1 and S-14 (docs/APPROVALS_NEEDED.md)." />
        <SettingForm name="push_unverified_gate_leads" label="Push unverified gate attempts as leads" kind="bool" value={v.push_unverified_gate_leads} disabled={!admin} help="Off by default (spec 7.2). Attempts with a junk score of 50 or more are never pushed." />
        <SettingForm name="push_unverified_after_minutes" label="…after this many minutes" kind="number" value={v.push_unverified_after_minutes} disabled={!admin} />
        <SettingForm name="require_phone_otp" label="Require phone OTP" kind="bool" value={v.require_phone_otp} disabled help="Needs a phone OTP provider first (S-25)." />
        <SettingForm name="document_upload_enabled" label="Document upload in the application form" kind="bool" value={v.document_upload_enabled} disabled help="Not built in v1 (D-054)." />
      </Card>
      <Card title="Site">
        <SettingForm name="announcement" label="Announcement bar" kind="json" value={v.announcement} disabled={!editor} help='{"text": "Admissions open for January", "href": "/programmes", "tone": "info"} — or null to hide.' />
        <SettingForm name="sections" label="Homepage sections on/off" kind="json" value={v.sections} disabled={!editor} help='{"faq": true, "testimonials": false, …}' />
        <SettingForm name="counsellor_whatsapp" label="Counsellor WhatsApp number" kind="text" value={v.counsellor_whatsapp} disabled={!editor} />
        <SettingForm name="counsellor_phone" label="Counsellor phone number" kind="text" value={v.counsellor_phone} disabled={!editor} />
        <SettingForm name="application_form" label="Application form fields" kind="json" value={v.application_form} disabled={!editor} help='{"hidden": ["board", "industry"], "optional": ["score"]}. Configurable: stream, score, yearOfPassing, board, role, industry, goal, why, intake, budget, emi, city, state, bestTime, questions. Contact details and consent are always shown.' />
        <SettingForm name="business_hours" label="Opening hours (local SEO)" kind="json" value={v.business_hours} disabled={!editor} help='["Mo-Sa 10:00-19:00"] — shown in LocalBusiness structured data; null hides them.' />
        <SettingForm name="default_theme" label="Default theme" kind="text" value={v.default_theme} disabled={!editor} help="system, dark or light" />
      </Card>
    </AdminShell>
  );
}

export default function SettingsPage() {
  return (
    <Suspense fallback={<div className="skeleton m-8 h-40" />}>
      <Settings />
    </Suspense>
  );
}
