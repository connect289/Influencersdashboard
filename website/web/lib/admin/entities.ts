/**
 * Admin content editor configuration (spec 11). Each entity maps to an allow-listed table in web_admin_entities
 * (migration web9); the server re-checks columns and roles. Field types drive the generic list and edit screens.
 */
export type FieldType = "text" | "textarea" | "number" | "bool" | "json" | "tags" | "select" | "datetime" | "url";

export interface Field {
  name: string;
  label: string;
  type: FieldType;
  required?: boolean;
  options?: string[];
  help?: string;
  /** key fields are editable on create only */
  key?: boolean;
  readOnly?: boolean;
}

export interface EntityConfig {
  entity: string;
  label: string;
  singular: string;
  description: string;
  minRole: "content_editor" | "super_admin";
  key: string[];
  listColumns: string[];
  fields: Field[];
  canCreate?: boolean;
  canDelete?: boolean;
}

export const ENTITIES: EntityConfig[] = [
  {
    entity: "curated_views",
    label: "Curated finder views",
    singular: "curated view",
    description: "Indexable landing pages (/programmes/<slug>) with pre-applied filters, intro and FAQs. Only these finder pages are indexed.",
    minRole: "content_editor",
    key: ["slug"],
    listColumns: ["slug", "title", "status"],
    canDelete: true,
    fields: [
      { name: "slug", label: "Slug", type: "text", required: true, key: true, help: "Lower case, hyphens: online-mba-hr → /programmes/online-mba-hr" },
      { name: "title", label: "Title (page title)", type: "text", required: true },
      { name: "h1", label: "H1", type: "text" },
      { name: "intro", label: "Intro", type: "textarea", help: "Plain, factual. Approvals and fees come only from the catalogue." },
      { name: "filters", label: "Filters", type: "json", required: true, help: 'Finder filters, e.g. {"programme":["mba"],"spec":["hr"]}' },
      { name: "faqs", label: "FAQs", type: "json", help: 'List of {"q": "...", "a": "..."}' },
      { name: "seo_description", label: "Meta description", type: "textarea" },
      { name: "status", label: "Status", type: "select", options: ["draft", "published", "archived"], required: true },
      { name: "sort", label: "Order", type: "number" },
    ],
  },
  {
    entity: "faqs",
    label: "FAQs",
    singular: "FAQ",
    description: "Global and per-page FAQs (FAQPage structured data). Scope: home, contact, how-it-works, about, curated:<slug>, university:<slug>.",
    minRole: "content_editor",
    key: ["id"],
    listColumns: ["scope", "question", "published"],
    canDelete: true,
    fields: [
      { name: "scope", label: "Scope", type: "text", required: true },
      { name: "question", label: "Question", type: "text", required: true },
      { name: "answer", label: "Answer", type: "textarea", required: true },
      { name: "sort", label: "Order", type: "number" },
      { name: "published", label: "Published", type: "bool" },
    ],
  },
  {
    entity: "testimonials",
    label: "Testimonials",
    singular: "testimonial",
    description: "Shown only when published, and publishing requires the student's agreement to be quoted.",
    minRole: "content_editor",
    key: ["id"],
    listColumns: ["name", "quote", "published"],
    canDelete: true,
    fields: [
      { name: "name", label: "Name", type: "text", required: true },
      { name: "detail", label: "Detail", type: "text", help: "e.g. Online MBA, 2025" },
      { name: "quote", label: "Quote", type: "textarea", required: true },
      { name: "rating", label: "Rating (1–5)", type: "number" },
      { name: "photo_path", label: "Photo path", type: "text" },
      { name: "source", label: "Source", type: "select", options: ["new", "legacy"] },
      { name: "consent_confirmed", label: "Student agreed to be quoted", type: "bool" },
      { name: "published", label: "Published", type: "bool" },
      { name: "sort", label: "Order", type: "number" },
    ],
  },
  {
    entity: "resources",
    label: "Guides",
    singular: "guide",
    description: "Every guide needs a named author and reviewer before publishing (spec 13.4). Body is a list of blocks.",
    minRole: "content_editor",
    key: ["slug"],
    listColumns: ["slug", "title", "status"],
    canDelete: true,
    fields: [
      { name: "slug", label: "Slug", type: "text", required: true, key: true },
      { name: "title", label: "Title", type: "text", required: true },
      { name: "summary", label: "Summary", type: "textarea" },
      { name: "body", label: "Body (blocks)", type: "json", help: '[{"type":"p","text":"..."},{"type":"h2","text":"..."}]' },
      { name: "author_id", label: "Author id", type: "number" },
      { name: "reviewer_id", label: "Reviewer id", type: "number" },
      { name: "status", label: "Status", type: "select", options: ["idea", "brief", "draft", "review", "published", "refresh_due", "archived"], required: true },
      { name: "published_at", label: "Published at", type: "datetime" },
      { name: "refresh_due_at", label: "Refresh due", type: "datetime" },
      { name: "tags", label: "Tags", type: "tags" },
      { name: "seo_title", label: "SEO title", type: "text" },
      { name: "seo_description", label: "SEO description", type: "textarea" },
      { name: "brief", label: "Brief (from the content planner)", type: "json" },
      { name: "draft_source", label: "Draft source", type: "select", options: ["human", "claude_assisted"] },
    ],
  },
  {
    entity: "authors",
    label: "Authors and reviewers",
    singular: "author",
    description: "Named people for guide bylines. They cannot be deleted (bylines keep pointing at them); set inactive instead.",
    minRole: "content_editor",
    key: ["id"],
    listColumns: ["id", "name", "role", "active"],
    canDelete: false,
    fields: [
      { name: "name", label: "Name", type: "text", required: true },
      { name: "role", label: "Role", type: "text", help: "e.g. Senior admissions counsellor" },
      { name: "bio", label: "Short bio", type: "textarea" },
      { name: "photo_path", label: "Photo path", type: "text" },
      { name: "active", label: "Active", type: "bool" },
    ],
  },
  {
    entity: "university_profiles",
    label: "University pages",
    singular: "university page",
    description: "Editorial content for university pages. Facts (approvals, fees) come from the catalogue and are not edited here.",
    minRole: "content_editor",
    key: ["catalog_university_id"],
    listColumns: ["display_name", "state", "logo_permitted", "published"],
    canCreate: false,
    canDelete: false,
    fields: [
      { name: "catalog_university_id", label: "Catalogue id", type: "number", key: true, readOnly: true },
      { name: "display_name", label: "Display name", type: "text" },
      { name: "about", label: "About", type: "textarea" },
      { name: "state", label: "State", type: "text" },
      { name: "city", label: "City", type: "text" },
      { name: "website_url", label: "Official website", type: "url" },
      { name: "logo_path", label: "Logo path", type: "text" },
      { name: "logo_permitted", label: "Logo use permitted by the owner", type: "bool" },
      { name: "published", label: "Published", type: "bool" },
    ],
  },
  {
    entity: "popular_searches",
    label: "Popular searches",
    singular: "popular search",
    description: "Chips on the homepage and empty search states.",
    minRole: "content_editor",
    key: ["id"],
    listColumns: ["label", "href", "active"],
    canDelete: true,
    fields: [
      { name: "label", label: "Label", type: "text", required: true },
      { name: "href", label: "Link", type: "text", required: true, help: "A site path, e.g. /programmes/online-mba" },
      { name: "sort", label: "Order", type: "number" },
      { name: "active", label: "Active", type: "bool" },
    ],
  },
  {
    entity: "pages",
    label: "SEO overrides",
    singular: "page override",
    description: "Override the title, description, OG image or indexing of any page path. Templates in code apply otherwise.",
    minRole: "content_editor",
    key: ["path"],
    listColumns: ["path", "title", "noindex"],
    canDelete: true,
    fields: [
      { name: "path", label: "Path", type: "text", required: true, key: true, help: "e.g. /about or /universities/nmims" },
      { name: "title", label: "Title (≤ 70 characters)", type: "text" },
      { name: "description", label: "Description (≤ 200 characters)", type: "textarea" },
      { name: "og_image", label: "OG image URL", type: "url" },
      { name: "noindex", label: "Noindex", type: "bool" },
    ],
  },
  {
    entity: "redirects",
    label: "Redirects",
    singular: "redirect",
    description: "Applied at request time without a deploy (D-045). The legacy map in code runs first.",
    minRole: "content_editor",
    key: ["from_path"],
    listColumns: ["from_path", "to_path", "code", "hits"],
    canDelete: true,
    fields: [
      { name: "from_path", label: "From path", type: "text", required: true, key: true },
      { name: "to_path", label: "To (path or https URL)", type: "text", required: true },
      { name: "code", label: "Status", type: "select", options: ["301", "302", "307", "308"], required: true },
      { name: "source", label: "Source", type: "select", options: ["admin", "404_monitor", "slug_change", "legacy_map"] },
    ],
  },
  {
    entity: "synonyms",
    label: "Search synonyms",
    singular: "synonym",
    description: "Words students type, mapped to taxonomy ids (programme, specialisation, level, university, category, mode) or stopwords.",
    minRole: "content_editor",
    key: ["id"],
    listColumns: ["alias", "kind", "target_id"],
    canDelete: true,
    fields: [
      { name: "alias", label: "Alias", type: "text", required: true },
      { name: "kind", label: "Kind", type: "select", options: ["programme", "specialisation", "level", "university", "category", "mode", "stopword"], required: true },
      { name: "target_id", label: "Target id", type: "text" },
      { name: "weight", label: "Weight", type: "number" },
      { name: "source", label: "Source", type: "select", options: ["admin", "seed", "catalog_synonyms"] },
    ],
  },
  {
    entity: "legal_pages",
    label: "Legal pages",
    singular: "legal page",
    description: "The six legal pages keep their URLs. Text is migrated verbatim (S-01); edits go through legal review.",
    minRole: "super_admin",
    key: ["slug"],
    listColumns: ["slug", "title", "status"],
    canCreate: false,
    canDelete: false,
    fields: [
      { name: "slug", label: "Slug", type: "text", key: true, readOnly: true },
      { name: "title", label: "Title", type: "text", required: true },
      { name: "body", label: "Body (blocks)", type: "json" },
      { name: "status", label: "Status", type: "select", options: ["pending_migration", "migrated", "proposed_edit"], required: true },
      { name: "source_url", label: "Source URL", type: "url" },
      { name: "reviewed_by", label: "Reviewed by", type: "text" },
    ],
  },
  {
    entity: "consent_texts",
    label: "Consent text versions",
    singular: "consent text",
    description: "Versioned; an accepted text is never reworded — create a new version and deactivate the old one.",
    minRole: "super_admin",
    key: ["version"],
    listColumns: ["version", "channel", "active"],
    canDelete: false,
    fields: [
      { name: "version", label: "Version", type: "text", required: true, key: true, help: "e.g. web-form-2026-11-v2" },
      { name: "channel", label: "Channel", type: "select", options: ["gate", "form", "marketing"], required: true },
      { name: "body", label: "Text", type: "textarea", required: true },
      { name: "purposes", label: "Purposes", type: "tags", help: "sales, partner_share, ai_chat_storage, marketing" },
      { name: "active", label: "Active", type: "bool" },
      { name: "legal_reviewed_at", label: "Legal review date", type: "datetime" },
    ],
  },
  {
    entity: "keywords",
    label: "SEO keywords",
    singular: "keyword",
    description: "Target keywords with priority and landing page; positions come from Search Console (SEO toolkit → Keywords).",
    minRole: "content_editor",
    key: ["id"],
    listColumns: ["keyword", "priority", "target_path"],
    canDelete: true,
    fields: [
      { name: "keyword", label: "Keyword", type: "text", required: true, help: "Lower case, as people search it" },
      { name: "priority", label: "Priority (1 high – 3 low)", type: "number" },
      { name: "target_path", label: "Target page", type: "text", help: "/programmes/online-mba, /universities/nmims, /resources/…, or /" },
      { name: "notes", label: "Notes", type: "textarea" },
    ],
  },
  {
    entity: "local_seo",
    label: "Local SEO checklist",
    singular: "task",
    description: "Manual tasks for Google Business Profile and directories.",
    minRole: "content_editor",
    key: ["id"],
    listColumns: ["task", "done"],
    canDelete: true,
    fields: [
      { name: "task", label: "Task", type: "text", required: true },
      { name: "done", label: "Done", type: "bool" },
      { name: "done_at", label: "Done on", type: "datetime" },
      { name: "done_by", label: "Done by", type: "text" },
      { name: "sort", label: "Order", type: "number" },
    ],
  },
];

export function entityConfig(entity: string): EntityConfig | undefined {
  return ENTITIES.find((e) => e.entity === entity);
}

/** Converts a submitted form into the JSON row the database expects. Pure; returns field errors. */
export function parseEntityForm(cfg: EntityConfig, form: FormData, isNew: boolean): { row: Record<string, unknown>; errors: Record<string, string> } {
  const row: Record<string, unknown> = {};
  const errors: Record<string, string> = {};
  for (const f of cfg.fields) {
    if (f.readOnly && !isNew) {
      const v = form.get(f.name);
      if (v !== null) row[f.name] = f.type === "number" ? Number(v) : String(v);
      continue;
    }
    if (f.key && !isNew) {
      row[f.name] = f.type === "number" ? Number(form.get(f.name)) : String(form.get(f.name) ?? "");
      continue;
    }
    if (f.type === "bool") {
      row[f.name] = form.get(f.name) === "on";
      continue;
    }
    const raw = String(form.get(f.name) ?? "").trim();
    if (!raw) {
      // Empty: required → error; new rows → database default; edits → cleared (JSON and numbers stay unchanged).
      if (f.required) errors[f.name] = `${f.label} is required.`;
      else if (!isNew && form.has(f.name) && f.type !== "json" && f.type !== "number") row[f.name] = null;
      continue;
    }
    switch (f.type) {
      case "number": {
        const n = Number(raw);
        if (!Number.isFinite(n)) errors[f.name] = `${f.label} must be a number.`;
        else row[f.name] = n;
        break;
      }
      case "json":
        try {
          row[f.name] = JSON.parse(raw);
        } catch {
          errors[f.name] = `${f.label} is not valid JSON.`;
        }
        break;
      case "tags":
        row[f.name] = raw.split(",").map((t) => t.trim()).filter(Boolean);
        break;
      case "datetime": {
        const d = new Date(raw);
        if (Number.isNaN(d.getTime())) errors[f.name] = `${f.label} is not a valid date.`;
        else row[f.name] = d.toISOString();
        break;
      }
      case "select":
        if (f.options && !f.options.includes(raw)) errors[f.name] = `Choose a valid ${f.label.toLowerCase()}.`;
        else row[f.name] = f.name === "code" ? Number(raw) : raw;
        break;
      case "url":
        if (!/^https:\/\/\S+$/.test(raw) && !raw.startsWith("/")) errors[f.name] = `${f.label} must start with https:// or /.`;
        else row[f.name] = raw;
        break;
      default:
        row[f.name] = raw;
    }
  }
  return { row, errors };
}
