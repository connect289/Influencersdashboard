import { z } from "zod";

/**
 * The marketing email block editor (spec B9.2, B9.2a): a list of blocks rendered to email-safe HTML (one centred
 * 600px table, inline styles, no scripts or classes) that is stored as the template body and sent. Merge fields such
 * as {{first_name}} pass through as written. Every text is escaped and links must be https. Pure; unit-tested.
 */
export const BLOCKS_MARK = "<!-- spark:blocks -->";

const https = z.string().trim().max(1000).regex(/^https:\/\/[^\s"'<>]+$/, "Links and images start with https://");
const text = (max: number) => z.string().max(max);

export const BlockSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("heading"), text: text(200).min(1, "A heading needs text."), level: z.union([z.literal(1), z.literal(2)]).optional() }),
  z.object({ type: z.literal("text"), text: text(5000).min(1, "A text block needs text.") }),
  z.object({ type: z.literal("image"), src: https, alt: text(200).optional(), href: https.optional().or(z.literal("")) }),
  z.object({ type: z.literal("button"), text: text(60).min(1, "A button needs a label."), href: https }),
  z.object({ type: z.literal("divider") }),
  z.object({ type: z.literal("spacer"), height: z.number().int().min(4).max(80).optional() }),
  z.object({
    type: z.literal("programme"), name: text(200).min(1, "Name the programme."), university: text(200).optional(), fee: text(80).optional(),
    note: text(500).optional(), href: https.optional().or(z.literal("")),
  }),
]);
export const BlocksSchema = z.array(BlockSchema).max(60, "At most 60 blocks.");
export type Block = z.infer<typeof BlockSchema>;
export type BlockType = Block["type"];

export const BLOCK_LABEL: Record<BlockType, string> = {
  heading: "Heading", text: "Text", image: "Image", button: "Button", divider: "Divider", spacer: "Space", programme: "Programme card",
};

const FONT = "font-family:Arial,Helvetica,sans-serif;color:#1f2937";
const BRAND = "#072E5A";

export function esc(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

/** Escaped text with blank lines as paragraphs and single line breaks kept. */
function paras(s: string, style: string): string {
  return s.replace(/\r\n?/g, "\n").trim().split(/\n{2,}/).map((p) => `<p style="margin:0 0 12px;${style}">${esc(p).replace(/\n/g, "<br>")}</p>`).join("");
}

function row(inner: string, pad = "0 24px"): string {
  return `<tr><td style="padding:${pad}">${inner}</td></tr>`;
}

function one(b: Block): string {
  switch (b.type) {
    case "heading":
      return row(`<h${b.level ?? 2} style="margin:0 0 12px;${FONT};font-size:${b.level === 1 ? 24 : 19}px;line-height:1.3">${esc(b.text)}</h${b.level ?? 2}>`);
    case "text":
      return row(paras(b.text, `${FONT};font-size:15px;line-height:1.55`));
    case "image": {
      const img = `<img src="${esc(b.src)}" alt="${esc(b.alt ?? "")}" width="552" style="display:block;width:100%;max-width:552px;height:auto;border:0">`;
      return row(`<div style="margin:0 0 12px">${b.href ? `<a href="${esc(b.href)}">${img}</a>` : img}</div>`);
    }
    case "button":
      return row(`<table role="presentation" cellpadding="0" cellspacing="0" style="margin:4px 0 16px"><tr><td style="background:${BRAND};border-radius:6px">`
        + `<a href="${esc(b.href)}" style="display:inline-block;padding:11px 18px;${FONT};font-size:15px;color:#ffffff;text-decoration:none">${esc(b.text)}</a></td></tr></table>`);
    case "divider":
      return row(`<hr style="border:0;border-top:1px solid #e5e7eb;margin:8px 0 16px">`);
    case "spacer":
      return row(`<div style="height:${b.height ?? 16}px;line-height:${b.height ?? 16}px;font-size:1px">&nbsp;</div>`);
    case "programme": {
      const name = b.href ? `<a href="${esc(b.href)}" style="color:${BRAND};text-decoration:none">${esc(b.name)}</a>` : esc(b.name);
      return row(`<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 14px;border:1px solid #e5e7eb;border-radius:8px"><tr><td style="padding:14px 16px">`
        + `<div style="${FONT};font-size:16px;font-weight:bold">${name}</div>`
        + (b.university ? `<div style="${FONT};font-size:13px;color:#6b7280">${esc(b.university)}</div>` : "")
        + (b.fee ? `<div style="${FONT};font-size:14px;margin-top:6px">Fee: ${esc(b.fee)}</div>` : "")
        + (b.note ? `<div style="${FONT};font-size:14px;margin-top:6px">${esc(b.note).replace(/\n/g, "<br>")}</div>` : "")
        + `</td></tr></table>`);
    }
  }
}

/** The blocks as one email-safe HTML fragment, marked so the sender keeps it as HTML. */
export function renderBlocks(blocks: Block[]): string {
  return `${BLOCKS_MARK}<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;margin:0 auto"><tr><td style="height:16px"></td></tr>`
    + blocks.map(one).join("") + `</table>`;
}

export function isBlocksHtml(body: string | null | undefined): boolean {
  return typeof body === "string" && body.startsWith(BLOCKS_MARK);
}

/** The plain-text version that goes with the HTML. */
export function blocksText(blocks: Block[]): string {
  return blocks.map((b) => {
    switch (b.type) {
      case "heading": return b.text.toUpperCase();
      case "text": return b.text.trim();
      case "image": return b.href ? `${b.alt || "Image"}: ${b.href}` : b.alt ?? "";
      case "button": return `${b.text}: ${b.href}`;
      case "divider": return "----";
      case "spacer": return "";
      case "programme": return [b.name, b.university, b.fee && `Fee: ${b.fee}`, b.note, b.href].filter(Boolean).join("\n");
    }
  }).filter((s) => s !== "").join("\n\n");
}

/** Plain text from block HTML (for the text part when only the HTML is at hand, as when sending). */
export function htmlText(html: string): string {
  return html.replace(BLOCKS_MARK, "")
    .replace(/<a [^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/gi, (_, href: string, inner: string) => `${inner.replace(/<[^>]+>/g, "")} (${href})`)
    .replace(/<br\s*\/?>/gi, "\n").replace(/<\/(p|h1|h2|tr|div)>/gi, "\n\n").replace(/<hr[^>]*>/gi, "\n----\n")
    .replace(/<[^>]+>/g, "").replace(/&nbsp;/g, " ").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, "&")
    .replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
}

/** A new block of a type, with sensible starting values. */
export function newBlock(type: BlockType): Block {
  switch (type) {
    case "heading": return { type, text: "A heading", level: 2 };
    case "text": return { type, text: "Hi {{first_name}}," };
    case "image": return { type, src: "https://", alt: "" };
    case "button": return { type, text: "Know more", href: "https://" };
    case "divider": return { type };
    case "spacer": return { type, height: 16 };
    case "programme": return { type, name: "{{programme}}", university: "{{university}}" };
  }
}
