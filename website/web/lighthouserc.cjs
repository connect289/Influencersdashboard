// Lighthouse CI budgets (spec 3A/12): mobile form factor, applied (DevTools) throttling — slow 4G + 4x CPU — which is
// what D-021 measures against. Runs against `next start` on :3100 with the local Supabase stack.
const paths = ["/", "/programmes", "/programmes?programme=mba&spec=marketing", "/programmes/online-mba", "/universities", "/universities/nmims", "/thank-you", "/admin/login"];
module.exports = {
  ci: {
    collect: {
      startServerCommand: "npx next start -p 3100",
      startServerReadyPattern: "Ready",
      url: paths.map((p) => `http://localhost:3100${p}`),
      numberOfRuns: 2,
      chromePath: process.env.CHROME_PATH || undefined,
      settings: {
        formFactor: "mobile",
        throttlingMethod: "devtools",
        onlyCategories: ["performance", "accessibility", "best-practices", "seo"],
        chromeFlags: "--headless=new --no-sandbox --disable-gpu",
        // Lighthouse 13 dropped "Chrome-Lighthouse" from its UA; keep it so the SEO audit sees what HTML-limited crawlers
        // receive (Next sends blocking <head> metadata to them and streams it to browsers — D-035).
        emulatedUserAgent:
          "Mozilla/5.0 (Linux; Android 11; moto g power (2022)) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Mobile Safari/537.36 Chrome-Lighthouse",
      },
    },
    assert: {
      assertMatrix: [
        {
          matchingUrlPattern: ".*",
          assertions: {
            "categories:performance": ["error", { minScore: 0.9, aggregationMethod: "median-run" }],
            "categories:accessibility": ["error", { minScore: 0.95 }],
            "categories:best-practices": ["error", { minScore: 0.9 }],
            "largest-contentful-paint": ["error", { maxNumericValue: 2500, aggregationMethod: "median-run" }],
            "cumulative-layout-shift": ["error", { maxNumericValue: 0.1 }],
            "total-blocking-time": ["error", { maxNumericValue: 300, aggregationMethod: "median-run" }],
          },
        },
        {
          // Public pages must be indexable; /admin and /thank-you are deliberately noindex.
          matchingUrlPattern: "^(?!.*/(admin|thank-you)).*$",
          assertions: { "categories:seo": ["error", { minScore: 0.95 }] },
        },
      ],
    },
    upload: { target: "filesystem", outputDir: ".lighthouseci" },
  },
};
