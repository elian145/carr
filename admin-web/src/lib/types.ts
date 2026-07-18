export interface User {
  id: string;
  username: string;
  email?: string;
  phone_number?: string;
  first_name?: string;
  last_name?: string;
  is_admin?: boolean;
  admin_role?: string | null;
  permissions?: string[];
  is_active?: boolean;
  is_verified?: boolean;
  account_type?: string;
  dealer_status?: string;
  dealership_name?: string;
  dealership_location?: string;
  dealership_phone?: string;
  dealership_phones?: string[];
  dealership_description?: string;
  dealership_cover_picture?: string;
  dealership_opening_hours?: string | Record<string, unknown>;
  dealer_application?: DealerApplication;
  is_featured_dealer?: boolean;
  created_at?: string;
  last_login?: string;
  updated_at?: string;
}

export interface DealerDecision {
  id: string;
  decision: string;
  reason?: string | null;
  application_snapshot?: Record<string, unknown>;
  reviewer?: { id: string; username: string } | null;
  created_at?: string;
}

export interface DealerApplication {
  id: string;
  status: string;
  dealership_name: string;
  dealership_phone: string;
  dealership_phones?: string[];
  dealership_location: string;
  dealership_description?: string | null;
  business_registration_number?: string | null;
  document_urls?: string[];
  has_verification_photo?: boolean;
  verification_photo_url?: string;
  review_reason?: string | null;
  submitted_at?: string | null;
  reviewed_at?: string | null;
  created_at?: string;
  updated_at?: string;
  decisions?: DealerDecision[];
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
  dealer_accounts?: number;
  featured_cars?: number;
  total_saved_searches?: number;
  total_user_actions?: number;
  total_listing_views?: number;
  total_listing_messages?: number;
  total_listing_calls?: number;
  total_listing_favorites?: number;
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
  is_featured?: boolean;
  views_count?: number;
  created_at?: string;
  updated_at?: string;
  seller_id?: string;
  seller?: User;
  description?: string;
  images?: { image_url: string; is_primary?: boolean }[];
}

export interface ListingAnalytics {
  listing_id?: string;
  views?: number;
  messages?: number;
  calls?: number;
  shares?: number;
  favorites?: number;
  brand?: string;
  model?: string;
  year?: number;
  price?: number;
}

export interface CarDetail {
  car: CarListing;
  analytics: ListingAnalytics | null;
  reports: AdminReport[];
}

export interface Message {
  id: string;
  content?: string;
  sender_id?: string;
  receiver_id?: string;
  car_id?: string;
  message_type?: string;
  is_read?: boolean;
  created_at?: string;
  sender_name?: string;
  sender_username?: string;
  receiver_name?: string;
  receiver_username?: string;
}

export interface Notification {
  id: string;
  title?: string;
  message?: string;
  notification_type?: string;
  is_read?: boolean;
  created_at?: string;
  user_public_id?: string;
  user_username?: string;
}

export interface UserAction {
  id: number;
  action_type: string;
  target_type?: string;
  target_id?: string;
  action_metadata?: Record<string, unknown>;
  created_at?: string;
  user_public_id?: string;
  user_username?: string;
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

export interface GlobalSearchResults {
  users: User[];
  cars: CarListing[];
}

export interface AnalyticsOverview {
  totals: {
    views: number;
    messages: number;
    calls: number;
    shares: number;
    favorites: number;
    tracked_listings: number;
  };
  top_listings: ListingAnalytics[];
}

export interface InsightsData {
  signups_by_day: { day: string; count: number }[];
  listings_by_day: { day: string; count: number }[];
  messages_by_day: { day: string; count: number }[];
  top_brands: { brand: string; count: number }[];
  top_locations: { location: string; count: number }[];
}

export interface SavedSearch {
  id: string;
  name: string;
  filters: Record<string, unknown>;
  notify?: boolean;
  auto_saved?: boolean;
  created_at?: string;
  user_public_id?: string;
  user_username?: string;
}

export interface FilterMeta {
  brands: string[];
  listing_statuses: string[];
  action_types: string[];
  notification_types: string[];
  admin_roles?: string[];
}
