/**
 * Per-isolate memo for Cron-owned KV JSON snapshots (road events). Requests
 * in the same isolate within the TTL reuse the parsed snapshot instead of one
 * billable KV read plus a full JSON parse each; writes made by this isolate
 * update the memo immediately. Other isolates see a new snapshot within the
 * TTL, which is well inside the 10-minute refresh cadence. After the TTL a
 * re-read with the same checkedAt keeps the existing parsed object.
 */
const MEMO_MS = 60_000;
const memo = new WeakMap<object, Map<string, { at: number; value: unknown }>>();

export async function readMemoizedJson<T extends { checkedAt?: string | null }>(
  kv: KVNamespace, key: string, ttlMs = MEMO_MS,
): Promise<T | null> {
  const cached = memo.get(kv)?.get(key);
  if (cached && Date.now() - cached.at < ttlMs) return cached.value as T | null;
  const value = await kv.get<T>(key, 'json');
  const previous = cached?.value as T | null | undefined;
  const same = previous && value && previous.checkedAt && previous.checkedAt === value.checkedAt;
  rememberJson(kv, key, same ? previous : value);
  return same ? previous : value;
}

export function rememberJson(kv: KVNamespace, key: string, value: unknown) {
  let entries = memo.get(kv);
  if (!entries) { entries = new Map(); memo.set(kv, entries); }
  entries.set(key, { at: Date.now(), value });
}
