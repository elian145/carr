import type { NextConfig } from "next";
import path from "path";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  outputFileTracingRoot: path.join(__dirname),
  // API proxy: app/backend-api/[...path] attaches Authorization from the httpOnly JWT cookie.
};

export default nextConfig;
