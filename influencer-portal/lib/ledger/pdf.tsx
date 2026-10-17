import "server-only";
import { join } from "node:path";
import { Document, Font, Page, renderToBuffer, StyleSheet, Text, View } from "@react-pdf/renderer";
import { formatDate, formatPaise } from "@/lib/format";
import type { Organisation, PayoutDetail } from "./data";
import type { Statement } from "./earnings";
import type { LedgerType } from "./lifecycle";

// Finance PDFs (spec 11): the payment advice sent when a payout is paid, and a creator's monthly statement. Both are
// rebuilt from the ledger, so they never disagree with it. Geist (bundled with the media kit) has the ₹ sign.
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
const MUTED = "#5C6F87";
const LINE = "#D5DCE6";

const s = StyleSheet.create({
  page: {
    fontFamily: "Geist",
    fontSize: 10,
    color: "#0E2240",
    paddingTop: 44,
    paddingBottom: 56,
    paddingHorizontal: 44,
  },
  top: { flexDirection: "row", justifyContent: "space-between", marginBottom: 18 },
  brand: { fontSize: 14, fontWeight: 700, color: NAVY },
  org: { fontSize: 8.5, color: MUTED, lineHeight: 1.4, maxWidth: 260 },
  title: { fontSize: 16, fontWeight: 700, color: NAVY, textAlign: "right" },
  ref: { fontSize: 9, color: MUTED, textAlign: "right", marginTop: 2 },
  box: { borderWidth: 1, borderColor: LINE, borderRadius: 6, padding: 10, marginBottom: 12 },
  dl: { flexDirection: "row", marginBottom: 2 },
  dt: { width: 120, color: MUTED },
  dd: { flex: 1 },
  th: { flexDirection: "row", backgroundColor: "#F2F4F7", borderBottomWidth: 1, borderBottomColor: LINE },
  tr: { flexDirection: "row", borderBottomWidth: 1, borderBottomColor: LINE },
  cell: { padding: 4, fontSize: 9 },
  head: { padding: 4, fontSize: 8.5, fontWeight: 700 },
  amount: { width: 90, textAlign: "right" },
  date: { width: 70 },
  grow: { flex: 1 },
  totals: { marginTop: 8, marginLeft: "auto", width: 260 },
  totalRow: { flexDirection: "row", justifyContent: "space-between", paddingVertical: 2 },
  strong: { fontWeight: 700 },
  net: { borderTopWidth: 1, borderTopColor: LINE, marginTop: 4, paddingTop: 4 },
  note: { fontSize: 8.5, color: MUTED, marginTop: 14, lineHeight: 1.4 },
  footer: {
    position: "absolute",
    bottom: 24,
    left: 44,
    right: 44,
    fontSize: 7.5,
    color: MUTED,
    flexDirection: "row",
    justifyContent: "space-between",
  },
});

export interface FinancePdfLabels {
  advice: string;
  statement: string;
  payee: string;
  name: string;
  pan: string;
  bank: string;
  paidOn: string;
  utr: string;
  date: string;
  description: string;
  amount: string;
  gross: string;
  tds: (section: string, rate: string) => string;
  gst: string;
  net: string;
  opening: string;
  closing: string;
  earned: string;
  tdsTotal: string;
  paidOut: string;
  empty: string;
  adviceNote: string;
  statementNote: string;
  page: (n: number, of: number) => string;
  type: (t: LedgerType) => string;
}

function Header({ org, title, sub }: { org: Organisation; title: string; sub: string }) {
  const ids = [org.gstin && `GSTIN ${org.gstin}`, org.pan && `PAN ${org.pan}`].filter(Boolean).join(" · ");
  return (
    <View style={s.top}>
      <View>
        <Text style={s.brand}>{org.trade_name || org.legal_name}</Text>
        <Text style={s.org}>{org.legal_name}</Text>
        {org.address ? <Text style={s.org}>{org.address}</Text> : null}
        {ids ? <Text style={s.org}>{ids}</Text> : null}
      </View>
      <View>
        <Text style={s.title}>{title}</Text>
        <Text style={s.ref}>{sub}</Text>
      </View>
    </View>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <View style={s.dl}>
      <Text style={s.dt}>{label}</Text>
      <Text style={s.dd}>{value}</Text>
    </View>
  );
}

function Footer({ org, l }: { org: Organisation; l: FinancePdfLabels }) {
  return (
    <View style={s.footer} fixed>
      <Text>{[org.legal_name, org.support_email].filter(Boolean).join(" · ")}</Text>
      <Text render={({ pageNumber, totalPages }) => l.page(pageNumber, totalPages)} />
    </View>
  );
}

const signedPaise = (p: number) => (p < 0 ? `−${formatPaise(-p)}` : formatPaise(p));

function AdviceDoc({ p, l }: { p: PayoutDetail; l: FinancePdfLabels }) {
  const org = p.organisation;
  return (
    <Document title={`${l.advice} ${p.ref}`} author={org.legal_name}>
      <Page size="A4" style={s.page}>
        <Header org={org} title={l.advice} sub={p.ref} />
        <View style={s.box}>
          <Row label={l.payee} value={p.legal_name ?? p.creator_name} />
          <Row label={l.name} value={`${p.creator_name} (@${p.handle})`} />
          {p.pan_last4 ? <Row label={l.pan} value={`•••••${p.pan_last4}`} /> : null}
          {p.bank_last4 ? <Row label={l.bank} value={`•••• ${p.bank_last4}${p.ifsc ? ` · ${p.ifsc}` : ""}`} /> : null}
          {p.gstin ? <Row label="GSTIN" value={p.gstin} /> : null}
          {p.paid_on ? <Row label={l.paidOn} value={formatDate(p.paid_on)} /> : null}
          {p.utr ? <Row label={l.utr} value={p.utr} /> : null}
        </View>
        <View style={s.th}>
          <Text style={[s.head, s.grow]}>{l.description}</Text>
          <Text style={[s.head, s.amount]}>{l.amount}</Text>
        </View>
        {p.items.map((i) => (
          <View key={i.entry_id} style={s.tr} wrap={false}>
            <Text style={[s.cell, s.grow]}>
              {i.note ?? l.type(i.type)}
              {i.deal_title ? ` · ${i.deal_title}` : ""} · {i.period}
            </Text>
            <Text style={[s.cell, s.amount]}>{signedPaise(i.amount_paise)}</Text>
          </View>
        ))}
        <View style={s.totals} wrap={false}>
          <View style={s.totalRow}>
            <Text>{l.gross}</Text>
            <Text>{formatPaise(p.gross_paise)}</Text>
          </View>
          {p.sections
            .filter((x) => x.tds_paise > 0 && x.borne_by === "creator")
            .map((x) => (
              <View key={x.code} style={s.totalRow}>
                <Text>{l.tds(x.code, (x.rate_bps / 100).toLocaleString("en-IN"))}</Text>
                <Text>−{formatPaise(x.tds_paise)}</Text>
              </View>
            ))}
          {p.gst_paise > 0 ? (
            <View style={s.totalRow}>
              <Text>{l.gst}</Text>
              <Text>{formatPaise(p.gst_paise)}</Text>
            </View>
          ) : null}
          <View style={[s.totalRow, s.net]}>
            <Text style={s.strong}>{l.net}</Text>
            <Text style={s.strong}>{formatPaise(p.net_paise)}</Text>
          </View>
        </View>
        <Text style={s.note}>{l.adviceNote}</Text>
        <Footer org={org} l={l} />
      </Page>
    </Document>
  );
}

export interface StatementParty {
  name: string;
  legal_name: string | null;
  handle: string;
}

function StatementDoc({
  st,
  creator,
  org,
  monthLabel,
  l,
}: {
  st: Statement;
  creator: StatementParty;
  org: Organisation;
  monthLabel: string;
  l: FinancePdfLabels;
}) {
  return (
    <Document title={`${l.statement} ${monthLabel}`} author={org.legal_name}>
      <Page size="A4" style={s.page}>
        <Header org={org} title={l.statement} sub={monthLabel} />
        <View style={s.box}>
          <Row label={l.payee} value={creator.legal_name ?? creator.name} />
          <Row label={l.name} value={`${creator.name} (@${creator.handle})`} />
          <Row label={l.opening} value={signedPaise(st.opening_paise)} />
        </View>
        <View style={s.th}>
          <Text style={[s.head, s.date]}>{l.date}</Text>
          <Text style={[s.head, s.grow]}>{l.description}</Text>
          <Text style={[s.head, s.amount]}>{l.amount}</Text>
        </View>
        {st.lines.length === 0 ? (
          <View style={s.tr}>
            <Text style={[s.cell, s.grow]}>{l.empty}</Text>
          </View>
        ) : (
          st.lines.map((x, i) => (
            <View key={i} style={s.tr} wrap={false}>
              <Text style={[s.cell, s.date]}>{formatDate(x.posted_at)}</Text>
              <Text style={[s.cell, s.grow]}>{x.label}</Text>
              <Text style={[s.cell, s.amount]}>{signedPaise(x.amount_paise)}</Text>
            </View>
          ))
        )}
        <View style={s.totals} wrap={false}>
          <View style={s.totalRow}>
            <Text>{l.earned}</Text>
            <Text>{signedPaise(st.earned_paise)}</Text>
          </View>
          <View style={s.totalRow}>
            <Text>{l.tdsTotal}</Text>
            <Text>{formatPaise(st.tds_paise)}</Text>
          </View>
          <View style={s.totalRow}>
            <Text>{l.gst}</Text>
            <Text>{formatPaise(st.gst_paise)}</Text>
          </View>
          <View style={s.totalRow}>
            <Text>{l.paidOut}</Text>
            <Text>{formatPaise(st.paid_out_paise)}</Text>
          </View>
          <View style={[s.totalRow, s.net]}>
            <Text style={s.strong}>{l.closing}</Text>
            <Text style={s.strong}>{signedPaise(st.closing_paise)}</Text>
          </View>
        </View>
        <Text style={s.note}>{l.statementNote}</Text>
        <Footer org={org} l={l} />
      </Page>
    </Document>
  );
}

export function renderAdvicePdf(p: PayoutDetail, labels: FinancePdfLabels): Promise<Buffer> {
  return renderToBuffer(<AdviceDoc p={p} l={labels} />);
}

export function renderStatementPdf(
  st: Statement,
  creator: StatementParty,
  org: Organisation,
  monthLabel: string,
  labels: FinancePdfLabels,
): Promise<Buffer> {
  return renderToBuffer(<StatementDoc st={st} creator={creator} org={org} monthLabel={monthLabel} l={labels} />);
}
