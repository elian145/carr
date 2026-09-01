import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

/** Render / uptime health check (no auth). */
export function GET() {
  return NextResponse.json({ status: "ok", service: "carzo-admin" });
}
