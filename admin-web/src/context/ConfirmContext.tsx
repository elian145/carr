"use client";

import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";

type ConfirmTone = "brand" | "danger" | "warning";

type ConfirmOptions = {
  title: string;
  description?: string;
  confirmLabel?: string;
  cancelLabel?: string;
  tone?: ConfirmTone;
};

type PromptOptions = ConfirmOptions & {
  placeholder?: string;
  inputLabel?: string;
  defaultValue?: string;
};

type ConfirmApi = {
  confirm: (options: ConfirmOptions) => Promise<boolean>;
  prompt: (options: PromptOptions) => Promise<string | null>;
};

type DialogState =
  | (ConfirmOptions & {
      mode: "confirm";
      resolve: (value: boolean) => void;
    })
  | (PromptOptions & {
      mode: "prompt";
      resolve: (value: string | null) => void;
    })
  | null;

const ConfirmContext = createContext<ConfirmApi | null>(null);

const TONE_BTN: Record<ConfirmTone, string> = {
  brand: "bg-brand-700 hover:bg-brand-600",
  danger: "bg-red-800 hover:bg-red-700",
  warning: "bg-amber-700 hover:bg-amber-600",
};

export function ConfirmProvider({ children }: { children: ReactNode }) {
  const [dialog, setDialog] = useState<DialogState>(null);
  const [inputValue, setInputValue] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);

  const confirm = useCallback((options: ConfirmOptions) => {
    return new Promise<boolean>((resolve) => {
      setDialog({ ...options, mode: "confirm", resolve });
    });
  }, []);

  const prompt = useCallback((options: PromptOptions) => {
    return new Promise<string | null>((resolve) => {
      setInputValue(options.defaultValue ?? "");
      setDialog({ ...options, mode: "prompt", resolve });
      requestAnimationFrame(() => inputRef.current?.focus());
    });
  }, []);

  const api = useMemo(() => ({ confirm, prompt }), [confirm, prompt]);

  function closeConfirm(result: boolean) {
    if (dialog?.mode === "confirm") dialog.resolve(result);
    setDialog(null);
  }

  function closePrompt(result: string | null) {
    if (dialog?.mode === "prompt") dialog.resolve(result);
    setDialog(null);
    setInputValue("");
  }

  return (
    <ConfirmContext.Provider value={api}>
      {children}
      {dialog ? (
        <div
          className="fixed inset-0 z-[90] flex items-center justify-center bg-black/60 p-4"
          role="presentation"
          onClick={() =>
            dialog.mode === "confirm" ? closeConfirm(false) : closePrompt(null)
          }
        >
          <div
            role="dialog"
            aria-modal="true"
            aria-labelledby="confirm-dialog-title"
            className="w-full max-w-md rounded-xl border border-surface-border bg-surface-card p-5 shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 id="confirm-dialog-title" className="text-lg font-semibold">
              {dialog.title}
            </h2>
            {dialog.description ? (
              <p className="mt-2 text-sm text-surface-muted">{dialog.description}</p>
            ) : null}

            {dialog.mode === "prompt" ? (
              <label className="mt-4 flex flex-col gap-1 text-xs text-surface-muted">
                <span>{dialog.inputLabel || "Details"}</span>
                <input
                  ref={inputRef}
                  type="text"
                  value={inputValue}
                  onChange={(e) => setInputValue(e.target.value)}
                  placeholder={dialog.placeholder}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") closePrompt(inputValue);
                    if (e.key === "Escape") closePrompt(null);
                  }}
                  className="rounded-lg border border-surface-border bg-black/30 px-3 py-2 text-sm text-white"
                />
              </label>
            ) : null}

            <div className="mt-5 flex justify-end gap-2">
              <button
                type="button"
                onClick={() =>
                  dialog.mode === "confirm"
                    ? closeConfirm(false)
                    : closePrompt(null)
                }
                className="rounded-lg border border-surface-border px-4 py-2 text-sm text-surface-muted hover:bg-white/5 hover:text-white"
              >
                {dialog.cancelLabel || "Cancel"}
              </button>
              <button
                type="button"
                onClick={() =>
                  dialog.mode === "confirm"
                    ? closeConfirm(true)
                    : closePrompt(inputValue)
                }
                className={`rounded-lg px-4 py-2 text-sm text-white ${TONE_BTN[dialog.tone || "brand"]}`}
              >
                {dialog.confirmLabel ||
                  (dialog.mode === "confirm" ? "Confirm" : "Submit")}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </ConfirmContext.Provider>
  );
}

export function useConfirm(): ConfirmApi {
  const ctx = useContext(ConfirmContext);
  if (!ctx) throw new Error("useConfirm must be used within ConfirmProvider");
  return ctx;
}
