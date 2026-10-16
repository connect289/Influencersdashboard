import { describe, expect, it, vi } from "vitest";
vi.mock("server-only", () => ({}));
import { toDirUser } from "./directory";

describe("directory mapping", () => {
  it("maps a Workspace user", () => {
    expect(toDirUser({ id: "1", primaryEmail: "Priya@Eduwit.in", name: { fullName: " Priya Sharma " }, thumbnailPhotoUrl: "https://lh3.google/x",
      organizations: [{ title: "Intern" }, { title: "Counsellor", primary: true }] }))
      .toEqual({ id: "1", email: "priya@eduwit.in", name: "Priya Sharma", photo_url: "https://lh3.google/x", job_title: "Counsellor", suspended: false });
  });
  it("treats archived as suspended and drops http photos", () => {
    expect(toDirUser({ primaryEmail: "a@eduwit.in", archived: true, thumbnailPhotoUrl: "http://x" })).toMatchObject({ suspended: true, photo_url: null });
    expect(toDirUser({})).toBeNull();
  });
});
