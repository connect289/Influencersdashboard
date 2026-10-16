import type { MetadataRoute } from "next";

/** Installable on phones (spec: the Sales app is used mostly on a phone). */
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Eduwit Spark",
    short_name: "Eduwit Spark",
    start_url: "/",
    display: "standalone",
    background_color: "#FFFFFF",
    theme_color: "#072E5A",
    icons: [{ src: "/logo.jpg", sizes: "512x512", type: "image/jpeg" }],
  };
}
