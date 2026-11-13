import { createHash } from "node:crypto";

/**
 * The fingerprint of the functions Settings → Privileges showed for one schema (D-137): md5 of their names sorted
 * bytewise and joined with commas, as one.ui_privilege_ack_schema computes it (`order by fn collate "C"`), so the
 * acknowledgement covers exactly what the owner read. The names are ASCII signatures (`schema.fn(types)`), for which
 * JavaScript's default sort and collation C agree.
 */
export function privilegeListHash(fns: readonly string[]): string {
  return createHash("md5")
    .update([...fns].sort().join(","), "utf8")
    .digest("hex");
}
