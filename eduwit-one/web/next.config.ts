import type { NextConfig } from "next";

// No build-time configuration: hosts, ids and thresholds are read from one.settings at runtime (spec standard 3).
const config: NextConfig = {
  poweredByHeader: false,
  reactStrictMode: true,
};

export default config;
