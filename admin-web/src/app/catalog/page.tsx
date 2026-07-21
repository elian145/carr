"use client";

import { useEffect, useState, Fragment } from "react";
import { DataTable, Td, Th } from "@/components/DataTable";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { useAuth } from "@/context/AuthContext";
import { useConfirm } from "@/context/ConfirmContext";
import { useToast } from "@/context/ToastContext";
import {
  createCatalogBodyType,
  createCatalogBrand,
  createCatalogModel,
  fetchCatalogBodyTypes,
  fetchCatalogBrands,
  fetchCatalogModels,
  fetchCatalogSummary,
  seedCatalog,
  updateCatalogBodyType,
  updateCatalogBrand,
  updateCatalogModel,
  type CatalogBrand,
  type CatalogBodyType,
  type CatalogVehicleModel,
} from "@/lib/api";
import { hasPermission } from "@/lib/permissions";

type Tab = "brands" | "body";

const inputClass =
  "rounded-lg border border-surface-border bg-black/30 px-3 py-2 text-sm text-white";

export default function CatalogPage() {
  const toast = useToast();
  const { confirm } = useConfirm();
  const { user } = useAuth();
  const canWrite = hasPermission(user, "catalog.write");
  const [tab, setTab] = useState<Tab>("brands");
  const [q, setQ] = useState("");
  const [busy, setBusy] = useState(false);
  const [newBrand, setNewBrand] = useState("");
  const [newBody, setNewBody] = useState("");
  const [expandedId, setExpandedId] = useState<number | null>(null);
  const [models, setModels] = useState<CatalogVehicleModel[]>([]);
  const [modelsLoading, setModelsLoading] = useState(false);
  const [newModel, setNewModel] = useState("");

  const summary = useAsyncData(fetchCatalogSummary, []);
  const brands = useAsyncData(
    () => fetchCatalogBrands({ q: q || undefined }),
    [q],
  );
  const bodies = useAsyncData(fetchCatalogBodyTypes, []);

  useEffect(() => {
    if (expandedId == null) {
      setModels([]);
      return;
    }
    let cancelled = false;
    setModelsLoading(true);
    fetchCatalogModels(expandedId)
      .then((r) => {
        if (!cancelled) setModels(r.models);
      })
      .catch((e) => {
        if (!cancelled) {
          toast.error(e instanceof Error ? e.message : "Failed to load models");
          setModels([]);
        }
      })
      .finally(() => {
        if (!cancelled) setModelsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [expandedId, toast]);

  async function reloadAll() {
    summary.reload();
    brands.reload();
    bodies.reload();
    if (expandedId != null) {
      const r = await fetchCatalogModels(expandedId);
      setModels(r.models);
    }
  }

  async function handleSeed(force: boolean) {
    const ok = await confirm({
      title: force ? "Re-seed catalog from JSON?" : "Seed catalog?",
      description: force
        ? "Upserts all brands/models from assets/car_catalog.json and reactivates matching rows. Does not delete custom entries."
        : "Imports brands/models if the catalog is empty. Safe to run once after deploy.",
      confirmLabel: force ? "Force seed" : "Seed",
      tone: "brand",
    });
    if (!ok) return;
    setBusy(true);
    try {
      const result = await seedCatalog(force);
      toast.success(
        result.skipped_brand_seed
          ? `Body types updated · brands already present (${result.totals?.brands ?? "?"} brands)`
          : `Seeded · +${result.brands_created ?? 0} brands · +${result.models_created ?? 0} models`,
      );
      await reloadAll();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Seed failed");
    } finally {
      setBusy(false);
    }
  }

  async function addBrand() {
    const name = newBrand.trim();
    if (!name) return;
    setBusy(true);
    try {
      await createCatalogBrand({ name });
      setNewBrand("");
      toast.success("Brand created");
      await reloadAll();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Create failed");
    } finally {
      setBusy(false);
    }
  }

  async function toggleBrand(b: CatalogBrand) {
    setBusy(true);
    try {
      await updateCatalogBrand(b.id, { is_active: !b.is_active });
      toast.success(b.is_active ? "Brand deactivated" : "Brand activated");
      await reloadAll();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Update failed");
    } finally {
      setBusy(false);
    }
  }

  async function renameBrand(b: CatalogBrand) {
    const name = window.prompt("Brand name", b.name)?.trim();
    if (!name || name === b.name) return;
    setBusy(true);
    try {
      await updateCatalogBrand(b.id, { name });
      toast.success("Brand renamed");
      await reloadAll();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Rename failed");
    } finally {
      setBusy(false);
    }
  }

  async function addModel(brandId: number) {
    const name = newModel.trim();
    if (!name) return;
    setBusy(true);
    try {
      await createCatalogModel({ brand_id: brandId, name });
      setNewModel("");
      toast.success("Model created");
      const r = await fetchCatalogModels(brandId);
      setModels(r.models);
      brands.reload();
      summary.reload();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Create failed");
    } finally {
      setBusy(false);
    }
  }

  async function toggleModel(m: CatalogVehicleModel) {
    setBusy(true);
    try {
      await updateCatalogModel(m.id, { is_active: !m.is_active });
      toast.success(m.is_active ? "Model deactivated" : "Model activated");
      const r = await fetchCatalogModels(m.brand_id);
      setModels(r.models);
      brands.reload();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Update failed");
    } finally {
      setBusy(false);
    }
  }

  async function addBodyType() {
    const name = newBody.trim();
    if (!name) return;
    setBusy(true);
    try {
      await createCatalogBodyType({ name });
      setNewBody("");
      toast.success("Body type created");
      bodies.reload();
      summary.reload();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Create failed");
    } finally {
      setBusy(false);
    }
  }

  async function toggleBody(b: CatalogBodyType) {
    setBusy(true);
    try {
      await updateCatalogBodyType(b.id, { is_active: !b.is_active });
      toast.success(b.is_active ? "Deactivated" : "Activated");
      bodies.reload();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Update failed");
    } finally {
      setBusy(false);
    }
  }

  const s = summary.data;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold">Vehicle catalog</h1>
          <p className="mt-1 text-sm text-surface-muted">
            Manage makes, models, and body types used across listings.
          </p>
        </div>
        {canWrite ? (
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              disabled={busy}
              onClick={() => void handleSeed(false)}
              className="rounded-lg border border-surface-border px-3 py-2 text-sm hover:bg-white/5 disabled:opacity-50"
            >
              Seed from JSON
            </button>
            <button
              type="button"
              disabled={busy}
              onClick={() => void handleSeed(true)}
              className="rounded-lg border border-surface-border px-3 py-2 text-sm hover:bg-white/5 disabled:opacity-50"
            >
              Force re-seed
            </button>
          </div>
        ) : null}
      </div>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <div className="rounded-xl border border-surface-border bg-surface-card p-4">
          <p className="text-xs text-surface-muted">Brands</p>
          <p className="mt-1 text-2xl font-semibold">
            {s ? `${s.active_brands}/${s.brands}` : "—"}
          </p>
        </div>
        <div className="rounded-xl border border-surface-border bg-surface-card p-4">
          <p className="text-xs text-surface-muted">Models</p>
          <p className="mt-1 text-2xl font-semibold">
            {s ? `${s.active_models}/${s.models}` : "—"}
          </p>
        </div>
        <div className="rounded-xl border border-surface-border bg-surface-card p-4">
          <p className="text-xs text-surface-muted">Trims</p>
          <p className="mt-1 text-2xl font-semibold">
            {s ? `${s.active_trims ?? 0}/${s.trims ?? 0}` : "—"}
          </p>
        </div>
        <div className="rounded-xl border border-surface-border bg-surface-card p-4">
          <p className="text-xs text-surface-muted">Body types</p>
          <p className="mt-1 text-2xl font-semibold">
            {s ? `${s.active_body_types}/${s.body_types}` : "—"}
          </p>
        </div>
      </div>

      <div className="flex gap-2 border-b border-surface-border pb-2">
        <button
          type="button"
          onClick={() => setTab("brands")}
          className={`rounded-lg px-3 py-1.5 text-sm ${
            tab === "brands"
              ? "bg-brand-600/20 text-brand-300"
              : "text-surface-muted hover:bg-white/5"
          }`}
        >
          Brands & models
        </button>
        <button
          type="button"
          onClick={() => setTab("body")}
          className={`rounded-lg px-3 py-1.5 text-sm ${
            tab === "body"
              ? "bg-brand-600/20 text-brand-300"
              : "text-surface-muted hover:bg-white/5"
          }`}
        >
          Body types
        </button>
      </div>

      {tab === "brands" ? (
        <AsyncPageBody
          title="Brands & models"
          data={brands.data}
          error={brands.error}
          loading={brands.loading}
          reload={brands.reload}
          actions={
            <div className="flex flex-wrap items-center gap-2">
              <input
                type="search"
                value={q}
                onChange={(e) => setQ(e.target.value)}
                placeholder="Filter brands…"
                className={inputClass}
              />
              {canWrite ? (
                <>
                  <input
                    type="text"
                    value={newBrand}
                    onChange={(e) => setNewBrand(e.target.value)}
                    placeholder="New brand"
                    className={inputClass}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") void addBrand();
                    }}
                  />
                  <button
                    type="button"
                    disabled={busy || !newBrand.trim()}
                    onClick={() => void addBrand()}
                    className="rounded-lg bg-brand-700 px-3 py-2 text-sm hover:bg-brand-600 disabled:opacity-50"
                  >
                    Add brand
                  </button>
                </>
              ) : null}
            </div>
          }
        >
          {(result) => (
            <DataTable
              empty={!result.brands.length}
              emptyTitle="No brands yet — seed from JSON or add one"
            >
              <thead>
                <tr>
                  <Th>Brand</Th>
                  <Th>Models</Th>
                  <Th>Status</Th>
                  <Th>Actions</Th>
                </tr>
              </thead>
              <tbody>
                {result.brands.map((b) => (
                  <Fragment key={b.id}>
                    <tr className="border-t border-surface-border">
                      <Td>
                        <button
                          type="button"
                          className="text-left text-brand-400 hover:underline"
                          onClick={() =>
                            setExpandedId((id) => (id === b.id ? null : b.id))
                          }
                        >
                          {expandedId === b.id ? "▾ " : "▸ "}
                          {b.name}
                        </button>
                      </Td>
                      <Td>
                        {b.active_model_count ?? "—"}/{b.model_count ?? "—"}
                      </Td>
                      <Td>{b.is_active ? "Active" : "Inactive"}</Td>
                      <Td>
                        {canWrite ? (
                          <div className="flex flex-wrap gap-2">
                            <button
                              type="button"
                              disabled={busy}
                              onClick={() => void renameBrand(b)}
                              className="text-xs text-surface-muted hover:text-white"
                            >
                              Rename
                            </button>
                            <button
                              type="button"
                              disabled={busy}
                              onClick={() => void toggleBrand(b)}
                              className="text-xs text-surface-muted hover:text-white"
                            >
                              {b.is_active ? "Deactivate" : "Activate"}
                            </button>
                          </div>
                        ) : (
                          "—"
                        )}
                      </Td>
                    </tr>
                    {expandedId === b.id ? (
                      <tr className="bg-black/20">
                        <Td colSpan={4}>
                          <div className="space-y-3 p-2">
                            {canWrite ? (
                              <div className="flex flex-wrap gap-2">
                                <input
                                  type="text"
                                  value={newModel}
                                  onChange={(e) => setNewModel(e.target.value)}
                                  placeholder={`New ${b.name} model`}
                                  className={inputClass}
                                  onKeyDown={(e) => {
                                    if (e.key === "Enter") void addModel(b.id);
                                  }}
                                />
                                <button
                                  type="button"
                                  disabled={busy || !newModel.trim()}
                                  onClick={() => void addModel(b.id)}
                                  className="rounded-lg bg-brand-700 px-3 py-2 text-sm hover:bg-brand-600 disabled:opacity-50"
                                >
                                  Add model
                                </button>
                              </div>
                            ) : null}
                            {modelsLoading ? (
                              <p className="text-sm text-surface-muted">
                                Loading models…
                              </p>
                            ) : models.length === 0 ? (
                              <p className="text-sm text-surface-muted">
                                No models for this brand
                              </p>
                            ) : (
                              <ul className="grid gap-1 sm:grid-cols-2 lg:grid-cols-3">
                                {models.map((m) => (
                                  <li
                                    key={m.id}
                                    className="flex items-center justify-between gap-2 rounded-lg border border-surface-border/60 px-3 py-1.5 text-sm"
                                  >
                                    <span
                                      className={
                                        m.is_active
                                          ? ""
                                          : "text-surface-muted line-through"
                                      }
                                    >
                                      {m.name}
                                      {typeof m.trim_count === "number"
                                        ? ` · ${m.trim_count} trim(s)`
                                        : ""}
                                    </span>
                                    {canWrite ? (
                                      <button
                                        type="button"
                                        disabled={busy}
                                        onClick={() => void toggleModel(m)}
                                        className="text-xs text-surface-muted hover:text-white"
                                      >
                                        {m.is_active ? "Off" : "On"}
                                      </button>
                                    ) : null}
                                  </li>
                                ))}
                              </ul>
                            )}
                          </div>
                        </Td>
                      </tr>
                    ) : null}
                  </Fragment>
                ))}
              </tbody>
            </DataTable>
          )}
        </AsyncPageBody>
      ) : (
        <AsyncPageBody
          title="Body types"
          data={bodies.data}
          error={bodies.error}
          loading={bodies.loading}
          reload={bodies.reload}
          actions={
            canWrite ? (
              <div className="flex flex-wrap gap-2">
                <input
                  type="text"
                  value={newBody}
                  onChange={(e) => setNewBody(e.target.value)}
                  placeholder="New body type"
                  className={inputClass}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") void addBodyType();
                  }}
                />
                <button
                  type="button"
                  disabled={busy || !newBody.trim()}
                  onClick={() => void addBodyType()}
                  className="rounded-lg bg-brand-700 px-3 py-2 text-sm hover:bg-brand-600 disabled:opacity-50"
                >
                  Add
                </button>
              </div>
            ) : null
          }
        >
          {(result) => (
            <DataTable
              empty={!result.body_types.length}
              emptyTitle="No body types — seed or add one"
            >
              <thead>
                <tr>
                  <Th>Name</Th>
                  <Th>Status</Th>
                  <Th>Actions</Th>
                </tr>
              </thead>
              <tbody>
                {result.body_types.map((b) => (
                  <tr key={b.id} className="border-t border-surface-border">
                    <Td>{b.name}</Td>
                    <Td>{b.is_active ? "Active" : "Inactive"}</Td>
                    <Td>
                      {canWrite ? (
                        <button
                          type="button"
                          disabled={busy}
                          onClick={() => void toggleBody(b)}
                          className="text-xs text-surface-muted hover:text-white"
                        >
                          {b.is_active ? "Deactivate" : "Activate"}
                        </button>
                      ) : (
                        "—"
                      )}
                    </Td>
                  </tr>
                ))}
              </tbody>
            </DataTable>
          )}
        </AsyncPageBody>
      )}
    </div>
  );
}
