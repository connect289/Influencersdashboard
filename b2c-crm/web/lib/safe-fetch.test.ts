import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";
import { describe, expect, it } from "vitest";
import { fetchChecked, guardedLookup, hostAllowed, hostList, isPublicAddress, urlProblem, type FetchDeps, type FetchRules } from "./safe-fetch";

const RULES: FetchRules = { hosts: [".exotel.com", "media.example.org"], credentialHosts: [".exotel.com"], maxBytes: 1024, timeoutMs: 5000, maxRedirects: 3 };

describe("which addresses a download may reach", () => {
  it("refuses private, loopback, link-local, metadata, shared, multicast and reserved addresses", () => {
    for (const ip of ["10.0.0.1", "172.16.5.4", "172.31.255.255", "192.168.1.1", "127.0.0.1", "169.254.169.254", "100.64.0.1", "0.0.0.0", "224.0.0.1",
      "255.255.255.255", "198.18.0.1", "192.0.2.5", "203.0.113.9", "::", "::1", "fe80::1", "fd00:ec2::254", "fc00::1", "ff02::1", "::ffff:10.0.0.1",
      "::ffff:169.254.169.254", "64:ff9b::a00:1", "2001:db8::1", "::127.0.0.1", "not-an-ip"]) {
      expect(isPublicAddress(ip), ip).toBe(false);
    }
  });
  it("allows public unicast addresses", () => {
    for (const ip of ["8.8.8.8", "13.235.12.1", "172.32.0.1", "2606:4700:4700::1111", "::ffff:8.8.8.8", "64:ff9b::808:808"]) expect(isPublicAddress(ip), ip).toBe(true);
  });
});

describe("which links a download may follow", () => {
  it("needs https, the standard port, no user info and an allowed host name", () => {
    expect(urlProblem("https://recordings.exotel.com/a.mp3", RULES.hosts)).toBeNull();
    expect(urlProblem("https://exotel.com/a.mp3", RULES.hosts)).toBeNull();
    expect(urlProblem("http://recordings.exotel.com/a.mp3", RULES.hosts)).toMatch(/https/);
    expect(urlProblem("https://u:p@recordings.exotel.com/a.mp3", RULES.hosts)).toMatch(/user name/);
    expect(urlProblem("https://recordings.exotel.com:8443/a.mp3", RULES.hosts)).toMatch(/port/);
    expect(urlProblem("https://169.254.169.254/latest/meta-data/", RULES.hosts)).toMatch(/host name/);
    expect(urlProblem("https://[fd00:ec2::254]/latest/meta-data/", RULES.hosts)).toMatch(/host name/);
    expect(urlProblem("https://metadata.google.internal/computeMetadata/v1/", [".internal"])).toMatch(/internal/);
    expect(urlProblem("https://evil.example.com/a.mp3", RULES.hosts)).toMatch(/not an allowed host/);
    expect(urlProblem("https://evilexotel.com/a.mp3", RULES.hosts)).toMatch(/not an allowed host/);
    expect(urlProblem("https://exotel.com.evil.net/a.mp3", RULES.hosts)).toMatch(/not an allowed host/);
  });
  it("matches hosts on a dot boundary and reads host lists", () => {
    expect(hostAllowed("a.b.exotel.com", [".exotel.com"])).toBe(true);
    expect(hostAllowed("notexotel.com", [".exotel.com"])).toBe(false);
    expect(hostAllowed("media.example.org.", ["media.example.org"])).toBe(true);
    expect(hostList(" CDN.Example.com , .eduwit.in, bad host, http://x.y ")).toEqual(["cdn.example.com", ".eduwit.in"]);
  });
});

describe("the download itself", () => {
  it("refuses a host name whose DNS answer is private, before connecting", async () => {
    const lookup = ((_h: string, _o: unknown, cb: (e: Error | null, a: { address: string; family: number }[]) => void) => cb(null, [{ address: "10.0.0.7", family: 4 }])) as unknown as FetchDeps["lookup"];
    await new Promise<void>((resolve) => {
      guardedLookup(lookup)("media.example.org", { all: false }, ((err: Error | null) => { expect(err?.message).toMatch(/private or reserved/); resolve(); }) as never);
    });
    await expect(fetchChecked("https://media.example.org/x.png", RULES, undefined, { lookup })).rejects.toThrow(/private or reserved/);
  });

  it("sends credentials only to the hosts named for them, also across a redirect, and caps the size", async () => {
    const seen: { host: string; auth: string | undefined }[] = [];
    const answers: Record<string, { status: number; headers: Record<string, string>; body?: string }> = {
      "recordings.exotel.com": { status: 302, headers: { location: "https://media.example.org/r.mp3" } },
      "media.example.org": { status: 200, headers: { "content-type": "audio/mpeg" }, body: "ID3" },
    };
    const request = ((url: URL, options: { headers?: Record<string, string> }, callback: (res: unknown) => void) => {
      const req = new EventEmitter() as EventEmitter & { end: () => void; destroy: (e?: Error) => void };
      req.destroy = (e?: Error) => { if (e) req.emit("error", e); };
      req.end = () => {
        seen.push({ host: url.hostname, auth: options.headers?.authorization });
        const a = answers[url.hostname]!;
        const res = Object.assign(new PassThrough(), { statusCode: a.status, headers: a.headers });
        callback(res);
        res.end(a.body ?? "");
        req.emit("close");
      };
      return req;
    }) as unknown as FetchDeps["request"];
    const f = await fetchChecked("https://recordings.exotel.com/a.mp3", RULES, { authorization: "Basic c2VjcmV0" }, { request });
    expect(f.body.toString()).toBe("ID3");
    expect(seen).toEqual([{ host: "recordings.exotel.com", auth: "Basic c2VjcmV0" }, { host: "media.example.org", auth: undefined }]);
    answers["media.example.org"] = { status: 200, headers: {}, body: "x".repeat(2048) };
    await expect(fetchChecked("https://media.example.org/big.mp3", RULES, undefined, { request })).rejects.toThrow(/larger than/);
    answers["recordings.exotel.com"] = { status: 302, headers: { location: "https://evil.example.com/steal" } };
    await expect(fetchChecked("https://recordings.exotel.com/a.mp3", RULES, { authorization: "Basic c2VjcmV0" }, { request })).rejects.toThrow(/not an allowed host/);
  });
});
