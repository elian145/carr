"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useState } from "react";
import { DataTable, Td, Th } from "@/components/DataTable";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { refreshNavBadges } from "@/components/NavBadges";
import { useAuth } from "@/context/AuthContext";
import { useConfirm } from "@/context/ConfirmContext";
import { useToast } from "@/context/ToastContext";
import {
  deleteUser,
  fetchUserDetail,
  updateUserAdminRole,
  updateUserStatus,
} from "@/lib/api";
import { listingPublicUrl } from "@/lib/export";
import {
  displayName,
  formatDate,
  formatNumber,
  formatPrice,
  listingTitle,
} from "@/lib/format";
import { ADMIN_ROLE_LABELS, hasPermission, roleLabel } from "@/lib/permissions";

const ROLE_OPTIONS = Object.keys(ADMIN_ROLE_LABELS);

export default function UserDetailPage() {
  const params = useParams();
  const userId = String(params.id || "");
  const { user: me } = useAuth();
  const toast = useToast();
  const { confirm } = useConfirm();
  const [busy, setBusy] = useState(false);
  const canWriteUsers = hasPermission(me, "users.write");
  const canManageRoles = hasPermission(me, "users.role");

  const { data, error, loading, reload } = useAsyncData(
    () => fetchUserDetail(userId),
    [userId],
  );

  async function toggleActive(current: boolean) {
    const activating = !current;
    const ok = await confirm({
      title: activating ? "Activate account?" : "Deactivate account?",
      description: activating
        ? "The user will be able to sign in again."
        : "The user will be blocked from signing in until reactivated.",
      confirmLabel: activating ? "Activate" : "Deactivate",
      tone: activating ? "brand" : "danger",
    });
    if (!ok) return;

    setBusy(true);
    try {
      await updateUserStatus(userId, activating);
      toast.success(activating ? "Account activated" : "Account deactivated");
      reload();
      refreshNavBadges();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed");
    } finally {
      setBusy(false);
    }
  }

  async function handleDelete() {
    const ok = await confirm({
      title: "Deactivate user and hide listings?",
      description:
        "This soft-deletes the account (cannot sign in) and deactivates their active listings. Admins cannot be deleted this way.",
      confirmLabel: "Deactivate user",
      tone: "danger",
    });
    if (!ok) return;

    setBusy(true);
    try {
      const result = await deleteUser(userId);
      toast.success(
        `${result.message}${
          result.listings_deactivated
            ? ` · ${result.listings_deactivated} listing(s) hidden`
            : ""
        }`,
      );
      refreshNavBadges();
      reload();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Delete failed");
    } finally {
      setBusy(false);
    }
  }

  async function saveRole(nextRole: string, grantAdmin: boolean) {
    const ok = await confirm({
      title: grantAdmin ? "Update admin role?" : "Revoke admin access?",
      description: grantAdmin
        ? `Set this user to ${roleLabel(nextRole)}.`
        : "They will lose access to the admin panel.",
      confirmLabel: grantAdmin ? "Save role" : "Revoke admin",
      tone: grantAdmin ? "brand" : "danger",
    });
    if (!ok) return;

    setBusy(true);
    try {
      await updateUserAdminRole(
        userId,
        grantAdmin
          ? { is_admin: true, admin_role: nextRole }
          : { is_admin: false },
      );
      toast.success(grantAdmin ? "Admin role updated" : "Admin access revoked");
      reload();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Role update failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <AsyncPageBody
      title="User details"
      description={userId}
      data={data}
      error={error}
      loading={loading}
      reload={reload}
      actions={
        <Link
          href="/users"
          className="rounded-lg border border-surface-border px-3 py-2 text-sm hover:bg-white/5"
        >
          ← Back
        </Link>
      }
    >
      {(detail) => {
        const u = detail.user;
        const currentRole = u.admin_role || (u.is_admin ? "super_admin" : "");
        return (
          <div className="space-y-8">
            <section className="rounded-xl border border-surface-border bg-surface-card p-6">
              <div className="flex flex-wrap items-start justify-between gap-4">
                <div>
                  <h2 className="text-xl font-semibold">{displayName(u)}</h2>
                  <p className="mt-1 text-sm text-surface-muted">@{u.username}</p>
                </div>
                {canWriteUsers ? (
                  <div className="flex flex-wrap gap-2">
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => toggleActive(!!u.is_active)}
                      className="rounded-lg bg-brand-700 px-4 py-2 text-sm hover:bg-brand-600 disabled:opacity-50"
                    >
                      {u.is_active ? "Deactivate account" : "Activate account"}
                    </button>
                    {!u.is_admin ? (
                      <button
                        type="button"
                        disabled={busy}
                        onClick={handleDelete}
                        className="rounded-lg border border-red-800/60 bg-red-950/40 px-4 py-2 text-sm text-red-200 hover:bg-red-900/40 disabled:opacity-50"
                      >
                        Soft-delete user
                      </button>
                    ) : null}
                  </div>
                ) : null}
              </div>
              <dl className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                <div>
                  <dt className="text-xs text-surface-muted">Email</dt>
                  <dd className="mt-1 text-sm">{u.email || "—"}</dd>
                </div>
                <div>
                  <dt className="text-xs text-surface-muted">Phone</dt>
                  <dd className="mt-1 text-sm">{u.phone_number || "—"}</dd>
                </div>
                <div>
                  <dt className="text-xs text-surface-muted">Account</dt>
                  <dd className="mt-1 text-sm capitalize">
                    {u.account_type || "user"}
                    {u.dealer_status && u.dealer_status !== "none"
                      ? ` · ${u.dealer_status}`
                      : ""}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs text-surface-muted">Status</dt>
                  <dd className="mt-1 text-sm">
                    {u.is_active ? "Active" : "Inactive"}
                    {u.is_admin ? ` · ${roleLabel(u.admin_role)}` : ""}
                    {u.is_verified ? " · Verified" : ""}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs text-surface-muted">Joined</dt>
                  <dd className="mt-1 text-sm">{formatDate(u.created_at)}</dd>
                </div>
                <div>
                  <dt className="text-xs text-surface-muted">Last login</dt>
                  <dd className="mt-1 text-sm">{formatDate(u.last_login)}</dd>
                </div>
              </dl>
            </section>

            {canManageRoles && me?.id !== u.id ? (
              <section className="rounded-xl border border-surface-border bg-surface-card p-6">
                <h3 className="text-lg font-medium">Admin role</h3>
                <p className="mt-1 text-sm text-surface-muted">
                  Super admins can grant panel access and assign a role.
                </p>
                <div className="mt-4 flex flex-wrap items-end gap-3">
                  <label className="block text-sm">
                    <span className="text-xs text-surface-muted">Role</span>
                    <select
                      className="mt-1 block rounded-lg border border-surface-border bg-black/20 px-3 py-2"
                      defaultValue={currentRole || "moderator"}
                      id="admin-role-select"
                      disabled={busy}
                    >
                      {ROLE_OPTIONS.map((r) => (
                        <option key={r} value={r}>
                          {ADMIN_ROLE_LABELS[r]}
                        </option>
                      ))}
                    </select>
                  </label>
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => {
                      const el = document.getElementById(
                        "admin-role-select",
                      ) as HTMLSelectElement | null;
                      void saveRole(el?.value || "moderator", true);
                    }}
                    className="rounded-lg bg-brand-700 px-4 py-2 text-sm hover:bg-brand-600 disabled:opacity-50"
                  >
                    {u.is_admin ? "Update role" : "Grant admin"}
                  </button>
                  {u.is_admin ? (
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => void saveRole("moderator", false)}
                      className="rounded-lg border border-red-800/60 px-4 py-2 text-sm text-red-200 hover:bg-red-950/40 disabled:opacity-50"
                    >
                      Revoke admin
                    </button>
                  ) : null}
                </div>
              </section>
            ) : null}

            {u.dealership_name ||
            (u.dealer_status && u.dealer_status !== "none") ? (
              <section className="rounded-xl border border-surface-border bg-surface-card p-6">
                <h3 className="text-lg font-medium">Dealership profile</h3>
                <dl className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                  <div>
                    <dt className="text-xs text-surface-muted">Name</dt>
                    <dd className="mt-1 text-sm">{u.dealership_name || "—"}</dd>
                  </div>
                  <div>
                    <dt className="text-xs text-surface-muted">Location</dt>
                    <dd className="mt-1 text-sm">
                      {u.dealership_location || "—"}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-xs text-surface-muted">Phone</dt>
                    <dd className="mt-1 text-sm">
                      {(u.dealership_phones && u.dealership_phones.length
                        ? u.dealership_phones.join(", ")
                        : u.dealership_phone) || "—"}
                    </dd>
                  </div>
                  <div className="sm:col-span-2 lg:col-span-3">
                    <dt className="text-xs text-surface-muted">Description</dt>
                    <dd className="mt-1 whitespace-pre-wrap text-sm text-surface-muted">
                      {u.dealership_description || "—"}
                    </dd>
                  </div>
                  <div className="sm:col-span-2 lg:col-span-3">
                    <dt className="text-xs text-surface-muted">Opening hours</dt>
                    <dd className="mt-1 text-sm text-surface-muted">
                      {typeof u.dealership_opening_hours === "string"
                        ? u.dealership_opening_hours
                        : u.dealership_opening_hours
                          ? JSON.stringify(u.dealership_opening_hours)
                          : "—"}
                    </dd>
                  </div>
                </dl>
                {u.dealer_status === "pending" ? (
                  <p className="mt-4 text-sm text-amber-300">
                    Application pending — review on{" "}
                    <Link href="/dealers" className="underline hover:text-white">
                      Dealers
                    </Link>
                    .
                  </p>
                ) : null}
              </section>
            ) : null}

            <section>
              <h3 className="mb-3 text-lg font-medium">
                Listings ({detail.cars.length})
              </h3>
              <DataTable
                empty={detail.cars.length === 0}
                emptyTitle="No listings yet"
                emptyDescription="This account has not published any cars."
              >
                <thead>
                  <tr>
                    <Th>Listing</Th>
                    <Th>Price</Th>
                    <Th>Status</Th>
                    <Th>Views</Th>
                    <Th></Th>
                  </tr>
                </thead>
                <tbody>
                  {detail.cars.map((c) => (
                    <tr key={c.id}>
                      <Td>
                        <Link
                          href={`/listings/${c.id}`}
                          className="font-medium text-brand-300 hover:underline"
                        >
                          {listingTitle(c)}
                        </Link>
                      </Td>
                      <Td>{formatPrice(c.price)}</Td>
                      <Td>{c.is_active ? "Active" : "Inactive"}</Td>
                      <Td>{formatNumber(c.views_count)}</Td>
                      <Td>
                        <a
                          href={listingPublicUrl(c.id)}
                          target="_blank"
                          rel="noreferrer"
                          className="text-xs text-brand-400 hover:underline"
                        >
                          Public ↗
                        </a>
                      </Td>
                    </tr>
                  ))}
                </tbody>
              </DataTable>
            </section>

            <section>
              <h3 className="mb-3 text-lg font-medium">Recent actions</h3>
              <DataTable empty={detail.recent_actions.length === 0}>
                <thead>
                  <tr>
                    <Th>Action</Th>
                    <Th>Target</Th>
                    <Th>When</Th>
                  </tr>
                </thead>
                <tbody>
                  {detail.recent_actions.map((a) => (
                    <tr key={a.id}>
                      <Td className="font-medium">{a.action_type}</Td>
                      <Td className="text-surface-muted">
                        {a.target_type ? `${a.target_type}: ` : ""}
                        {a.target_id || "—"}
                      </Td>
                      <Td className="text-surface-muted">
                        {formatDate(a.created_at)}
                      </Td>
                    </tr>
                  ))}
                </tbody>
              </DataTable>
            </section>
          </div>
        );
      }}
    </AsyncPageBody>
  );
}
