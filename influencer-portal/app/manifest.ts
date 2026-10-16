import type { MetadataRoute } from "next";

// Installable PWA for creators (spec 3, 17). Opens straight into the creator portal.
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Eduwit Creators",
    short_name: "Eduwit",
    description: "Your Eduwit campaigns, content, leads and earnings in one place.",
    start_url: "/creator",
    scope: "/",
    display: "standalone",
    orientation: "portrait",
    background_color: "#f2f4f7",
    theme_color: "#0b2f5e",
    icons: [
      { src: "/brand/icon-192.png", sizes: "192x192", type: "image/png" },
      { src: "/brand/icon-512.png", sizes: "512x512", type: "image/png" },
      { src: "/brand/icon-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
    ],
  };
}
