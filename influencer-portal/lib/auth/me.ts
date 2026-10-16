import { z } from "zod";
import { isStaffRole, permissionsFor, type Permission, type StaffAccess, type StaffRole } from "@/lib/auth/permissions";

/** Shape of inf.me(). Parsed, never trusted blindly. */
export const meSchema = z.object({
  signed_in: z.boolean(),
  user_id: z.uuid().optional(),
  email: z.string().nullable().optional(),
  kind: z.enum(["staff", "creator", "none"]).optional(),
  session: z
    .object({ registered: z.boolean(), verified: z.boolean(), revoked: z.boolean(), verified_via: z.string().nullable() })
    .nullable()
    .optional(),
  staff: z
    .object({
      full_name: z.string(),
      status: z.enum(["active", "suspended"]),
      is_signatory: z.boolean(),
      roles: z.array(z.string()),
    })
    .nullable()
    .optional(),
  creator: z
    .object({
      id: z.uuid(),
      display_name: z.string(),
      handle: z.string(),
      status: z.string(),
      is_blocked: z.boolean(),
      is_test: z.boolean(),
    })
    .nullable()
    .optional(),
});
export type Me = z.infer<typeof meSchema>;

export interface StaffMe {
  userId: string;
  email: string;
  fullName: string;
  roles: StaffRole[];
  isSignatory: boolean;
  access: StaffAccess;
  permissions: Set<Permission>;
}

export function toStaffMe(me: Me): StaffMe | null {
  if (me.kind !== "staff" || !me.staff || !me.user_id || me.staff.status !== "active") return null;
  const roles = me.staff.roles.filter(isStaffRole);
  const access: StaffAccess = { roles, isSignatory: me.staff.is_signatory };
  return {
    userId: me.user_id,
    email: me.email ?? "",
    fullName: me.staff.full_name,
    roles,
    isSignatory: me.staff.is_signatory,
    access,
    permissions: permissionsFor(access),
  };
}

export interface CreatorMe {
  userId: string;
  email: string;
  creatorId: string;
  displayName: string;
  handle: string;
  status: string;
  isTest: boolean;
}

export function toCreatorMe(me: Me): CreatorMe | null {
  if (me.kind !== "creator" || !me.creator || !me.user_id || me.creator.is_blocked) return null;
  if (["blocked", "archived"].includes(me.creator.status)) return null;
  return {
    userId: me.user_id,
    email: me.email ?? "",
    creatorId: me.creator.id,
    displayName: me.creator.display_name,
    handle: me.creator.handle,
    status: me.creator.status,
    isTest: me.creator.is_test,
  };
}

/** Where a signed-in person lands. */
export function homeFor(me: Me): string {
  if (me.kind === "staff") return "/admin";
  if (me.kind === "creator") return "/creator";
  return "/no-access";
}
