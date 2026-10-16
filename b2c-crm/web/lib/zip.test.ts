import { crc32 as nodeCrc32 } from "node:zlib";
import { describe, expect, it } from "vitest";
import { crc32, zip } from "./zip";
import { unzip } from "./unzip.testutil";

describe("zip", () => {
  it("computes the standard CRC-32", () => {
    expect(crc32(new TextEncoder().encode("123456789"))).toBe(0xcbf43926);
    const sample = new TextEncoder().encode("Eduwit Spark ₹ 50,000");
    expect(crc32(sample)).toBe(nodeCrc32(sample));
  });

  it("writes entries that read back byte for byte", () => {
    const big = "row,".repeat(5000);
    const files = unzip(zip([{ name: "a.txt", data: "hello" }, { name: "dir/ünï.xml", data: "<x>₹</x>" }, { name: "big.csv", data: big }]));
    expect(files).toEqual({ "a.txt": "hello", "dir/ünï.xml": "<x>₹</x>", "big.csv": big });
  });

  it("handles an empty archive", () => {
    expect(unzip(zip([]))).toEqual({});
  });
});
