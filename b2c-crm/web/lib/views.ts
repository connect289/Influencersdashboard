import "server-only";
import { rpc, RpcError } from "@/lib/data";
import type { SavedView } from "@/lib/types";

/** The views a person may open on an interface (b2c.views_list): their own, the standard ones, those shared with their role, and their pinned default. */
export async function viewsFor(role: "sales" | "workspace"): Promise<{ views: SavedView[]; defaultId: number | null }> {
  const r = await rpc<{ default: number | null; views: SavedView[] }>("views_list", { p_role: role });
  return { views: (r.views ?? []).map((v) => ({ ...v, columns: Array.isArray(v.columns) ? v.columns : [] })), defaultId: r.default ?? null };
}

/**
 * The view to show: the one asked for (a pill, or a shared link ?view=), else the pinned default, else the first. A link
 * to a view not in the list is opened through b2c.view_get, which refuses one not shared with this person.
 */
export async function pickView(list: { views: SavedView[]; defaultId: number | null }, asked: string | undefined, fallback?: (v: SavedView[]) => SavedView | undefined):
  Promise<{ view: SavedView | undefined; refused: string | null }> {
  const id = Number(asked);
  const standing = () => list.views.find((v) => v.id === list.defaultId) ?? fallback?.(list.views) ?? list.views[0];
  if (asked && Number.isInteger(id) && id > 0) {
    const found = list.views.find((v) => v.id === id);
    if (found) return { view: found, refused: null };
    try {
      const v = await rpc<SavedView>("view_get", { p_id: id });
      return { view: { ...v, columns: Array.isArray(v.columns) ? v.columns : [] }, refused: null };
    } catch (e) {
      const msg = e instanceof RpcError || e instanceof Error ? e.message : "";
      return { view: standing(), refused: /not shared/i.test(msg) ? "This view is not shared with you. Ask its owner to share it with your role." : "This view could not be opened." };
    }
  }
  return { view: standing(), refused: null };
}
