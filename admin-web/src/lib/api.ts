import { apiRequest } from "./auth";
import type {
  AdminReport,
  CarListing,
  DashboardData,
  Message,
  Notification,
  Pagination,
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

export async function fetchUsers(params: {
  page?: number;
  per_page?: number;
  search?: string;
}): Promise<{ users: User[]; pagination: Pagination }> {
  const q = new URLSearchParams();
  if (params.page) q.set("page", String(params.page));
  if (params.per_page) q.set("per_page", String(params.per_page));
  if (params.search) q.set("search", params.search);
  const qs = q.toString();
  return apiRequest(`/api/admin/users${qs ? `?${qs}` : ""}`);
}

export async function fetchUserDetail(userId: string): Promise<UserDetail> {
  return apiRequest<UserDetail>(
    `/api/admin/users/${encodeURIComponent(userId)}`,
  );
}

export async function fetchListings(params: {
  page?: number;
  per_page?: number;
  active_only?: boolean;
}): Promise<{ cars: CarListing[]; pagination: Pagination }> {
  const q = new URLSearchParams();
  if (params.page) q.set("page", String(params.page));
  if (params.per_page) q.set("per_page", String(params.per_page));
  if (params.active_only) q.set("active_only", "true");
  const qs = q.toString();
  return apiRequest(`/api/admin/cars${qs ? `?${qs}` : ""}`);
}

export async function fetchReports(params: {
  page?: number;
  per_page?: number;
  status?: string;
  type?: string;
}): Promise<{ reports: AdminReport[]; pagination: Pagination }> {
  const q = new URLSearchParams();
  if (params.page) q.set("page", String(params.page));
  if (params.per_page) q.set("per_page", String(params.per_page));
  if (params.status) q.set("status", params.status);
  if (params.type) q.set("type", params.type);
  const qs = q.toString();
  return apiRequest(`/api/admin/reports${qs ? `?${qs}` : ""}`);
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

export async function fetchPendingDealers(): Promise<{ dealers: User[] }> {
  return apiRequest("/api/admin/dealers/pending");
}

export async function approveDealer(userId: string): Promise<void> {
  await apiRequest(`/api/admin/dealers/${encodeURIComponent(userId)}/approve`, {
    method: "POST",
  });
}

export async function rejectDealer(
  userId: string,
  reason?: string,
): Promise<void> {
  await apiRequest(`/api/admin/dealers/${encodeURIComponent(userId)}/reject`, {
    method: "POST",
    body: JSON.stringify(reason ? { reason } : {}),
  });
}

export async function fetchMessages(params: {
  page?: number;
  per_page?: number;
}): Promise<{ messages: Message[]; pagination: Pagination }> {
  const q = new URLSearchParams();
  if (params.page) q.set("page", String(params.page));
  if (params.per_page) q.set("per_page", String(params.per_page));
  const qs = q.toString();
  return apiRequest(`/api/admin/messages${qs ? `?${qs}` : ""}`);
}

export async function fetchNotifications(params: {
  page?: number;
  per_page?: number;
}): Promise<{ notifications: Notification[]; pagination: Pagination }> {
  const q = new URLSearchParams();
  if (params.page) q.set("page", String(params.page));
  if (params.per_page) q.set("per_page", String(params.per_page));
  const qs = q.toString();
  return apiRequest(`/api/admin/notifications${qs ? `?${qs}` : ""}`);
}

export async function fetchUserActions(params: {
  page?: number;
  per_page?: number;
  action_type?: string;
}): Promise<{ actions: UserAction[]; pagination: Pagination }> {
  const q = new URLSearchParams();
  if (params.page) q.set("page", String(params.page));
  if (params.per_page) q.set("per_page", String(params.per_page));
  if (params.action_type) q.set("action_type", params.action_type);
  const qs = q.toString();
  return apiRequest(`/api/admin/user-actions${qs ? `?${qs}` : ""}`);
}

export async function fetchNavBadges(): Promise<{
  pendingReports: number;
  pendingDealers: number;
}> {
  const dashboard = await fetchDashboard();
  return {
    pendingReports: dashboard.stats.pending_reports ?? 0,
    pendingDealers: dashboard.stats.pending_dealers ?? 0,
  };
}
