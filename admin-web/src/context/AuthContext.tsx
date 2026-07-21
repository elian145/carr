"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { usePathname, useRouter } from "next/navigation";
import { fetchMe } from "@/lib/api";
import {
  ApiRequestError,
  clearSession,
  establishSession,
} from "@/lib/auth";
import type { User } from "@/lib/types";

interface AuthContextValue {
  user: User | null;
  loading: boolean;
  login: (username: string, password: string) => Promise<void>;
  logout: () => void;
  refresh: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

const PUBLIC_PATHS = ["/login"];

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const router = useRouter();
  const pathname = usePathname();

  const refresh = useCallback(async () => {
    try {
      const me = await fetchMe();
      if (!me.is_admin) {
        await clearSession();
        setUser(null);
        throw new Error("Admin privileges required");
      }
      setUser(me);
    } catch {
      await clearSession();
      setUser(null);
    }
  }, []);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      await refresh();
      if (!cancelled) setLoading(false);
    })();
    return () => {
      cancelled = true;
    };
  }, [refresh]);

  useEffect(() => {
    if (loading) return;
    const isPublic = PUBLIC_PATHS.includes(pathname);
    if (!user && !isPublic) {
      router.replace("/login");
    } else if (user && pathname === "/login") {
      router.replace("/dashboard");
    }
  }, [loading, user, pathname, router]);

  const login = useCallback(
    async (username: string, password: string) => {
      const me = (await establishSession(username, password)) as User;
      if (!me?.is_admin) {
        await clearSession();
        setUser(null);
        throw new Error("This account does not have admin access");
      }
      setUser(me);
      router.replace("/dashboard");
    },
    [router],
  );

  const logout = useCallback(() => {
    void (async () => {
      await clearSession();
      setUser(null);
      router.replace("/login");
    })();
  }, [router]);

  const value = useMemo(
    () => ({ user, loading, login, logout, refresh }),
    [user, loading, login, logout, refresh],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
}

export function getApiErrorMessage(error: unknown): string {
  if (error instanceof ApiRequestError) return error.message;
  if (error instanceof Error) return error.message;
  return "Something went wrong";
}
