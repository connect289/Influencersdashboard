import { fetchMe } from "@/lib/auth/guards";
import type { ContractDetail } from "@/lib/contracts/data";
import { signingChannels } from "@/lib/contracts/signing";
import type { ServerSupabase } from "@/lib/supabase/server";
import { SignPanel } from "./sign-panel";

/**
 * The sign panel when it's this person's turn: the creator (or their negotiating agency) once the contract is ready
 * to sign, the Authorised Signatory once the creator has signed. The database re-checks all of it when they sign.
 */
export async function SignSection({ c, supabase }: { c: ContractDetail; supabase: ServerSupabase }) {
  const role =
    c.side !== "eduwit" && c.status === "ready_to_sign"
      ? "creator"
      : c.side === "eduwit" && c.can_countersign && c.status === "signed_by_creator"
        ? "signatory"
        : null;
  if (!role || !c.current || !c.consent) return null;
  const me = await fetchMe(supabase);
  const channels = await signingChannels({
    email: me.email ?? null,
    creatorId: c.side === "creator" ? (me.creator?.id ?? null) : null,
  });
  return (
    <div className="mb-4">
      <SignPanel
        contractId={c.id}
        versionId={c.current.id}
        sha256={c.current.sha256}
        sections={c.current.content.sections.map((s) => ({ key: s.key, number: s.number, title: s.title }))}
        consent={c.consent}
        channels={channels.map((x) => x.channel)}
        role={role}
      />
    </div>
  );
}
