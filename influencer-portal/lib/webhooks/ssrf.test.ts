import { describe, expect, it } from "vitest";
import { isPublicAddress, literalHostAllowed } from "./ssrf";

describe("webhook address check", () => {
  it("allows public addresses", () => {
    for (const ip of ["8.8.8.8", "1.1.1.1", "13.235.1.2", "2606:4700:4700::1111", "2404:6800:4009:80b::200e"])
      expect(isPublicAddress(ip), ip).toBe(true);
  });

  it("refuses loopback, private, link-local, metadata, CGNAT, multicast and reserved", () => {
    for (const ip of [
      "127.0.0.1",
      "10.1.2.3",
      "172.16.0.1",
      "172.31.255.255",
      "192.168.1.1",
      "169.254.169.254",
      "100.64.0.1",
      "0.0.0.0",
      "224.0.0.1",
      "255.255.255.255",
      "192.0.2.10",
      "::1",
      "::",
      "fc00::1",
      "fd12:3456::1",
      "fe80::1",
      "ff02::1",
      "::ffff:127.0.0.1",
      "::ffff:10.0.0.1",
      "2001:db8::1",
      "not-an-ip",
      "",
    ])
      expect(isPublicAddress(ip), ip).toBe(false);
  });

  it("treats IPv4-mapped public addresses as public", () => {
    expect(isPublicAddress("::ffff:8.8.8.8")).toBe(true);
    expect(isPublicAddress("172.32.0.1")).toBe(true);
  });

  it("refuses private addresses written as the host, in any form the URL parser accepts", () => {
    for (const u of [
      "https://127.0.0.1/hook",
      "https://2130706433/hook",
      "https://0x7f.1/hook",
      "https://0177.0.0.1/hook",
      "https://[::1]/hook",
      "https://100.64.0.1/hook",
      "https://169.254.169.254/latest",
      "not a url",
    ])
      expect(literalHostAllowed(u), u).toBe(false);
    for (const u of ["https://hooks.example.com/x", "https://8.8.8.8/x", "https://[2606:4700::1111]/x"])
      expect(literalHostAllowed(u), u).toBe(true);
  });
});
