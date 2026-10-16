import type { Metadata } from "next";
import { PipelineView, type PipelineParams } from "@/components/lead/PipelineView";
import { requireUser } from "@/lib/auth";

export const metadata: Metadata = { title: "Pipeline" };

/** My active leads by stage (the sales head: the team's, by counsellor). Drag a card or use Move on it. */
export default async function PipelinePage({ searchParams }: { searchParams: Promise<PipelineParams> }) {
  const me = await requireUser("sales", "/s/pipeline");
  return <PipelineView me={me} base="/s/pipeline" leadBase="/s/leads" sp={await searchParams} />;
}
