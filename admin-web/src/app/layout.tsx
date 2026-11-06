import type { Metadata } from "next";
import { AuthProvider } from "@/context/AuthContext";
import { ConfirmProvider } from "@/context/ConfirmContext";
import { ToastProvider } from "@/context/ToastContext";
import { AdminLayout } from "@/components/AdminLayout";
import "./globals.css";

// F-19: the production CSP authorises scripts with a per-request nonce
// (middleware.ts), so every page must be rendered per request rather than
// prerendered at build time (a build-time HTML snapshot cannot carry a nonce).
export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "CarNet Admin",
  description: "CarNet platform administration dashboard",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>
        <AuthProvider>
          <ToastProvider>
            <ConfirmProvider>
              <AdminLayout>{children}</AdminLayout>
            </ConfirmProvider>
          </ToastProvider>
        </AuthProvider>
      </body>
    </html>
  );
}
