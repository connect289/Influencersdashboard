/** Joins class names, skipping empty ones. The components use only token classes, so no merge step is needed. */
export function cn(...parts: Array<string | false | null | undefined>): string {
  return parts.filter(Boolean).join(" ");
}
