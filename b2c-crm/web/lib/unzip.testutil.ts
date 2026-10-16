import { inflateRawSync } from "node:zlib";
import { crc32 } from "./zip";

// Test helper (not a test file).
/** Reads a ZIP through its central directory, as a spreadsheet program does. */
export function unzip(file: Uint8Array): Record<string, string> {
  const b = Buffer.from(file);
  const end = b.lastIndexOf(Buffer.from([0x50, 0x4b, 0x05, 0x06]));
  const count = b.readUInt16LE(end + 10);
  let p = b.readUInt32LE(end + 16);
  const out: Record<string, string> = {};
  for (let i = 0; i < count; i++) {
    if (b.readUInt32LE(p) !== 0x02014b50) throw new Error("bad central header");
    const crc = b.readUInt32LE(p + 16);
    const size = b.readUInt32LE(p + 20);
    const nameLen = b.readUInt16LE(p + 28);
    const local = b.readUInt32LE(p + 42);
    const name = b.subarray(p + 46, p + 46 + nameLen).toString("utf8");
    if (b.readUInt32LE(local) !== 0x04034b50) throw new Error("bad local header");
    const start = local + 30 + b.readUInt16LE(local + 26) + b.readUInt16LE(local + 28);
    const data = inflateRawSync(b.subarray(start, start + size));
    if (crc32(data) !== crc) throw new Error(`bad CRC in ${name}`);
    out[name] = data.toString("utf8");
    p += 46 + nameLen + b.readUInt16LE(p + 30) + b.readUInt16LE(p + 32);
  }
  return out;
}

