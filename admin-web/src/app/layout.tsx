import type { Metadata } from "next";
import { AuthProvider } from "@/context/AuthContext";
import { AdminLayout } from "@/components/AdminLayout";
import "./globals.css";

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
          <AdminLayout>{children}</AdminLayout>
        </AuthProvider>
      </body>
    </html>
  );
}
