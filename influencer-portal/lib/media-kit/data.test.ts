import { describe, expect, it } from "vitest";
import { averageEngagement, avatarUrl, mediaKitFileName } from "./data";

describe("media kit helpers", () => {
  it("builds public avatar URLs only for well-formed paths", () => {
    expect(avatarUrl("http://127.0.0.1:54421/", "7c9e6679-7425-40de-944b-e07fc1f90ae7/1760000000000.png")).toBe(
      "http://127.0.0.1:54421/storage/v1/object/public/inf-public-avatars/7c9e6679-7425-40de-944b-e07fc1f90ae7/1760000000000.png",
    );
    expect(avatarUrl("http://x", "../secret.png")).toBeNull();
    expect(avatarUrl("http://x", null)).toBeNull();
  });
  it("weights engagement by followers and ignores platforms without data", () => {
    expect(
      averageEngagement({
        platforms: [
          {
            platform: "instagram",
            handle: "a",
            url: "",
            followers: 30000,
            avg_views: null,
            engagement_rate: 5,
            stats_updated_at: null,
          },
          {
            platform: "youtube",
            handle: "a",
            url: "",
            followers: 10000,
            avg_views: null,
            engagement_rate: 1,
            stats_updated_at: null,
          },
          {
            platform: "x",
            handle: "a",
            url: "",
            followers: 50000,
            avg_views: null,
            engagement_rate: null,
            stats_updated_at: null,
          },
        ],
      }),
    ).toBe(4);
    expect(averageEngagement({ platforms: [] })).toBeNull();
  });
  it("makes a safe file name", () => {
    expect(mediaKitFileName("riya.learns")).toBe("riya.learns-media-kit.pdf");
    expect(mediaKitFileName("../..")).toBe("creator-media-kit.pdf");
  });
});
