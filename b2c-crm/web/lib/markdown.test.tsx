import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { Markdown, screenMatches } from "./markdown";

describe("guide markdown", () => {
  it("renders paragraphs, lists and bold, and escapes markup", () => {
    const h = renderToStaticMarkup(<Markdown text={"Start on **Today**.\nNext line\n\n- one\n- **two**\n\n<script>x</script>"} />);
    expect(h).toBe("<p>Start on <b>Today</b>.<br/>Next line</p><ul class=\"md-list\"><li>one</li><li><b>two</b></li></ul><p>&lt;script&gt;x&lt;/script&gt;</p>");
  });
  it("matches screens", () => {
    expect(screenMatches("/s/leads/*", "/s/leads/42")).toBe(true);
    expect(screenMatches("/s/leads/*", "/s/leads")).toBe(false);
    expect(screenMatches("/s/leads", "/s/leads")).toBe(true);
    expect(screenMatches("/s", "/s/leads")).toBe(false);
  });
});
