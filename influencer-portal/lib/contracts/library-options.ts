import type { LibraryClause } from "./data";
import type { RichDoc } from "./doc";

export interface LibraryOption {
  id: string;
  key: string;
  category: string;
  version: number;
  title: string;
  body: RichDoc;
  required: boolean;
  negotiable: boolean;
  locked: boolean;
  reviewed: boolean;
}

/** Library clauses as the template editor needs them (current versions, archived ones left out). */
export function libraryOptions(library: readonly LibraryClause[]): LibraryOption[] {
  return library
    .filter((c) => !c.archived)
    .map((c) => ({
      id: c.id,
      key: c.key,
      category: c.category,
      version: c.version,
      title: c.title,
      body: c.body,
      required: c.required,
      negotiable: c.negotiable,
      locked: c.locked,
      reviewed: c.reviewed_at !== null,
    }));
}
