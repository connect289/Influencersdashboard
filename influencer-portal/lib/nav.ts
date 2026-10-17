// Navigation registries. Only modules that exist are listed (no placeholder screens); each later phase adds its
// entries. Items a role can't use are hidden (spec 4: hide, never just disable).
import type { Permission } from "@/lib/auth/permissions";

export const ICON_NAMES = [
  "home",
  "users",
  "settings",
  "scroll",
  "activity",
  "user",
  "shield",
  "idCard",
  "badgeCheck",
  "building",
  "contact",
  "checklist",
  "megaphone",
  "inbox",
  "fileText",
  "handshake",
  "signature",
  "help",
] as const;
export type IconName = (typeof ICON_NAMES)[number];

export interface StaffNavItem {
  href: string;
  labelKey: string;
  icon: IconName;
  /** Any one of these permissions shows the item; none listed = every staff member. */
  anyOf?: Permission[];
}

export const STAFF_NAV: StaffNavItem[] = [
  { href: "/admin", labelKey: "nav.admin.overview", icon: "home" },
  { href: "/admin/creators", labelKey: "nav.admin.creators", icon: "contact", anyOf: ["creator.read"] },
  { href: "/admin/campaigns", labelKey: "nav.admin.campaigns", icon: "megaphone", anyOf: ["campaign.read"] },
  { href: "/admin/applications", labelKey: "nav.admin.applications", icon: "inbox", anyOf: ["campaign.read"] },
  { href: "/admin/deals", labelKey: "nav.admin.deals", icon: "handshake", anyOf: ["deal.read"] },
  { href: "/admin/contracts", labelKey: "nav.admin.contracts", icon: "signature", anyOf: ["contract.read"] },
  { href: "/admin/tasks", labelKey: "nav.admin.tasks", icon: "checklist" },
  { href: "/admin/agencies", labelKey: "nav.admin.agencies", icon: "building", anyOf: ["agency.manage"] },
  { href: "/admin/kyc", labelKey: "nav.admin.kyc", icon: "badgeCheck", anyOf: ["kyc.read_masked"] },
  { href: "/admin/staff", labelKey: "nav.admin.staff", icon: "users", anyOf: ["staff.manage"] },
  {
    href: "/admin/settings",
    labelKey: "nav.admin.settings",
    icon: "settings",
    anyOf: ["settings.read", "settings.write", "tax.manage", "tier.manage"],
  },
  { href: "/admin/audit", labelKey: "nav.admin.audit", icon: "scroll", anyOf: ["audit.read"] },
  { href: "/admin/system", labelKey: "nav.admin.system", icon: "activity", anyOf: ["system.read"] },
  { href: "/admin/help", labelKey: "nav.admin.help", icon: "help" },
];

export function visibleStaffNav(permissions: ReadonlySet<Permission>): StaffNavItem[] {
  return STAFF_NAV.filter((i) => !i.anyOf || i.anyOf.some((p) => permissions.has(p)));
}

export interface CreatorNavItem {
  href: string;
  labelKey: string;
  icon: IconName;
}

export const CREATOR_NAV: CreatorNavItem[] = [
  { href: "/creator", labelKey: "nav.creator.home", icon: "home" },
  { href: "/creator/campaigns", labelKey: "nav.creator.campaigns", icon: "megaphone" },
  { href: "/creator/deals", labelKey: "nav.creator.deals", icon: "handshake" },
  { href: "/creator/contracts", labelKey: "nav.creator.contracts", icon: "signature" },
  { href: "/creator/profile", labelKey: "nav.creator.profile", icon: "idCard" },
  { href: "/creator/kyc", labelKey: "nav.creator.kyc", icon: "badgeCheck" },
  { href: "/creator/media-kit", labelKey: "nav.creator.mediaKit", icon: "fileText" },
  { href: "/creator/agency", labelKey: "nav.creator.agency", icon: "building" },
  { href: "/creator/account", labelKey: "nav.creator.account", icon: "user" },
  { href: "/creator/help", labelKey: "nav.creator.help", icon: "help" },
];

export const AGENCY_NAV: CreatorNavItem[] = [
  { href: "/agency", labelKey: "nav.agency.home", icon: "users" },
  { href: "/agency/team", labelKey: "nav.agency.team", icon: "building" },
  { href: "/agency/account", labelKey: "nav.agency.account", icon: "user" },
  { href: "/agency/help", labelKey: "nav.agency.help", icon: "help" },
];

/** Active when the path is the item or below it (except the portal root, which matches exactly). */
export function isActive(path: string, href: string): boolean {
  if (href === "/admin" || href === "/creator" || href === "/agency") return path === href;
  return path === href || path.startsWith(`${href}/`);
}
