import "server-only";
import { join } from "node:path";
import { Document, Font, Page, renderToBuffer, StyleSheet, Text, View } from "@react-pdf/renderer";
import type { ContractContent } from "./assemble";
import type { Block, Inline } from "./doc";

// The signed contract PDF (spec 8.4): the exact version that was signed, then a signature certificate page with every
// signature record and the document hash. Geist (bundled with the media kit) has the ₹ sign.
const FONT_DIR = join(process.cwd(), "lib", "media-kit", "fonts");
Font.register({
  family: "Geist",
  fonts: [
    { src: join(FONT_DIR, "Geist-Regular.ttf"), fontWeight: 400 },
    { src: join(FONT_DIR, "Geist-Regular.ttf"), fontWeight: 400, fontStyle: "italic" },
    { src: join(FONT_DIR, "Geist-Bold.ttf"), fontWeight: 700 },
    { src: join(FONT_DIR, "Geist-Bold.ttf"), fontWeight: 700, fontStyle: "italic" },
  ],
});
Font.registerHyphenationCallback((word) => [word]);

const NAVY = "#0B2F5E";
const MUTED = "#5C6F87";
const LINE = "#D5DCE6";

const s = StyleSheet.create({
  page: {
    fontFamily: "Geist",
    fontSize: 10,
    color: "#0E2240",
    paddingTop: 48,
    paddingBottom: 56,
    paddingHorizontal: 48,
  },
  title: { fontSize: 16, fontWeight: 700, color: NAVY, marginBottom: 8 },
  header: { color: MUTED, marginBottom: 12 },
  sectionTitle: { fontSize: 11, fontWeight: 700, color: NAVY, marginTop: 12, marginBottom: 4 },
  p: { lineHeight: 1.45, marginBottom: 4 },
  h2: { fontSize: 11, fontWeight: 700, marginTop: 6, marginBottom: 3 },
  h3: { fontSize: 10.5, fontWeight: 700, marginTop: 5, marginBottom: 2 },
  li: { flexDirection: "row", marginBottom: 2 },
  bullet: { width: 14 },
  liBody: { flex: 1 },
  table: { borderWidth: 1, borderColor: LINE, marginVertical: 4 },
  tr: { flexDirection: "row", borderBottomWidth: 1, borderBottomColor: LINE },
  th: { flex: 1, padding: 4, fontWeight: 700, backgroundColor: "#F2F4F7", fontSize: 9 },
  td: { flex: 1, padding: 4, fontSize: 9 },
  footer: {
    position: "absolute",
    bottom: 24,
    left: 48,
    right: 48,
    fontSize: 7.5,
    color: MUTED,
    flexDirection: "row",
    justifyContent: "space-between",
  },
  certTitle: { fontSize: 15, fontWeight: 700, color: NAVY, marginBottom: 10 },
  dl: { flexDirection: "row", marginBottom: 3 },
  dt: { width: 130, color: MUTED },
  dd: { flex: 1 },
  mono: { fontSize: 8 },
  sig: { borderWidth: 1, borderColor: LINE, borderRadius: 6, padding: 8, marginTop: 8 },
  sigName: { fontSize: 11, fontWeight: 700 },
});

function InlineText({ content }: { content: readonly Inline[] | undefined }) {
  return (
    <>
      {(content ?? []).map((n, i) => {
        if (n.type === "hardBreak") return <Text key={i}>{"\n"}</Text>;
        const marks = new Set((n.marks ?? []).map((m) => m.type));
        return (
          <Text
            key={i}
            style={{
              fontWeight: marks.has("bold") ? 700 : 400,
              fontStyle: marks.has("italic") ? "italic" : "normal",
              textDecoration: marks.has("underline") ? "underline" : "none",
            }}
          >
            {n.text}
          </Text>
        );
      })}
    </>
  );
}

function BlockPdf({ block, depth = 0 }: { block: Block; depth?: number }) {
  switch (block.type) {
    case "paragraph":
      return (
        <Text style={s.p}>
          <InlineText content={block.content} />
        </Text>
      );
    case "heading":
      return (
        <Text style={block.attrs.level === 2 ? s.h2 : s.h3}>
          <InlineText content={block.content} />
        </Text>
      );
    case "bulletList":
    case "orderedList":
      return (
        <View style={{ marginLeft: depth * 12, marginBottom: 4 }}>
          {block.content.map((li, i) => (
            <View key={i} style={s.li} wrap={false}>
              <Text style={s.bullet}>{block.type === "bulletList" ? "•" : `${String(i + 1)}.`}</Text>
              <View style={s.liBody}>
                {li.content.map((b, j) => (
                  <BlockPdf key={j} block={b} depth={depth + 1} />
                ))}
              </View>
            </View>
          ))}
        </View>
      );
    case "table":
      return (
        <View style={s.table}>
          <View style={s.tr} fixed>
            {block.head.map((h, i) => (
              <Text key={i} style={s.th}>
                {h}
              </Text>
            ))}
          </View>
          {block.rows.map((r, i) => (
            <View key={i} style={s.tr} wrap={false}>
              {r.map((c, j) => (
                <Text key={j} style={s.td}>
                  {c}
                </Text>
              ))}
            </View>
          ))}
        </View>
      );
  }
}

export interface CertificateSignature {
  signer_name: string;
  signer_role: string;
  signer_designation: string | null;
  signed_at: string;
  signed_at_ist: string;
  otp_channel: string;
  otp_reference: string | null;
  consent_version: number;
  ip: string | null;
  user_agent: string | null;
  document_sha256: string;
}

export interface Certificate {
  number: string;
  version: number;
  sha256: string;
  generatedAt: string;
  signatures: CertificateSignature[];
}

const ROLE: Record<string, string> = {
  creator: "Creator",
  agency: "Agency, for the Creator",
  signatory: "Authorised Signatory, for Eduwit",
};

function Footer({ number, sha256 }: { number: string; sha256: string }) {
  return (
    <View style={s.footer} fixed>
      <Text>
        {number} · SHA-256 {sha256.slice(0, 16)}…
      </Text>
      <Text render={({ pageNumber, totalPages }) => `${String(pageNumber)} / ${String(totalPages)}`} />
    </View>
  );
}

export function ContractPdf({ content, certificate }: { content: ContractContent; certificate: Certificate }) {
  return (
    <Document title={content.title} author="Eduwit" subject={`Contract ${certificate.number}`}>
      <Page size="A4" style={s.page}>
        <Text style={s.title}>{content.title}</Text>
        <View style={s.header}>
          {content.header.map((b, i) => (
            <BlockPdf key={i} block={b} />
          ))}
        </View>
        {content.sections.map((sec) => (
          <View key={sec.key}>
            <Text style={s.sectionTitle} minPresenceAhead={40}>
              {sec.number}. {sec.title}
            </Text>
            {sec.blocks.map((b, i) => (
              <BlockPdf key={i} block={b} />
            ))}
          </View>
        ))}
        <View style={{ marginTop: 12 }}>
          {content.footer.map((b, i) => (
            <BlockPdf key={i} block={b} />
          ))}
        </View>
        <Footer number={certificate.number} sha256={certificate.sha256} />
      </Page>
      <Page size="A4" style={s.page}>
        <Text style={s.certTitle}>Signature certificate</Text>
        <View style={s.dl}>
          <Text style={s.dt}>Contract</Text>
          <Text style={s.dd}>
            {certificate.number}, version {certificate.version}
          </Text>
        </View>
        <View style={s.dl}>
          <Text style={s.dt}>Document SHA-256</Text>
          <Text style={[s.dd, s.mono]}>{certificate.sha256}</Text>
        </View>
        <View style={s.dl}>
          <Text style={s.dt}>Certificate generated</Text>
          <Text style={s.dd}>{certificate.generatedAt} UTC</Text>
        </View>
        <Text style={[s.p, { marginTop: 8, color: MUTED }]}>
          Each party reviewed the document above, typed their name, accepted the consent text and confirmed with a
          one-time code sent to them. The SHA-256 hash identifies the exact document signed; any change to it produces a
          different hash.
        </Text>
        {certificate.signatures.map((g, i) => (
          <View key={i} style={s.sig} wrap={false}>
            <Text style={s.sigName}>
              {g.signer_name}
              {g.signer_designation ? `, ${g.signer_designation}` : ""}
            </Text>
            <Text style={{ color: MUTED, marginBottom: 4 }}>{ROLE[g.signer_role] ?? g.signer_role}</Text>
            <View style={s.dl}>
              <Text style={s.dt}>Signed (UTC)</Text>
              <Text style={s.dd}>{g.signed_at}</Text>
            </View>
            <View style={s.dl}>
              <Text style={s.dt}>Signed (IST)</Text>
              <Text style={s.dd}>{g.signed_at_ist}</Text>
            </View>
            <View style={s.dl}>
              <Text style={s.dt}>One-time code</Text>
              <Text style={s.dd}>
                by {g.otp_channel}
                {g.otp_reference ? ` · reference ${g.otp_reference}` : ""}
              </Text>
            </View>
            <View style={s.dl}>
              <Text style={s.dt}>Consent text</Text>
              <Text style={s.dd}>version {g.consent_version}</Text>
            </View>
            <View style={s.dl}>
              <Text style={s.dt}>IP address</Text>
              <Text style={s.dd}>{g.ip ?? "not recorded"}</Text>
            </View>
            <View style={s.dl}>
              <Text style={s.dt}>Device</Text>
              <Text style={[s.dd, s.mono]}>{g.user_agent ?? "not recorded"}</Text>
            </View>
            <View style={s.dl}>
              <Text style={s.dt}>Hash signed</Text>
              <Text style={[s.dd, s.mono]}>{g.document_sha256}</Text>
            </View>
          </View>
        ))}
        <Footer number={certificate.number} sha256={certificate.sha256} />
      </Page>
    </Document>
  );
}

export async function renderContractPdf(content: ContractContent, certificate: Certificate): Promise<Buffer> {
  return renderToBuffer(<ContractPdf content={content} certificate={certificate} />);
}
