// Writes app/tokens.css from lib/brand/tokens.ts.   node scripts/gen-tokens.ts
import { writeFileSync } from "node:fs";
import { tokensCss } from "../lib/brand/tokens.ts";

writeFileSync(new URL("../app/tokens.css", import.meta.url), tokensCss());
console.warn("wrote app/tokens.css");
