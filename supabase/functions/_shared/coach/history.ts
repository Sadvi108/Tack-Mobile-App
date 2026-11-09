/**
 * The coach's memory: the last six turns of this conversation, redacted,
 * so "and what about the second one?" means something.
 *
 * Every turn goes through the same redaction as the question, and a turn
 * that still looks personal afterwards is dropped rather than sent. The
 * prompt marks these turns as context, never as instructions
 * (`coach_prompt.ts`).
 */
import type { SupabaseClient } from "@supabase/supabase-js";
import { assertClean, redact } from "../ai/redact.ts";

export interface Turn {
  role: "student" | "coach";
  body: string;
}

export interface HistoryRow {
  role: string;
  body: string;
  job_id: string | null;
  created_at: string;
}

export const HISTORY_TURNS = 6, TURN_CHARS = 500, HISTORY_CHARS = 2400;

const size = (turns: Turn[]) => turns.reduce((n, t) => n + t.body.length, 0);

/**
 * rows: the thread's messages strictly before this question, newest first.
 * Returns at most six turns, oldest first, each redacted and at most 500
 * characters, together at most 2400. Never throws on a bad turn: it drops it.
 */
export function prepareHistory(rows: HistoryRow[]): Turn[] {
  const turns: Turn[] = [];
  for (const row of rows.slice(0, HISTORY_TURNS)) {
    if (row.role !== "student" && row.role !== "coach") continue;
    let body = redact(row.body ?? "").text.trim();
    if (!body) continue;
    if (body.length > TURN_CHARS) {
      body = `${body.slice(0, TURN_CHARS - 1).trimEnd()}…`;
    }
    try {
      assertClean(body);
    } catch {
      continue;
    }
    turns.push({ role: row.role, body });
  }
  turns.reverse();
  while (turns.length > 0 && size(turns) > HISTORY_CHARS) turns.shift();
  return turns;
}

/**
 * The rows `prepareHistory` needs, read with the service client.
 *
 * The cutoff is this job's own student message, so a retry of the same job
 * sees the same history even after later messages arrive. Without that
 * message (an old payload), the cutoff is now.
 */
export async function loadHistoryRows(
  service: SupabaseClient,
  job: { id: string; userId: string; threadId: string },
): Promise<HistoryRow[]> {
  const { data: own } = await service.from("chat_messages")
    .select("created_at")
    .eq("job_id", job.id).eq("role", "student").eq("user_id", job.userId)
    .maybeSingle();
  const cutoff = (own?.created_at as string | undefined) ??
    new Date().toISOString();
  const { data, error } = await service.from("chat_messages")
    .select("role, body, job_id, created_at")
    .eq("thread_id", job.threadId).eq("user_id", job.userId)
    .lt("created_at", cutoff)
    .order("created_at", { ascending: false })
    .limit(HISTORY_TURNS);
  if (error) throw error;
  return (data ?? []) as HistoryRow[];
}
