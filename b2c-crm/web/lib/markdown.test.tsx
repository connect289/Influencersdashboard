import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { Markdown, screenMatches } from "./markdown";

describe("guide markdown", () => {
  it("renders paragraphs, lists and bold, and escapes markup", () => {
    const h = renderToStaticMarkup(<Markdown text={"Start on **Today**.\nNext line\n\n- one\n- **two**\n\n<script>x</script>"} />);
    expect(h).toBe("<p>Start on <b>Today</b>.<br/>Next line</p><ul class=\"md-list\"><li>one</li><li><b>two</b></li></ul><p>&lt;script&gt;x&lt;/script&gt;</p>");
  });
  it("shows screenshots by number through the given links, and only those", () => {
    const images = [{ url: "https://s.example/a.png?token=x&y=1", caption: "First" }, { url: null, caption: "Gone" }];
    const h = renderToStaticMarkup(<Markdown text={"![The queue](image:1)\n\nSee ![](image:1) and ![x](image:2) and ![y](image:9).\n\n![](javascript:alert(1))"} images={images} />);
    expect(h).toContain('<figure class="md-figure" style="margin:8px 0"><img src="https://s.example/a.png?token=x&amp;y=1" alt="The queue"');
    expect(h).toContain("<figcaption class=\"small muted\">The queue</figcaption></figure>");
    expect(h).toContain('See <img src="https://s.example/a.png?token=x&amp;y=1" alt="First"');
    expect(h).toContain('<span class="muted">[x]</span>');
    expect(h).toContain('<span class="muted">[y]</span>');
    expect(h).toContain("<p>![](javascript:alert(1))</p>");
    expect(renderToStaticMarkup(<Markdown text="![Step 2](image:2)" />)).toBe('<span class="muted">[Step 2]</span>');
  });
  it("matches screens", () => {
    expect(screenMatches("/s/leads/*", "/s/leads/42")).toBe(true);
    expect(screenMatches("/s/leads/*", "/s/leads")).toBe(false);
    expect(screenMatches("/s/leads", "/s/leads")).toBe(true);
    expect(screenMatches("/s", "/s/leads")).toBe(false);
  });
});
