import "server-only";
import { join } from "node:path";
import {
  Document,
  Font,
  Image,
  Link,
  Page,
  renderToBuffer,
  StyleSheet,
  Text,
  View,
} from "@react-pdf/renderer";
import { formatCompact, formatDate, formatPaise } from "@/lib/format";
import { averageEngagement, type MediaKit } from "./data";

// Geist (SIL OFL, bundled in lib/media-kit/fonts) has the ₹ sign, which the PDF base fonts lack.
const FONT_DIR = join(process.cwd(), "lib", "media-kit", "fonts");
Font.register({
  family: "Geist",
  fonts: [
    { src: join(FONT_DIR, "Geist-Regular.ttf"), fontWeight: 400 },
    { src: join(FONT_DIR, "Geist-Bold.ttf"), fontWeight: 700 },
  ],
});
Font.registerHyphenationCallback((word) => [word]);

const NAVY = "#0B2F5E";
const GOLD = "#8A5A00";
const MUTED = "#5C6F87";
const LINE = "#E3E8EF";

const s = StyleSheet.create({
  page: { fontFamily: "Geist", fontSize: 10, color: "#0E2240", padding: 36 },
  header: { flexDirection: "row", alignItems: "center", gap: 14, marginBottom: 18 },
  avatar: { width: 64, height: 64, borderRadius: 32 },
  name: { fontSize: 22, fontWeight: 700, color: NAVY },
  sub: { color: MUTED, marginTop: 2 },
  brand: { position: "absolute", top: 36, right: 36, fontSize: 10, fontWeight: 700, color: NAVY },
  section: { marginTop: 16 },
  h2: { fontSize: 12, fontWeight: 700, color: NAVY, marginBottom: 6 },
  bio: { lineHeight: 1.5 },
  stats: { flexDirection: "row", gap: 10 },
  stat: { flex: 1, borderWidth: 1, borderColor: LINE, borderRadius: 8, padding: 10 },
  statValue: { fontSize: 16, fontWeight: 700, color: NAVY },
  statLabel: { color: MUTED, marginTop: 2, fontSize: 9 },
  row: { flexDirection: "row", borderBottomWidth: 1, borderBottomColor: LINE, paddingVertical: 5 },
  th: { color: MUTED, fontSize: 9 },
  c1: { flex: 2 },
  c2: { flex: 1, textAlign: "right" },
  chips: { flexDirection: "row", flexWrap: "wrap", gap: 4 },
  chip: {
    backgroundColor: "#EEF3FA",
    color: NAVY,
    borderRadius: 8,
    paddingVertical: 2,
    paddingHorizontal: 6,
    fontSize: 9,
  },
  link: { color: NAVY, textDecoration: "none", marginBottom: 3 },
  footer: {
    position: "absolute",
    bottom: 24,
    left: 36,
    right: 36,
    fontSize: 8,
    color: MUTED,
    textAlign: "center",
  },
});

export interface PdfLabels {
  brand: string;
  about: string;
  reach: string;
  platformsCount: string;
  engagement: string;
  platforms: string;
  platform: string;
  followers: string;
  avgViews: string;
  er: string;
  rates: string;
  format: string;
  price: string;
  topics: string;
  languages: string;
  work: string;
  footer: string;
  platformName: (p: MediaKit["platforms"][number]["platform"]) => string;
  formatName: (f: MediaKit["rates"][number]["format"]) => string;
}

function MediaKitDocument({
  kit,
  labels,
  avatar,
}: {
  kit: MediaKit;
  labels: PdfLabels;
  avatar: string | null;
}) {
  const er = averageEngagement(kit);
  const where = [kit.city, kit.state].filter(Boolean).join(", ");
  return (
    <Document title={`${kit.display_name} · media kit`} author={labels.brand}>
      <Page size="A4" style={s.page}>
        <Text style={s.brand}>{labels.brand}</Text>
        <View style={s.header}>
          {/* react-pdf's Image is a PDF image object, not an HTML <img>; it has no alt attribute. */}
          {/* eslint-disable-next-line jsx-a11y/alt-text */}
          {avatar ? <Image src={avatar} style={s.avatar} /> : null}
          <View>
            <Text style={s.name}>{kit.display_name}</Text>
            <Text style={s.sub}>
              @{kit.handle}
              {where ? ` · ${where}` : ""}
            </Text>
          </View>
        </View>
        <View style={s.stats}>
          <View style={s.stat}>
            <Text style={s.statValue}>{formatCompact(kit.total_followers)}</Text>
            <Text style={s.statLabel}>{labels.reach}</Text>
          </View>
          <View style={s.stat}>
            <Text style={s.statValue}>{kit.platforms.length}</Text>
            <Text style={s.statLabel}>{labels.platformsCount}</Text>
          </View>
          <View style={s.stat}>
            <Text style={s.statValue}>{er === null ? "—" : `${String(er)}%`}</Text>
            <Text style={s.statLabel}>{labels.engagement}</Text>
          </View>
        </View>
        {kit.bio ? (
          <View style={s.section}>
            <Text style={s.h2}>{labels.about}</Text>
            <Text style={s.bio}>{kit.bio}</Text>
          </View>
        ) : null}
        {kit.niches.length || kit.languages.length ? (
          <View style={[s.section, { flexDirection: "row", gap: 24 }]}>
            {kit.niches.length ? (
              <View style={{ flex: 1 }}>
                <Text style={s.h2}>{labels.topics}</Text>
                <View style={s.chips}>
                  {kit.niches.map((n) => (
                    <Text key={n} style={s.chip}>
                      {n}
                    </Text>
                  ))}
                </View>
              </View>
            ) : null}
            {kit.languages.length ? (
              <View style={{ flex: 1 }}>
                <Text style={s.h2}>{labels.languages}</Text>
                <Text>{kit.languages.join(", ")}</Text>
              </View>
            ) : null}
          </View>
        ) : null}
        {kit.platforms.length ? (
          <View style={s.section}>
            <Text style={s.h2}>{labels.platforms}</Text>
            <View style={s.row}>
              <Text style={[s.th, s.c1]}>{labels.platform}</Text>
              <Text style={[s.th, s.c2]}>{labels.followers}</Text>
              <Text style={[s.th, s.c2]}>{labels.avgViews}</Text>
              <Text style={[s.th, s.c2]}>{labels.er}</Text>
            </View>
            {kit.platforms.map((p) => (
              <View key={`${p.platform}-${p.handle}`} style={s.row}>
                <Link src={p.url} style={[s.c1, { color: NAVY, textDecoration: "none" }]}>
                  {labels.platformName(p.platform)} · @{p.handle}
                </Link>
                <Text style={s.c2}>{p.followers === null ? "—" : formatCompact(p.followers)}</Text>
                <Text style={s.c2}>{p.avg_views === null ? "—" : formatCompact(p.avg_views)}</Text>
                <Text style={s.c2}>
                  {p.engagement_rate === null ? "—" : `${String(p.engagement_rate)}%`}
                </Text>
              </View>
            ))}
          </View>
        ) : null}
        {kit.rates.length ? (
          <View style={s.section}>
            <Text style={s.h2}>{labels.rates}</Text>
            <View style={s.row}>
              <Text style={[s.th, s.c1]}>{labels.format}</Text>
              <Text style={[s.th, s.c2]}>{labels.price}</Text>
            </View>
            {kit.rates.map((r) => (
              <View key={`${r.platform}-${r.format}`} style={s.row}>
                <Text style={s.c1}>
                  {labels.formatName(r.format)} · {labels.platformName(r.platform)}
                </Text>
                <Text style={[s.c2, { color: GOLD, fontWeight: 700 }]}>
                  {formatPaise(r.suggested_paise, { whole: true })}
                </Text>
              </View>
            ))}
          </View>
        ) : null}
        {kit.portfolio.length ? (
          <View style={s.section}>
            <Text style={s.h2}>{labels.work}</Text>
            {kit.portfolio.map((f) => (
              <Link key={f.url} src={f.url} style={s.link}>
                {f.title ?? f.url}
              </Link>
            ))}
          </View>
        ) : null}
        <Text style={s.footer} fixed>
          {labels.footer} · {formatDate(kit.generated_at)}
        </Text>
      </Page>
    </Document>
  );
}

export async function renderMediaKitPdf(
  kit: MediaKit,
  labels: PdfLabels,
  avatar: string | null,
): Promise<Buffer> {
  return renderToBuffer(<MediaKitDocument kit={kit} labels={labels} avatar={avatar} />);
}
