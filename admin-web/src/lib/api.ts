import { apiRequest } from "./auth";
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
): Promise<{ dealers: User[] }> {
  return apiRequest(`/api/admin/dealers${buildQuery({ status })}`);
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

export async function fetchNavBadges(): Promise<NavBadges> {
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
}
