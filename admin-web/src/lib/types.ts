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
  dealership_socials?: {
    facebook?: string;
    instagram?: string;
    tiktok?: string;
  };
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

export interface CarImage {
  id?: number;
  image_url: string;
  is_primary?: boolean;
  order?: number;
  kind?: string;
  focus_y?: number | null;
  image_width?: number | null;
  image_height?: number | null;
}

export interface AdminImage extends CarImage {
  created_at?: string;
  car?: {
    id: string;
    title?: string;
    brand?: string;
    model?: string;
    status?: string;
  } | null;
  seller?: {
    id: string;
    username?: string;
  } | null;
}

export interface CarVideo {
  id?: number;
  video_url: string;
  thumbnail_url?: string | null;
  duration?: number | null;
  order?: number;
}

export interface CarListing {
  id: string;
  title?: string;
  brand?: string;
  model?: string;
  trim?: string;
  year?: number;
  mileage?: number;
  engine_type?: string;
  fuel_type?: string;
  transmission?: string;
  drive_type?: string;
  condition?: string;
  body_type?: string;
  title_status?: string;
  damaged_parts?: number | null;
  seating?: number;
  color?: string;
  fuel_economy?: string;
  vin?: string;
  engine_size?: number | null;
  cylinder_count?: number | null;
  cylinders?: number | null;
  region_specs?: string;
  plate_type?: string;
  plate_city?: string;
  price?: number;
  currency?: string;
  location?: string;
  latitude?: number | null;
  longitude?: number | null;
  status?: string;
  is_active?: boolean;
  is_featured?: boolean;
  views_count?: number;
  created_at?: string;
  updated_at?: string;
  seller_id?: string;
  seller?: User;
  description?: string;
  images?: CarImage[];
  videos?: CarVideo[];
  ai_analyzed?: boolean;
  ai_detected_brand?: string;
  ai_detected_model?: string;
  ai_detected_color?: string;
  ai_detected_body_type?: string;
  ai_detected_condition?: string | null;
  ai_confidence_score?: number | null;
  ai_analysis_timestamp?: string | null;
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

/** A seller's pending edit of a published listing (see kk/listing_revisions.py). */
export interface ListingRevision {
  id: string;
  status: "editing" | "pending" | "rejected";
  rejection_reason?: string | null;
  submitted_at?: string | null;
  reviewed_at?: string | null;
  updated_at?: string | null;
  /** Must be sent back on approve/reject: proves the admin reviewed THIS content. */
  revision_token: string;
  changed_fields: string[];
  media?: {
    ready: boolean;
    in_flight: number;
    failed: number;
    failed_cover?: boolean;
    approvable?: boolean;
    total: number;
  };
  /** The PROPOSED version (only on the detail view). */
  car?: CarListing;
  /** The approved listing, summarised (only on the list view). */
  listing?: {
    id: string;
    title?: string;
    brand?: string;
    model?: string;
    year?: number;
    price?: number | null;
    currency?: string;
    status?: string;
    image_url?: string | null;
    seller?: { id: string; username?: string } | null;
  };
}

export interface CarDetail {
  car: CarListing;
  analytics: ListingAnalytics | null;
  reports: AdminReport[];
  pending_revision?: ListingRevision | null;
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

// ---------------------------------------------------------------------------
// Auto moderation (mirrors kk/routes/admin_auto_moderation.py)
// ---------------------------------------------------------------------------

export type AutoModerationMode = "off" | "shadow" | "live";

export interface AutoModerationSettings {
  mode: AutoModerationMode;
  kill_switch: boolean;
  kill_switch_reason: string | null;
  kill_switch_by: string | null;
  kill_switch_at: string | null;
  auto_approve_new_listings: boolean;
  auto_approve_revisions: boolean;
  require_ai_for_auto_approve: boolean;
  /** Computed by the server: the AI check is mandatory unless the server operator opted out. */
  ai_required_effective?: boolean;
  min_photos: number;
  min_image_side_px: number;
  min_year: number;
  max_mileage: number;
  /** Listed as New above this odometer reading (km) is suspicious. */
  new_max_mileage_km?: number;
  /** Soft review signal: km per year of model age above which mileage is looked at. */
  max_annual_mileage_km?: number;
  max_listings_per_24h: number;
  price_change_review_pct: number;
  flag_contact_in_description: boolean;
  min_seller_prior_approved: number;
  dealers_count_as_trusted: boolean;
  listing_payment_required: boolean;
  ai: {
    send_images: boolean;
    max_images: number;
    max_total_images: number;
    timeout_seconds: number;
    min_confidence: number;
    only_if_candidate: boolean;
  };
  retry: {
    max_attempts: number;
    backoff_seconds: number[];
    apply_max_age_seconds: number;
  };
  alerts: {
    enabled: boolean;
    channels: string[];
    email_recipients: string[];
    include_shadow: boolean;
    alert_on_routine: boolean;
    notify_on_hold: boolean;
    max_per_hour: number;
  };
  gate: {
    window_days: number;
    min_samples: number;
    max_unsafe_approve_rate: number;
  };
}

export interface ShadowReport {
  window_days: number;
  compared: number;
  awaiting_human_outcome: number;
  matrix: Record<string, Record<string, number>>;
  would_auto_approve: number;
  unsafe_approvals: number;
  unsafe_approve_rate: number | null;
  over_flagged: number;
  over_flag_rate: number | null;
  agreement_rate: number | null;
  automation_coverage: number | null;
  gate: {
    min_samples: number;
    max_unsafe_approve_rate: number;
    passed: boolean;
    problems: string[];
  };
}

export interface AutoModerationReadiness {
  ai_required: boolean;
  ai_configured: boolean;
  /** True only when live mode is active and nothing blocks an automatic approval. */
  auto_approval_possible: boolean;
  blockers: string[];
  notes: string[];
}

export interface AutoModerationSettingsResponse {
  settings: AutoModerationSettings;
  effective_mode: AutoModerationMode;
  kill_switch_active: boolean;
  readiness?: AutoModerationReadiness;
  environment: {
    disabled: boolean;
    kill_switch_forced: boolean;
    live_allowed: boolean;
    ai_provider: string;
    ai_model: string | null;
    ai_configured: boolean;
    rules_only_allowed?: boolean;
    telegram_configured: boolean;
    admin_web_base_url_configured: boolean;
  };
  shadow_report?: ShadowReport;
  warning?: string;
}

export interface AutoModerationStats {
  days: number;
  evaluated: number;
  by_mode_decision: Record<string, number>;
  by_outcome: Record<string, number>;
  by_subject_type: Record<string, number>;
  auto_approved: number;
  post_approval_reversals: number;
  post_approval_reversal_rate: number | null;
  failed_evaluations: number;
  error_rate: number | null;
  apply_refusals: number;
  stale_discards: number;
  alerts_sent: number;
  ai: {
    calls: number;
    unavailable: number;
    unavailable_rate: number | null;
    avg_latency_ms: number | null;
  };
  daily: Array<Record<string, number | string>>;
  truncated: boolean;
}

export interface AutoModerationReason {
  code: string;
  level: "hold" | "review" | "info";
  check?: string;
  suspicious?: boolean;
  /** Specific facts behind the reason (e.g. "Electric powertrain, but the listing also states a 0.7 L engine and 3 cylinders"). */
  detail?: string | null;
  /** Short plain-language title, added by the server (not stored on the run). */
  label?: string;
  /** One-sentence explanation for the reviewing admin, added by the server. */
  message?: string;
}

export interface AutoModerationEvent {
  id: number;
  type: string;
  actor: string | null;
  data: Record<string, unknown> | null;
  created_at: string | null;
}

export interface AutoModerationRun {
  id: string;
  subject_type: "listing" | "revision";
  mode: "shadow" | "live";
  status: string;
  decision: "AUTO_APPROVE" | "NEEDS_REVIEW" | "HOLD" | null;
  outcome: string | null;
  applied: boolean;
  applied_at: string | null;
  attempts: number;
  reason_codes: string[];
  /** Plain-language titles parallel to `reason_codes` (older servers omit it). */
  reason_labels?: string[];
  suspicious: boolean;
  admin_outcome: string | null;
  admin_outcome_by: string | null;
  admin_outcome_at: string | null;
  override_action: string | null;
  override_by: string | null;
  override_at: string | null;
  override_note: string | null;
  created_at: string | null;
  decided_at: string | null;
  listing: {
    id: string | null;
    title: string | null;
    status: string | null;
    is_active: boolean | null;
    price: number | null;
    currency: string | null;
  };
  seller: { id: string; username: string } | null;
  revision_id: string | null;
  // detail only
  reasons?: AutoModerationReason[];
  checks?: Record<string, string> | null;
  ai?: Record<string, unknown> | null;
  content_token?: string;
  engine_version?: string;
  error?: string | null;
  events?: AutoModerationEvent[];
}

export type AutoModerationView =
  | "all"
  | "auto_approved"
  | "would_approve"
  | "flagged"
  | "held"
  | "errors";

export type AutoModerationOverrideAction =
  | "approve"
  | "revoke"
  | "require_review"
  | "clear_review_pin";
