import localFont from "next/font/local";

/**
 * Self-hosted Latin subsets (app/fonts, OFL). Characters outside Latin — notably ₹ — use the system font, which every
 * target platform ships (Roboto on Android, Segoe UI on Windows, SF on Apple), avoiding a 130 KB latin-ext download.
 */

/** Body face, both concepts; also Concept B's display face (Inter's optical sizing gives a "display" cut at large sizes). */
export const inter = localFont({
  src: "../app/fonts/inter-opsz-latin.woff2",
  weight: "100 900",
  style: "normal",
  display: "optional",
  variable: "--font-inter",
  adjustFontFallback: "Arial",
  declarations: [
    {
      prop: "unicode-range",
      value:
        "U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD",
    },
  ],
});

/**
 * Concept A display face: Bricolage Grotesque, variable with optical sizing (spec 10.2). font-display: optional so the
 * headline (the LCP element) never waits for or re-flows on the web font (D-020).
 */
export const bricolage = localFont({
  src: "../app/fonts/bricolage-opsz-latin.woff2",
  weight: "200 800",
  style: "normal",
  display: "optional",
  variable: "--font-bricolage",
  adjustFontFallback: "Arial",
  declarations: [
    {
      prop: "unicode-range",
      value:
        "U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD",
    },
  ],
});

export const fontVariables = [bricolage.variable, inter.variable].join(" ");
