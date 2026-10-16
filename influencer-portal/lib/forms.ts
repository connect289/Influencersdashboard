/** A text field from FormData ("" when missing or a file). */
export function formText(form: FormData | null | undefined, name: string): string {
  const v = form?.get(name);
  return typeof v === "string" ? v : "";
}
