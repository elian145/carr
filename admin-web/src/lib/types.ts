export interface User {
  id: string;
  username: string;
  email?: string;
  phone_number?: string;
  first_name?: string;
  last_name?: string;
  is_admin?: boolean;
  is_active?: boolean;
  is_verified?: boolean;
  account_type?: string;
  dealer_status?: string;
  dealership_name?: string;
  dealership_location?: string;
  dealership_phone?: string;
  created_at?: string;
  last_login?: string;
  updated_at?: string;
}

export interface Pagination {
  page: number;
  per_page: number;
  total: number;
  pages: number;
  has_next: boolean;
  has_prev: boolean;
}

export interface DashboardStats {
  total_users: number;
  active_users: number;
  inactive_users?: number;
  total_cars: number;
  active_cars: number;
  inactive_cars?: number;
  total_messages: number;
  total_notifications: number;
  pending_reports?: number;
  pending_user_reports?: number;
  pending_listing_reports?: number;
  pending_dealers?: number;
}

export interface DashboardData {
  stats: DashboardStats;
  recent_activity: {
    users: User[];
    cars: CarListing[];
    messages: Message[];
  };
  user_actions: { action_type: string; count: number }[];
}

export interface CarListing {
  id: string;
  title?: string;
  brand?: string;
  model?: string;
  year?: number;
  price?: number;
  location?: string;
  status?: string;
  is_active?: boolean;
  views_count?: number;
  created_at?: string;
  seller_id?: string;
}

export interface Message {
  id: string;
  content?: string;
  sender_id?: string;
  receiver_id?: string;
  car_id?: string;
  created_at?: string;
}

export interface Notification {
  id: string;
  title?: string;
  message?: string;
  notification_type?: string;
  is_read?: boolean;
  created_at?: string;
}

export interface UserAction {
  id: number;
  action_type: string;
  target_type?: string;
  target_id?: string;
  action_metadata?: Record<string, unknown>;
  created_at?: string;
}

export interface UserDetail {
  user: User;
  cars: CarListing[];
  recent_actions: UserAction[];
}

export interface AdminReport {
  id: number;
  type: "user" | "listing";
  status: string;
  reason?: string;
  details?: string;
  admin_notes?: string;
  created_at?: string;
  reporter?: { id?: string; username?: string };
  reported_user?: { id?: string; username?: string };
  listing?: { id?: string; title?: string; brand?: string; model?: string };
}

export interface ApiError {
  message: string;
}
