import type { User } from "./types";

/** Nav/page → required permission (must match backend admin_roles._PERMISSIONS). */
export const NAV_PERMISSION: Record<string, string> = {
  "/dashboard": "dashboard",
  "/search": "search",
  "/insights": "insights",
  "/analytics": "analytics",
  "/users": "users.read",
  "/listings": "listings.read",
  "/reports": "reports",
  "/dealers": "dealers",
  "/messages": "messages",
  "/notifications": "notifications.read",
  "/saved-searches": "saved_searches",
  "/audit": "audit",
  "/system": "system",
  "/settings": "settings",
  "/catalog": "catalog.read",
};

export const ADMIN_ROLE_LABELS: Record<string, string> = {
  super_admin: "Super admin",
  moderator: "Moderator",
  support: "Support",
  marketing: "Marketing",
};

export function hasPermission(
  user: User | null | undefined,
  permission: string,
): boolean {
  if (!user?.is_admin) return false;
  const perms = user.permissions;
  // Older API without permissions field → full access (legacy admins)
  if (!Array.isArray(perms)) return true;
  return perms.includes(permission);
}

export function roleLabel(role: string | null | undefined): string {
  if (!role) return "Admin";
  return ADMIN_ROLE_LABELS[role] || role;
}
