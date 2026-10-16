import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Empty, Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { createClient } from "@/lib/supabase/server";
import { stagesAndSubs } from "@/lib/stages";
import { JourneyEditor, type JourneyFull } from "./JourneyEditor";

export const metadata: Metadata = { title: "Journey" };

/** One journey (spec B9.4): the draft, its published versions, live counts on every step, test runs. */
export default async function JourneyPage({ params }: { params: Promise<{ id: string }> }) {
  const me = await requireUser("workspace", "/w/nurture");
  if (me.role !== "admin" && me.role !== "marketing") return <Page title="Journey"><Empty>Journeys are for Marketing and the Admin.</Empty></Page>;
  const id = Number((await params).id);
  if (!Number.isInteger(id) || id <= 0) notFound();
  const supabase = await createClient();
  const { data: j } = await supabase.from("journeys").select("*").eq("id", id).maybeSingle();
  if (!j) notFound();
  try {
    const [stats, { data: versions }, { data: wa }, { data: em }, { data: segs }, { data: others }, { stages }] = await Promise.all([
      rpc<{ at_step: Record<string, number>; entered: number; running: number; completed: number; exits: Record<string, number>; blocked: Record<string, number>; re_engaged: number; enrolled: number; sent: number; test_runs: number; wa_cost?: number; emails?: number }>("journey_stats", { p_id: id }),
      supabase.from("journey_versions").select("version, published_at, steps").eq("journey_id", id).order("version", { ascending: false }),
      supabase.from("wa_templates").select("name, status").eq("audience", "marketing").is("archived_at", null).order("name"),
      supabase.from("email_templates").select("name").is("archived_at", null).order("name"),
      supabase.from("segments").select("id, name").is("archived_at", null).order("name"),
      supabase.from("journeys").select("key, name").neq("id", id).neq("status", "archived").order("name"),
      stagesAndSubs(),
    ]);
    return (
      <JourneyEditor j={j as JourneyFull} stats={stats} versions={(versions ?? []) as { version: number; published_at: string; steps: unknown[] }[]} admin={me.role === "admin"} stages={stages}
        templates={{ whatsapp: (wa ?? []).map((t) => ({ name: t.name, status: t.status })), email: (em ?? []).map((t) => ({ name: t.name, status: "ready" })) }}
        segments={(segs ?? []) as { id: number; name: string }[]} journeys={(others ?? []) as { key: string; name: string }[]} />
    );
  } catch (e) {
    return <Page title={j.name}><SetupError error={e} /></Page>;
  }
}
