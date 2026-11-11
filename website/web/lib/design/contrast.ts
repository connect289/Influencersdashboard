/** WCAG 2.1 relative luminance and contrast ratio (used by the style guide and the token contrast test). */
export function luminance(hex: string): number {
  const h = hex.replace("#", "");
  const [r, g, b] = [0, 2, 4]
    .map((i) => parseInt(h.slice(i, i + 2), 16) / 255)
    .map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4)) as [number, number, number];
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

export function contrast(a: string, b: string): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x) as [number, number];
  return (hi + 0.05) / (lo + 0.05);
}

/** Text/background pairs that must meet WCAG AA (4.5:1 body, 3:1 large/UI). Kept in sync with app/tokens.css. */
export const CONTRAST_PAIRS: { theme: "dark" | "light"; name: string; fg: string; bg: string; min: number }[] = [
  { theme: "dark", name: "text on bg", fg: "#f5f5f7", bg: "#0e0e10", min: 4.5 },
  { theme: "dark", name: "muted on bg", fg: "#b1b1ba", bg: "#0e0e10", min: 4.5 },
  { theme: "dark", name: "subtle on bg", fg: "#92929c", bg: "#0e0e10", min: 4.5 },
  { theme: "dark", name: "muted on surface", fg: "#b1b1ba", bg: "#1a1a1e", min: 4.5 },
  { theme: "dark", name: "subtle on surface", fg: "#92929c", bg: "#1a1a1e", min: 4.5 },
  { theme: "dark", name: "on-primary on primary", fg: "#1a1200", bg: "#f3a503", min: 4.5 },
  { theme: "dark", name: "accent on bg", fg: "#ffc857", bg: "#0e0e10", min: 4.5 },
  { theme: "dark", name: "amber text on bg", fg: "#ffc44d", bg: "#0e0e10", min: 4.5 },
  { theme: "dark", name: "success on bg", fg: "#2fe6a7", bg: "#0e0e10", min: 4.5 },
  { theme: "dark", name: "danger on bg", fg: "#ff8a8a", bg: "#0e0e10", min: 4.5 },
  { theme: "light", name: "text on bg", fg: "#1d1d1f", bg: "#f5f5f7", min: 4.5 },
  { theme: "light", name: "muted on bg", fg: "#515158", bg: "#f5f5f7", min: 4.5 },
  { theme: "light", name: "subtle on bg", fg: "#66666e", bg: "#f5f5f7", min: 4.5 },
  { theme: "light", name: "subtle on white", fg: "#66666e", bg: "#ffffff", min: 4.5 },
  { theme: "light", name: "on-primary on primary (navy)", fg: "#ffffff", bg: "#1d1d1f", min: 4.5 },
  { theme: "light", name: "accent on white", fg: "#7a4d00", bg: "#ffffff", min: 4.5 },
  { theme: "light", name: "amber ink on bg", fg: "#94600a", bg: "#f5f5f7", min: 4.5 },
  { theme: "light", name: "success on white", fg: "#0f7a4b", bg: "#ffffff", min: 4.5 },
  { theme: "light", name: "danger on white", fg: "#c2281d", bg: "#ffffff", min: 4.5 },
  { theme: "light", name: "warning on warning-soft", fg: "#8a5a00", bg: "#fff4dc", min: 4.5 },
  { theme: "light", name: "text on concept-B bg", fg: "#1d1d1f", bg: "#fbfaf7", min: 4.5 },
  { theme: "dark", name: "focus ring on bg (UI)", fg: "#ffc94d", bg: "#0e0e10", min: 3 },
  { theme: "light", name: "focus ring on bg (UI)", fg: "#7a4d00", bg: "#f5f5f7", min: 3 },
];
