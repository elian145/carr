import { ApiRequestError, apiRequest } from "./auth";
import { buildQuery } from "./query";
import type {
  AdminReport,
  AnalyticsOverview,
  CarDetail,
  CarListing,
  DashboardData,
  FilterMeta,
  GlobalSearchResults,
  InsightsData,
  Message,
  Notification,
  Pagination,
  SavedSearch,
  User,
  UserAction,
  UserDetail,
} from "./types";

interface LoginResponse {
  access_token?: string;
  token?: string;
  user?: User;
  message?: string;
}

export async function login(username: string, password: string): Promise<string> {
  const data = await apiRequest<LoginResponse>("/api/auth/login", {
    method: "POST",
    body: JSON.stringify({ username, password }),
  });
  const token = data.access_token || data.token;
  if (!token) throw new Error("No token in login response");
  return token;
}

export async function fetchMe(): Promise<User> {
  return apiRequest<User>("/api/auth/me");
}

export async function fetchDashboard(): Promise<DashboardData> {
  return apiRequest<DashboardData>("/api/admin/dashboard");
}

export async function fetchFilterMeta(): Promise<FilterMeta> {
  return apiRequest<FilterMeta>("/api/admin/meta/filters");
}

export async function globalSearch(q: string, limit = 20): Promise<GlobalSearchResults> {
  return apiRequest(`/api/admin/search${buildQuery({ q, limit })}`);
}

export interface UserListParams {
  page?: number;
  per_page?: number;
  search?: string;
  account_type?: string;
  dealer_status?: string;
  is_active?: boolean;
  is_admin?: boolean;
}

export async function fetchUsers(
  params: UserListParams,
): Promise<{ users: User[]; pagination: Pagination }> {
  return apiRequest(`/api/admin/users${buildQuery(params as Record<string, string | number | boolean>)}`);
}

export async function fetchUserDetail(userId: string): Promise<UserDetail> {
  return apiRequest<UserDetail>(`/api/admin/users/${encodeURIComponent(userId)}`);
}

export async function updateUserStatus(
  userId: string,
  isActive: boolean,
): Promise<void> {
  await apiRequest(`/api/admin/users/${encodeURIComponent(userId)}/status`, {
    method: "PATCH",
    body: JSON.stringify({ is_active: isActive }),
  });
}

export interface ListingListParams {
  page?: number;
  per_page?: number;
  search?: string;
  brand?: string;
  status?: string;
  active_only?: boolean;
  is_featured?: boolean;
  min_price?: number;
  max_price?: number;
  sort?: string;
}

export async function fetchListings(
  params: ListingListParams,
): Promise<{ cars: CarListing[]; pagination: Pagination }> {
  return apiRequest(`/api/admin/cars${buildQuery(params as Record<string, string | number | boolean>)}`);
}

export async function fetchListingDetail(carId: string): Promise<CarDetail> {
  return apiRequest<CarDetail>(`/api/admin/cars/${encodeURIComponent(carId)}`);
}

export async function updateListingStatus(
  carId: string,
  patch: { is_active?: boolean; status?: string; is_featured?: boolean },
): Promise<void> {
  await apiRequest(`/api/admin/cars/${encodeURIComponent(carId)}/status`, {
    method: "PATCH",
    body: JSON.stringify(patch),
  });
}

export async function bulkUpdateListingStatus(
  ids: string[],
  patch: { is_active?: boolean; status?: string; is_featured?: boolean },
): Promise<{ updated: string[]; missing: string[]; message: string }> {
  return apiRequest("/api/admin/cars/bulk-status", {
    method: "POST",
    body: JSON.stringify({ ids, ...patch }),
  });
}

export async function broadcastNotification(payload: {
  title: string;
  message: string;
  audience?: "all" | "dealers" | "users" | "user";
  target_user_id?: string;
  notification_type?: string;
  send_push?: boolean;
}): Promise<{
  message: string;
  created: number;
  pushed: number;
  push_configured: boolean;
  audience: string;
}> {
  return apiRequest("/api/admin/notifications/broadcast", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

export async function deleteListing(carId: string): Promise<{ message: string }> {
  return apiRequest(`/api/admin/cars/${encodeURIComponent(carId)}`, {
    method: "DELETE",
  });
}

export async function deleteUser(
  userId: string,
): Promise<{ message: string; listings_deactivated?: number }> {
  return apiRequest(`/api/admin/users/${encodeURIComponent(userId)}`, {
    method: "DELETE",
  });
}

export interface SystemHealth {
  status: string;
  environment?: string;
  checks: {
    api: { ok: boolean };
    database: { ok: boolean; error?: string | null };
    redis: { configured: boolean; ok: boolean | null };
    storage: { mode: string; r2_configured: boolean };
    push: Record<string, unknown>;
  };
  counts: {
    users: number;
    active_users: number;
    listings: number;
    active_listings: number;
    pending_reports: number;
    pending_dealers: number;
    messages: number;
    notifications: number;
  };
  message?: string;
}

export async function fetchSystemHealth(): Promise<SystemHealth> {
  return apiRequest<SystemHealth>("/api/admin/system/health");
}

export async function fetchReports(params: {
  page?: number;
  per_page?: number;
  status?: string;
  type?: string;
}): Promise<{ reports: AdminReport[]; pagination: Pagination }> {
  return apiRequest(`/api/admin/reports${buildQuery(params)}`);
}

export async function updateReport(
  reportType: "user" | "listing",
  reportId: number,
  status: string,
  adminNotes?: string,
): Promise<void> {
  await apiRequest(`/api/admin/reports/${reportType}/${reportId}`, {
    method: "PATCH",
    body: JSON.stringify({
      status,
      ...(adminNotes ? { admin_notes: adminNotes } : {}),
    }),
  });
}

export async function fetchDealers(
  status = "all",
  params: { page?: number; per_page?: number } = {},
): Promise<{
  dealers: User[];
  pagination: Pagination;
  counts: {
    all: number;
    pending: number;
    approved: number;
    rejected: number;
  };
}> {
  const page = params.page ?? 1;
  const perPage = params.per_page ?? 20;
  const raw = await apiRequest<{
    dealers?: User[];
    pagination?: Pagination;
    counts?: {
      all: number;
      pending: number;
      approved: number;
      rejected: number;
    };
  }>(
    `/api/admin/dealers${buildQuery({
      status,
      page,
      per_page: perPage,
    })}`,
  );

  const dealers = raw.dealers ?? [];
  const total = raw.pagination?.total ?? dealers.length;
  const pages = raw.pagination?.pages ?? Math.max(1, Math.ceil(total / perPage) || 1);

  return {
    dealers,
    pagination: raw.pagination ?? {
      page,
      per_page: perPage,
      total,
      pages,
      has_next: page < pages,
      has_prev: page > 1,
    },
    counts: raw.counts ?? {
      all: status === "all" ? total : 0,
      pending: status === "pending" ? total : 0,
      approved: status === "approved" ? total : 0,
      rejected: status === "rejected" ? total : 0,
    },
  };
}

export async function fetchPendingDealers(): Promise<{ dealers: User[] }> {
  return apiRequest("/api/admin/dealers/pending");
}

export async function approveDealer(userId: string): Promise<void> {
  await apiRequest(`/api/admin/dealers/${encodeURIComponent(userId)}/approve`, {
    method: "POST",
  });
}

export async function rejectDealer(userId: string, reason?: string): Promise<void> {
  await apiRequest(`/api/admin/dealers/${encodeURIComponent(userId)}/reject`, {
    method: "POST",
    body: JSON.stringify(reason ? { reason } : {}),
  });
}

export async function fetchMessages(params: {
  page?: number;
  per_page?: number;
  search?: string;
  is_read?: boolean;
  car_id?: string;
}): Promise<{ messages: Message[]; pagination: Pagination }> {
  return apiRequest(`/api/admin/messages${buildQuery(params)}`);
}

export async function fetchNotifications(params: {
  page?: number;
  per_page?: number;
  type?: string;
  is_read?: boolean;
}): Promise<{ notifications: Notification[]; pagination: Pagination }> {
  return apiRequest(`/api/admin/notifications${buildQuery(params)}`);
}

export async function fetchUserActions(params: {
  page?: number;
  per_page?: number;
  action_type?: string;
  target_type?: string;
  user_id?: string;
  scope?: "all" | "admin" | "user";
}): Promise<{ actions: UserAction[]; pagination: Pagination }> {
  return apiRequest(`/api/admin/user-actions${buildQuery(params)}`);
}

export async function fetchAnalyticsOverview(): Promise<AnalyticsOverview> {
  return apiRequest<AnalyticsOverview>("/api/admin/analytics/overview");
}

export async function fetchInsights(days = 14): Promise<InsightsData> {
  return apiRequest<InsightsData>(`/api/admin/insights${buildQuery({ days })}`);
}

export async function fetchSavedSearches(params: {
  page?: number;
  per_page?: number;
  search?: string;
}): Promise<{ saved_searches: SavedSearch[]; pagination: Pagination }> {
  return apiRequest(`/api/admin/saved-searches${buildQuery(params)}`);
}

export interface NavBadges {
  pendingReports: number;
  pendingDealers: number;
  users: number;
  listings: number;
  dealers: number;
  messages: number;
  notifications: number;
  savedSearches: number;
  auditLog: number;
}

const EMPTY_NAV_BADGES: NavBadges = {
  pendingReports: 0,
  pendingDealers: 0,
  users: 0,
  listings: 0,
  dealers: 0,
  messages: 0,
  notifications: 0,
  savedSearches: 0,
  auditLog: 0,
};

export async function fetchNavBadges(): Promise<NavBadges> {
  try {
    const s = await apiRequest<{
      pending_reports?: number;
      pending_dealers?: number;
      users?: number;
      listings?: number;
      dealers?: number;
      messages?: number;
      notifications?: number;
      saved_searches?: number;
      audit_log?: number;
    }>("/api/admin/meta/badges");
    return {
      pendingReports: s.pending_reports ?? 0,
      pendingDealers: s.pending_dealers ?? 0,
      users: s.users ?? 0,
      listings: s.listings ?? 0,
      dealers: s.dealers ?? 0,
      messages: s.messages ?? 0,
      notifications: s.notifications ?? 0,
      savedSearches: s.saved_searches ?? 0,
      auditLog: s.audit_log ?? 0,
    };
  } catch (first) {
    // Network / CORS: don't fire a second request that will fail the same way.
    if (first instanceof ApiRequestError && first.status === 0) {
      return EMPTY_NAV_BADGES;
    }
    try {
      // Older API deploys without /meta/badges
      const dashboard = await fetchDashboard();
      const s = dashboard.stats;
      return {
        pendingReports: s.pending_reports ?? 0,
        pendingDealers: s.pending_dealers ?? 0,
        users: s.total_users ?? 0,
        listings: s.total_cars ?? 0,
        dealers: s.dealer_accounts ?? 0,
        messages: s.total_messages ?? 0,
        notifications: s.total_notifications ?? 0,
        savedSearches: s.total_saved_searches ?? 0,
        auditLog: s.total_user_actions ?? 0,
      };
    } catch {
      return EMPTY_NAV_BADGES;
    }
  }
}
