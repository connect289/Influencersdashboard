import { describe, expect, it } from "vitest";
import { describeDevice, relativeTime } from "./format";

describe("format", () => {
  it("describes common devices", () => {
    expect(describeDevice("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/140.0 Safari/537.36")).toBe("Chrome on macOS");
    expect(describeDevice("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Version/18.0 Mobile Safari/604.1")).toBe("Safari on iOS");
    expect(describeDevice(null)).toBe("Unknown device");
  });
  it("gives relative times", () => {
    const now = Date.parse("2026-10-06T12:00:00Z");
    expect(relativeTime("2026-10-06T11:59:50Z", now)).toBe("just now");
    expect(relativeTime("2026-10-06T11:30:00Z", now)).toBe("30 min ago");
    expect(relativeTime("2026-10-06T07:00:00Z", now)).toBe("5 h ago");
  });
});
