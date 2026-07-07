"use client";

import { FormEvent, useState } from "react";
import { getApiErrorMessage, useAuth } from "@/context/AuthContext";
import { getApiBase } from "@/lib/auth";

export default function LoginPage() {
  const { login, loading: authLoading } = useAuth();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      await login(username.trim(), password);
    } catch (err) {
      setError(getApiErrorMessage(err));
    } finally {
      setSubmitting(false);
    }
  }

  if (authLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <p className="text-surface-muted">Loading…</p>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-surface via-black to-brand-950/30 p-4">
      <div className="w-full max-w-md rounded-2xl border border-surface-border bg-surface-card p-8 shadow-2xl">
        <div className="mb-8 text-center">
          <p className="text-2xl font-bold text-brand-400">CARZO</p>
          <h1 className="mt-2 text-xl font-semibold">Admin sign in</h1>
          <p className="mt-2 text-sm text-surface-muted">
            Use an account with admin privileges on the server.
          </p>
        </div>

        <form onSubmit={onSubmit} className="space-y-4">
          <label className="block">
            <span className="mb-1.5 block text-sm text-surface-muted">
              Email, phone, or username
            </span>
            <input
              type="text"
              autoComplete="username"
              required
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              className="w-full rounded-lg border border-surface-border bg-black/30 px-3 py-2.5 text-white placeholder:text-surface-muted/60 focus:border-brand-500"
              placeholder="admin@example.com"
            />
          </label>

          <label className="block">
            <span className="mb-1.5 block text-sm text-surface-muted">Password</span>
            <input
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full rounded-lg border border-surface-border bg-black/30 px-3 py-2.5 text-white placeholder:text-surface-muted/60 focus:border-brand-500"
            />
          </label>

          {error ? (
            <p className="rounded-lg border border-red-900/50 bg-red-950/40 px-3 py-2 text-sm text-red-300">
              {error}
            </p>
          ) : null}

          <button
            type="submit"
            disabled={submitting}
            className="w-full rounded-lg bg-brand-600 px-4 py-2.5 font-medium text-white hover:bg-brand-500 disabled:opacity-60"
          >
            {submitting ? "Signing in…" : "Sign in"}
          </button>
        </form>

        <p className="mt-6 text-center text-xs text-surface-muted">
          API: {getApiBase()}
        </p>
      </div>
    </div>
  );
}
