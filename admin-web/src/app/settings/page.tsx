"use client";

import { useEffect, useState } from "react";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { useConfirm } from "@/context/ConfirmContext";
import { useToast } from "@/context/ToastContext";
import {
  fetchSettings,
  updateSettings,
  type PlatformSettingsPayload,
} from "@/lib/api";
import { formatDate } from "@/lib/format";

type FormState = {
  app_name: string;
  support_email: string;
  support_phone: string;
  support_whatsapp: string;
  terms_url: string;
  privacy_url: string;
  legal_effective_date: string;
  featured_listing_price: string;
  featured_listing_currency: string;
  dealer_subscription_price: string;
  dealer_subscription_currency: string;
  pricing_notes: string;
  min_app_version: string;
  min_android_build: string;
  min_ios_build: string;
  force_update_message: string;
  android_store_url: string;
  ios_store_url: string;
};

function toForm(payload: PlatformSettingsPayload): FormState {
  const e = payload.effective || {};
  const o = payload.overrides || {};
  const pick = (key: keyof FormState) => {
    const override = o[key];
    if (override !== undefined && override !== null && String(override) !== "") {
      return String(override);
    }
    const eff = e[key];
    return eff === null || eff === undefined ? "" : String(eff);
  };
  return {
    app_name: pick("app_name"),
    support_email: pick("support_email"),
    support_phone: pick("support_phone"),
    support_whatsapp: pick("support_whatsapp"),
    terms_url: pick("terms_url"),
    privacy_url: pick("privacy_url"),
    legal_effective_date: pick("legal_effective_date"),
    featured_listing_price: pick("featured_listing_price"),
    featured_listing_currency: pick("featured_listing_currency") || "USD",
    dealer_subscription_price: pick("dealer_subscription_price"),
    dealer_subscription_currency: pick("dealer_subscription_currency") || "USD",
    pricing_notes: pick("pricing_notes"),
    min_app_version: pick("min_app_version"),
    min_android_build: pick("min_android_build"),
    min_ios_build: pick("min_ios_build"),
    force_update_message: pick("force_update_message"),
    android_store_url: pick("android_store_url"),
    ios_store_url: pick("ios_store_url"),
  };
}

function Field({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <label className="flex flex-col gap-1 text-xs text-surface-muted">
      <span>{label}</span>
      {children}
      {hint ? <span className="text-[11px] opacity-80">{hint}</span> : null}
    </label>
  );
}

const inputClass =
  "rounded-lg border border-surface-border bg-black/30 px-3 py-2 text-sm text-white";

export default function SettingsPage() {
  const toast = useToast();
  const { confirm } = useConfirm();
  const { data, error, loading, reload } = useAsyncData(fetchSettings, []);
  const [form, setForm] = useState<FormState | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (data) setForm(toForm(data));
  }, [data]);

  function setField<K extends keyof FormState>(key: K, value: FormState[K]) {
    setForm((prev) => (prev ? { ...prev, [key]: value } : prev));
  }

  async function handleSave() {
    if (!form) return;
    const ok = await confirm({
      title: "Save settings?",
      description:
        "Contact and legal URL changes apply to the mobile app trust config immediately after save.",
      confirmLabel: "Save",
      tone: "brand",
    });
    if (!ok) return;

    setBusy(true);
    try {
      const payload = await updateSettings({
        app_name: form.app_name,
        support_email: form.support_email,
        support_phone: form.support_phone,
        support_whatsapp: form.support_whatsapp,
        terms_url: form.terms_url,
        privacy_url: form.privacy_url,
        legal_effective_date: form.legal_effective_date,
        featured_listing_price: form.featured_listing_price
          ? Number(form.featured_listing_price)
          : null,
        featured_listing_currency: form.featured_listing_currency,
        dealer_subscription_price: form.dealer_subscription_price
          ? Number(form.dealer_subscription_price)
          : null,
        dealer_subscription_currency: form.dealer_subscription_currency,
        pricing_notes: form.pricing_notes,
        min_app_version: form.min_app_version,
        min_android_build: form.min_android_build,
        min_ios_build: form.min_ios_build,
        force_update_message: form.force_update_message,
        android_store_url: form.android_store_url,
        ios_store_url: form.ios_store_url,
      });
      setForm(toForm(payload));
      toast.success("Settings saved");
      reload();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Save failed");
    } finally {
      setBusy(false);
    }
  }

  async function handleClearOverrides() {
    const ok = await confirm({
      title: "Clear all overrides?",
      description: "Values will fall back to environment defaults on the API.",
      confirmLabel: "Clear",
      tone: "danger",
    });
    if (!ok) return;
    setBusy(true);
    try {
      const payload = await updateSettings({
        app_name: "",
        support_email: "",
        support_phone: "",
        support_whatsapp: "",
        terms_url: "",
        privacy_url: "",
        legal_effective_date: "",
        featured_listing_price: null,
        featured_listing_currency: "",
        dealer_subscription_price: null,
        dealer_subscription_currency: "",
        pricing_notes: "",
        min_app_version: "",
        min_android_build: "",
        min_ios_build: "",
        force_update_message: "",
        android_store_url: "",
        ios_store_url: "",
      });
      setForm(toForm(payload));
      toast.success("Overrides cleared");
      reload();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Clear failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <AsyncPageBody
      title="Settings"
      description="Contact info, legal URLs, and feature pricing"
      data={data}
      error={error}
      loading={loading}
      reload={reload}
      actions={
        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            disabled={busy || !form}
            onClick={handleClearOverrides}
            className="rounded-lg border border-surface-border px-3 py-2 text-sm hover:bg-white/5 disabled:opacity-50"
          >
            Reset to env defaults
          </button>
          <button
            type="button"
            disabled={busy || !form}
            onClick={handleSave}
            className="rounded-lg bg-brand-600 px-4 py-2 text-sm hover:bg-brand-500 disabled:opacity-50"
          >
            {busy ? "Saving…" : "Save changes"}
          </button>
        </div>
      }
    >
      {(payload) =>
        form ? (
          <div className="space-y-6">
            {payload.updated_at ? (
              <p className="text-xs text-surface-muted">
                Last saved {formatDate(payload.updated_at)}
              </p>
            ) : (
              <p className="text-xs text-surface-muted">
                No DB overrides yet — showing environment defaults.
              </p>
            )}

            <section className="rounded-xl border border-surface-border bg-surface-card p-5">
              <h2 className="text-lg font-medium">App & contact</h2>
              <div className="mt-4 grid gap-3 sm:grid-cols-2">
                <Field label="App display name">
                  <input
                    className={inputClass}
                    value={form.app_name}
                    onChange={(e) => setField("app_name", e.target.value)}
                  />
                </Field>
                <Field label="Support email">
                  <input
                    type="email"
                    className={inputClass}
                    value={form.support_email}
                    onChange={(e) => setField("support_email", e.target.value)}
                  />
                </Field>
                <Field label="Support phone">
                  <input
                    className={inputClass}
                    value={form.support_phone}
                    onChange={(e) => setField("support_phone", e.target.value)}
                  />
                </Field>
                <Field label="Support WhatsApp">
                  <input
                    className={inputClass}
                    value={form.support_whatsapp}
                    onChange={(e) => setField("support_whatsapp", e.target.value)}
                  />
                </Field>
              </div>
            </section>

            <section className="rounded-xl border border-surface-border bg-surface-card p-5">
              <h2 className="text-lg font-medium">Legal</h2>
              <p className="mt-1 text-xs text-surface-muted">
                Leave blank to use the API host defaults (`/terms`, `/privacy`).
              </p>
              <div className="mt-4 grid gap-3 sm:grid-cols-2">
                <Field label="Terms URL" hint={`Default: ${payload.defaults.terms_url || "—"}`}>
                  <input
                    className={inputClass}
                    value={form.terms_url}
                    onChange={(e) => setField("terms_url", e.target.value)}
                  />
                </Field>
                <Field
                  label="Privacy URL"
                  hint={`Default: ${payload.defaults.privacy_url || "—"}`}
                >
                  <input
                    className={inputClass}
                    value={form.privacy_url}
                    onChange={(e) => setField("privacy_url", e.target.value)}
                  />
                </Field>
                <Field label="Legal effective date" hint="Shown on legal HTML pages">
                  <input
                    className={inputClass}
                    value={form.legal_effective_date}
                    onChange={(e) =>
                      setField("legal_effective_date", e.target.value)
                    }
                    placeholder="July 13, 2026"
                  />
                </Field>
              </div>
            </section>

            <section className="rounded-xl border border-surface-border bg-surface-card p-5">
              <h2 className="text-lg font-medium">Force update</h2>
              <p className="mt-1 text-xs text-surface-muted">
                Block older mobile builds. Leave version/build fields empty to
                allow all installed versions. Exposed at{" "}
                <code className="text-[11px]">/api/config/app</code>.
              </p>
              <div className="mt-4 grid gap-3 sm:grid-cols-2">
                <Field label="Min app version" hint="Semver, e.g. 1.0.1">
                  <input
                    className={inputClass}
                    value={form.min_app_version}
                    onChange={(e) => setField("min_app_version", e.target.value)}
                    placeholder="1.0.1"
                  />
                </Field>
                <Field label="Force update message">
                  <input
                    className={inputClass}
                    value={form.force_update_message}
                    onChange={(e) =>
                      setField("force_update_message", e.target.value)
                    }
                  />
                </Field>
                <Field label="Min Android build number" hint="versionCode">
                  <input
                    className={inputClass}
                    value={form.min_android_build}
                    onChange={(e) =>
                      setField("min_android_build", e.target.value)
                    }
                    placeholder="4"
                  />
                </Field>
                <Field label="Min iOS build number" hint="CFBundleVersion">
                  <input
                    className={inputClass}
                    value={form.min_ios_build}
                    onChange={(e) => setField("min_ios_build", e.target.value)}
                    placeholder="4"
                  />
                </Field>
                <Field label="Android store URL">
                  <input
                    className={inputClass}
                    value={form.android_store_url}
                    onChange={(e) =>
                      setField("android_store_url", e.target.value)
                    }
                  />
                </Field>
                <Field label="iOS store URL">
                  <input
                    className={inputClass}
                    value={form.ios_store_url}
                    onChange={(e) => setField("ios_store_url", e.target.value)}
                  />
                </Field>
              </div>
            </section>

            <section className="rounded-xl border border-surface-border bg-surface-card p-5">
              <h2 className="text-lg font-medium">Feature & dealer pricing</h2>
              <p className="mt-1 text-xs text-surface-muted">
                Reference-only pricing for ops/marketing. In-app checkout is not
                enabled — deals stay off-platform.
              </p>
              <div className="mt-4 grid gap-3 sm:grid-cols-2">
                <Field label="Featured listing price">
                  <input
                    type="number"
                    step="0.01"
                    className={inputClass}
                    value={form.featured_listing_price}
                    onChange={(e) =>
                      setField("featured_listing_price", e.target.value)
                    }
                  />
                </Field>
                <Field label="Featured listing currency">
                  <input
                    className={inputClass}
                    value={form.featured_listing_currency}
                    onChange={(e) =>
                      setField("featured_listing_currency", e.target.value)
                    }
                  />
                </Field>
                <Field label="Dealer subscription price">
                  <input
                    type="number"
                    step="0.01"
                    className={inputClass}
                    value={form.dealer_subscription_price}
                    onChange={(e) =>
                      setField("dealer_subscription_price", e.target.value)
                    }
                  />
                </Field>
                <Field label="Dealer subscription currency">
                  <input
                    className={inputClass}
                    value={form.dealer_subscription_currency}
                    onChange={(e) =>
                      setField("dealer_subscription_currency", e.target.value)
                    }
                  />
                </Field>
                <Field label="Pricing notes">
                  <textarea
                    rows={3}
                    className={inputClass}
                    value={form.pricing_notes}
                    onChange={(e) => setField("pricing_notes", e.target.value)}
                    placeholder="Internal notes about packages / promos"
                  />
                </Field>
              </div>
            </section>
          </div>
        ) : null
      }
    </AsyncPageBody>
  );
}
