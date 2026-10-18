import { describe, expect, it } from "vitest";
import { checkPostUrl, oembedEndpoint, pickOembed } from "./urls";

describe("checkPostUrl", () => {
  it.each([
    [
      "instagram",
      "https://www.instagram.com/reel/C1aBcD2eF3g/?igsh=abc",
      "https://www.instagram.com/reel/C1aBcD2eF3g/",
    ],
    ["instagram", "https://instagram.com/p/C1aBcD2eF3g", "https://instagram.com/p/C1aBcD2eF3g"],
    ["youtube", "https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=xyz", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"],
    ["youtube", "https://youtu.be/dQw4w9WgXcQ", "https://youtu.be/dQw4w9WgXcQ"],
    ["youtube", "https://youtube.com/shorts/abcdEFG1234", "https://youtube.com/shorts/abcdEFG1234"],
    ["x", "https://x.com/riyalearns/status/1790000000000000000", "https://x.com/riyalearns/status/1790000000000000000"],
    ["x", "https://twitter.com/riya/status/123", "https://twitter.com/riya/status/123"],
    [
      "linkedin",
      "https://www.linkedin.com/posts/riya_mba-activity-123",
      "https://www.linkedin.com/posts/riya_mba-activity-123",
    ],
    ["telegram", "https://t.me/eduwit_updates/42", "https://t.me/eduwit_updates/42"],
    ["facebook", "https://fb.watch/abc123/", "https://fb.watch/abc123/"],
    ["other", "https://blog.example.com/my-mba-story#top", "https://blog.example.com/my-mba-story"],
  ] as const)("%s accepts %s", (platform, raw, normalised) => {
    expect(checkPostUrl(platform, raw)).toEqual({ ok: true, url: normalised });
  });

  it.each([
    ["instagram", "http://instagram.com/p/abc", "not_https"],
    ["instagram", "https://instagram.com/riyalearns", "invalid"],
    ["instagram", "https://youtube.com/watch?v=abcdefg", "wrong_platform"],
    ["instagram", "https://evilinstagram.com/p/abc", "wrong_platform"],
    ["youtube", "https://www.youtube.com/watch", "invalid"],
    ["x", "https://x.com/riya", "invalid"],
    ["other", "not a url", "invalid"],
    ["other", "https://user:pw@example.com/x", "invalid"],
    ["other", "javascript:alert(1)", "not_https"],
    ["other", "https://localhost/x", "invalid"],
  ] as const)("%s refuses %s", (platform, raw, error) => {
    expect(checkPostUrl(platform, raw)).toEqual({ ok: false, error });
  });
});

describe("oEmbed", () => {
  it("only YouTube has a public endpoint", () => {
    expect(oembedEndpoint("youtube", "https://youtu.be/dQw4w9WgXcQ")).toBe(
      "https://www.youtube.com/oembed?format=json&url=https%3A%2F%2Fyoutu.be%2FdQw4w9WgXcQ",
    );
    expect(oembedEndpoint("instagram", "https://instagram.com/p/x")).toBeNull();
  });
  it("keeps only safe fields, never HTML", () => {
    expect(
      pickOembed({
        title: "My MBA",
        author_name: "Riya",
        thumbnail_url: "https://i.ytimg.com/x.jpg",
        html: "<iframe>",
      }),
    ).toEqual({ title: "My MBA", author_name: "Riya", thumbnail_url: "https://i.ytimg.com/x.jpg" });
    expect(pickOembed({ thumbnail_url: "javascript:x" })).toEqual({
      title: null,
      author_name: null,
      thumbnail_url: null,
    });
    expect(pickOembed("nope")).toBeNull();
  });
});
