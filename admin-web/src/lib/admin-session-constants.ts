/** Shared admin session cookie name (httpOnly access JWT). */
export const ADMIN_JWT_COOKIE = "carzo_admin_jwt";

/** httpOnly refresh JWT — used to rotate short-lived access tokens. */
export const ADMIN_REFRESH_COOKIE = "carzo_admin_refresh";

/** Legacy flag cookie — cleared on login/logout; no longer used for auth. */
export const LEGACY_AUTH_FLAG_COOKIE = "carzo_admin_auth";

/** Legacy localStorage key — cleared on login/logout. */
export const LEGACY_TOKEN_STORAGE_KEY = "carzo_admin_token";

/** Admin browser session lifetime (refresh cookie / re-login window). */
export const ADMIN_SESSION_MAX_AGE_SEC = 60 * 60 * 8; // 8 hours
