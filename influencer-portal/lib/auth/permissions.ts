// Permission matrix: the single source of truth for staff access (spec 4).
// - `scripts/generate-sql.ts` turns it into the `inf.permissions` / `inf.role_permissions` rows that RLS policies and
//   SECURITY DEFINER functions check through `inf.has_perm()`. A unit test fails if the SQL is stale.
// - The UI uses `can()` to hide (never just disable) what a role cannot use.
// Creators and agency users are not in this table: their access is relationship-based (own records, or a grant from
// the creator) and enforced by RLS with `inf.current_creator_id()` / agency grants. `EXTERNAL_CAPABILITIES` documents it.

export const STAFF_ROLES = ["super_admin", "influencer_manager", "content_reviewer", "finance", "viewer"] as const;
export type StaffRole = (typeof STAFF_ROLES)[number];

export const ROLE_LABELS: Record<StaffRole, string> = {
  super_admin: "Super Admin",
  influencer_manager: "Influencer Manager",
  content_reviewer: "Content Reviewer",
  finance: "Finance",
  viewer: "Viewer / Analyst",
};

export const PERMISSIONS = {
  // Platform
  "settings.read": { area: "platform", label: "View settings" },
  "settings.write": { area: "platform", label: "Change settings" },
  "staff.manage": { area: "platform", label: "Manage staff and roles" },
  "audit.read": { area: "platform", label: "View the audit log" },
  "system.read": { area: "platform", label: "View system status and jobs" },
  "webhook.manage": { area: "platform", label: "Manage outbound webhooks" },
  "privacy.manage": { area: "platform", label: "Handle data export and deletion requests" },
  "notification_template.write": { area: "platform", label: "Edit notification templates" },
  "dpdp.manage": { area: "platform", label: "Handle data export and deletion requests" },
  "export.data": { area: "platform", label: "Export data to CSV" },
  // Creators
  "creator.read": { area: "creators", label: "View creators" },
  "creator.write": { area: "creators", label: "Create and edit creators" },
  "creator.import": { area: "creators", label: "Bulk import and invite creators" },
  "creator.delete_draft": { area: "creators", label: "Delete draft records" },
  "kyc.read_masked": { area: "creators", label: "View KYC status (masked)" },
  "kyc.reveal": { area: "creators", label: "View unmasked PAN and bank details" },
  "kyc.verify": { area: "creators", label: "Verify KYC" },
  "outreach.write": { area: "creators", label: "Log outreach" },
  "task.write": { area: "creators", label: "Create and assign tasks" },
  "agency.manage": { area: "creators", label: "Manage agencies" },
  // Campaigns and deals
  "campaign.read": { area: "campaigns", label: "View campaigns" },
  "campaign.write": { area: "campaigns", label: "Create and edit campaigns" },
  "application.review": { area: "campaigns", label: "Review applications and invites" },
  "deal.read": { area: "deals", label: "View deals and compensation" },
  "deal.write": { area: "deals", label: "Build, amend and propose deals" },
  // Contracts
  "contract.read": { area: "contracts", label: "View contracts" },
  "contract.write": { area: "contracts", label: "Draft, negotiate and send contracts" },
  "contract.countersign": {
    area: "contracts",
    label: "Countersign for Eduwit (Authorised Signatory)",
  },
  "clause.write": { area: "contracts", label: "Edit the clause library and templates" },
  "clause.legal_review": { area: "contracts", label: "Mark clauses as legally reviewed" },
  // Content
  "brief.read": { area: "content", label: "View briefs" },
  "brief.write": { area: "content", label: "Write and publish briefs" },
  "deliverable.read": { area: "content", label: "View deliverables" },
  "deliverable.review": { area: "content", label: "Review, comment, approve or reject content" },
  "deliverable.verify_live": { area: "content", label: "Verify live posts" },
  "compliance.override": { area: "content", label: "Override compliance checks (with a reason)" },
  "compliance.manage": { area: "content", label: "Edit the banned-claims list" },
  // Leads
  "lead.read": { area: "leads", label: "View the lead pipeline" },
  "lead.contacts": { area: "leads", label: "See students' phone and email" },
  "attribution.review": { area: "leads", label: "Review and override attribution" },
  "fraud.review": { area: "leads", label: "Review fraud flags" },
  // Money
  "ledger.read": { area: "finance", label: "View the ledger" },
  "ledger.adjust": { area: "finance", label: "Post manual adjustments" },
  "penalty.approve": { area: "finance", label: "Approve proposed penalties" },
  "payout.read": { area: "finance", label: "View payouts" },
  "payout.manage": { area: "finance", label: "Create payout batches and mark paid" },
  "payout.approve": { area: "finance", label: "Approve payout batches" },
  "tax.manage": { area: "finance", label: "Manage TDS, GST, invoices and Form 16A" },
  "commission_receipt.write": { area: "finance", label: "Record Eduwit commission receipts" },
  // Engagement and insight
  "analytics.read": { area: "insight", label: "View dashboards and reports" },
  "message.read": { area: "engagement", label: "Read messages" },
  "message.write": { area: "engagement", label: "Send messages" },
  "announcement.write": { area: "engagement", label: "Publish announcements" },
  "scorecard.read": { area: "insight", label: "View scorecards" },
  "tier.manage": { area: "insight", label: "Manage tiers and score weights" },
} as const satisfies Record<string, { area: string; label: string }>;

export type Permission = keyof typeof PERMISSIONS;
export const ALL_PERMISSIONS = Object.keys(PERMISSIONS) as Permission[];

const READ_ONLY_ELSEWHERE: Permission[] = [
  "creator.read",
  "campaign.read",
  "deal.read",
  "contract.read",
  "brief.read",
  "deliverable.read",
  "lead.read",
  "analytics.read",
  "scorecard.read",
];

/**
 * Role → permissions. The Authorised Signatory flag (staff_profiles.is_signatory) adds `contract.countersign` to any
 * role; it is never granted through a role.
 */
export const ROLE_GRANTS: Record<StaffRole, readonly Permission[]> = {
  super_admin: ALL_PERMISSIONS.filter((p) => p !== "contract.countersign"),
  influencer_manager: [
    "settings.read",
    "export.data",
    "creator.read",
    "creator.write",
    "creator.import",
    "kyc.read_masked",
    "outreach.write",
    "task.write",
    "agency.manage",
    "campaign.read",
    "campaign.write",
    "application.review",
    "deal.read",
    "deal.write",
    "contract.read",
    "contract.write",
    "clause.write",
    "brief.read",
    "brief.write",
    "deliverable.read",
    "deliverable.review",
    "deliverable.verify_live",
    "lead.read",
    "attribution.review",
    "fraud.review",
    "ledger.read",
    "penalty.approve",
    "payout.read",
    "analytics.read",
    "message.read",
    "message.write",
    "announcement.write",
    "scorecard.read",
  ],
  content_reviewer: [
    "creator.read",
    "campaign.read",
    "brief.read",
    "brief.write",
    "deliverable.read",
    "deliverable.review",
    "deliverable.verify_live",
    "compliance.override",
    "compliance.manage",
    "message.read",
    "message.write",
  ],
  finance: [
    ...READ_ONLY_ELSEWHERE,
    "settings.read",
    "export.data",
    "kyc.read_masked",
    "kyc.reveal",
    "kyc.verify",
    "ledger.read",
    "ledger.adjust",
    "payout.read",
    "payout.manage",
    "payout.approve",
    "tax.manage",
    "commission_receipt.write",
    "message.read",
    "message.write",
  ],
  viewer: ["analytics.read", "scorecard.read"],
};

export const SIGNATORY_PERMISSION: Permission = "contract.countersign";

export interface StaffAccess {
  roles: readonly StaffRole[];
  isSignatory: boolean;
}

/** Permissions held by a staff member (union of roles, plus countersign for signatories). */
export function permissionsFor(access: StaffAccess): Set<Permission> {
  const set = new Set<Permission>();
  for (const role of access.roles) for (const p of ROLE_GRANTS[role]) set.add(p);
  if (access.isSignatory) set.add(SIGNATORY_PERMISSION);
  return set;
}

export function can(access: StaffAccess | null | undefined, permission: Permission): boolean {
  return access ? permissionsFor(access).has(permission) : false;
}

export function isStaffRole(value: string): value is StaffRole {
  return (STAFF_ROLES as readonly string[]).includes(value);
}

export function isPermission(value: string): value is Permission {
  return Object.hasOwn(PERMISSIONS, value);
}

/** What creators and agency users can do (enforced by RLS, documented here for the UI and guides). */
export const EXTERNAL_CAPABILITIES = {
  creator: [
    "own profile, platforms, KYC (own details unmasked)",
    "open and invited campaigns, own applications",
    "own deals, contracts, briefs, deliverables",
    "own attributed leads (phone and email always masked)",
    "own earnings, ledger, payouts, statements, TDS certificates",
    "own messages and notifications",
  ],
  agency: [
    "linked creators only, per grant: view; act on deliverables; negotiate and sign; view earnings",
    "never a creator's bank details unless the contract names the agency as payee",
    "student phone and email always masked",
  ],
} as const;
