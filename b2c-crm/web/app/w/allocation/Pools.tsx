"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Plus } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { poolSave } from "../actions";

export type Pool = { id: number; name: string; description: string | null; members: { user_id: string; weight: number; position: number }[] };
type Person = { user_id: string; name: string; role: string };

/** Pools (spec B7.2): named groups a rule picks from, each member with a weight for weighted round robin. */
export function Pools({ pools, people, admin }: { pools: Pool[]; people: Person[]; admin: boolean }) {
  const [edit, setEdit] = useState<Pool | "new" | null>(null);
  const name = (id: string) => people.find((p) => p.user_id === id)?.name ?? "—";
  return (
    <div className="stack">
      <div className="row between">
        <p className="note">A rule without a pool picks from everyone who takes leads.</p>
        {admin && <button type="button" className="btn primary sm" onClick={() => setEdit("new")}><Plus className="icon s" aria-hidden />New pool</button>}
      </div>
      <div className="grid g3">
        {pools.length === 0 && <p className="note">No pools yet.</p>}
        {pools.map((p) => (
          <div key={p.id} className="card pad stack" style={{ gap: 6 }}>
            <div className="row between"><b>{p.name}</b>{admin && <button type="button" className="btn quiet sm" onClick={() => setEdit(p)}>Edit</button>}</div>
            {p.description && <span className="small muted">{p.description}</span>}
            <span className="small">{p.members.length === 0 ? "No members" : p.members.map((m) => `${name(m.user_id)}${m.weight > 1 ? ` ×${m.weight}` : ""}`).join(" · ")}</span>
          </div>
        ))}
      </div>
      {edit && <PoolSheet pool={edit === "new" ? null : edit} people={people} onClose={() => setEdit(null)} />}
    </div>
  );
}

function PoolSheet({ pool, people, onClose }: { pool: Pool | null; people: Person[]; onClose: () => void }) {
  const router = useRouter();
  const [name, setName] = useState(pool?.name ?? "");
  const [desc, setDesc] = useState(pool?.description ?? "");
  const [weights, setWeights] = useState<Record<string, number>>(() => Object.fromEntries((pool?.members ?? []).map((m) => [m.user_id, m.weight])));
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const eligible = people.filter((p) => p.role !== "marketing");
  const save = () => start(async () => {
    const members = Object.entries(weights).filter(([, w]) => w > 0).map(([user_id, weight]) => ({ user_id, weight }));
    const r = await poolSave({ id: pool?.id ?? null, name, description: desc || null, members });
    if (!r.ok) return setError(r.error);
    toast.success(r.notice ?? "Saved.");
    onClose();
    router.refresh();
  });
  return (
    <Sheet title={pool ? `Edit pool: ${pool.name}` : "New pool"} onClose={onClose}>
      <label className="field"><span>Name</span><input className="input" value={name} onChange={(e) => setName(e.target.value)} maxLength={80} /></label>
      <label className="field"><span>What it is for</span><input className="input" value={desc} onChange={(e) => setDesc(e.target.value)} maxLength={200} /></label>
      <div className="field">
        <span>Members and weights (0 = not in the pool)</span>
        <div className="stack" style={{ gap: 6 }}>
          {eligible.map((p) => (
            <label key={p.user_id} className="row between">
              <span>{p.name}</span>
              <input className="input num" type="number" min={0} max={10} style={{ width: 80 }} value={weights[p.user_id] ?? 0}
                onChange={(e) => setWeights({ ...weights, [p.user_id]: Math.max(0, Math.min(10, Number(e.target.value))) })} aria-label={`Weight for ${p.name}`} />
            </label>
          ))}
        </div>
      </div>
      {error && <p className="error" role="alert">{error}</p>}
      <button type="button" className="btn primary block" disabled={busy || name.trim().length < 2} onClick={save}>{busy ? "Saving…" : "Save pool"}</button>
    </Sheet>
  );
}
