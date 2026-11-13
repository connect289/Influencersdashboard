import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { RichText } from "./RichText";

const reply = "Here is the brochure: https://example.edu/mba.pdf.\n\n- **Fees** on request";

describe("Witty reply text (D-095)", () => {
  it("shows a URL as plain text while the reply is unverified (streaming)", () => {
    const html = renderToStaticMarkup(<RichText text={reply} />);
    expect(html).not.toContain("<a ");
    expect(html).toContain("https://example.edu/mba.pdf");
    expect(html).toContain("<strong>Fees</strong>");
  });
  it("links it in the verified reply", () => {
    const html = renderToStaticMarkup(<RichText text={reply} links />);
    expect(html).toContain('<a href="https://example.edu/mba.pdf" target="_blank" rel="noopener noreferrer"');
    expect(html).toContain(">Brochure</a>");
  });
});
