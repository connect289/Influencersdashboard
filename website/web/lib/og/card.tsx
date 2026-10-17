import { ImageResponse } from "next/og";

/**
 * Open Graph / Twitter card (1200×630) generated per page with next/og (spec 13.1). Brand colours from the logo
 * (D-007); plain system font so no font file is fetched at render time.
 */
export const OG_SIZE = { width: 1200, height: 630 };

export function ogCard({ eyebrow, title, footer }: { eyebrow: string; title: string; footer?: string }) {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          padding: "64px 72px",
          background: "linear-gradient(135deg, #031a33 0%, #062f5b 60%, #0b3f78 100%)",
          color: "#ffffff",
          fontFamily: "sans-serif",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", fontSize: 44, fontWeight: 700 }}>
          <span>Edu</span>
          <span style={{ color: "#f2a900" }}>wit</span>
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 18 }}>
          <div style={{ fontSize: 28, color: "#f2c35a", textTransform: "uppercase", letterSpacing: 3 }}>{eyebrow}</div>
          <div style={{ fontSize: title.length > 60 ? 54 : 66, fontWeight: 700, lineHeight: 1.1, maxWidth: 1000 }}>{title}</div>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 26, color: "#c9d6e8" }}>
          <span>{footer ?? "Full fees · approvals · eligibility · free counselling"}</span>
          <span>eduwit.in</span>
        </div>
      </div>
    ),
    OG_SIZE,
  );
}
