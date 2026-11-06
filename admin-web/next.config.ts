import type { NextConfig } from "next";
import path from "path";
import { baseSecurityHeaders } from "./src/lib/security-headers";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  outputFileTracingRoot: path.join(__dirname),
  async headers() {
    // F-19: static assets (served from /_next/static, excluded from the
    // middleware matcher) get the non-CSP security headers too. Pages, API
    // routes and the proxy get the full set (incl. CSP) from middleware.ts.
    return [
      {
        source: "/:path*",
        headers: baseSecurityHeaders(process.env).map(([key, value]) => ({
          key,
          value,
        })),
      },
    ];
  },
  // API proxy: app/backend-api/[...path] attaches Authorization from the httpOnly JWT cookie.
};

export default nextConfig;
