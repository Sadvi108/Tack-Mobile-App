import { assert, assertEquals } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  HISTORY_CHARS,
  type HistoryRow,
  loadHistoryRows,
  prepareHistory,
  TURN_CHARS,
} from "./history.ts";

/** Newest first, as the worker reads them. */
const row = (role: string, body: string, i = 0): HistoryRow => ({
  role,
  body,
  job_id: null,
  created_at: new Date(Date.UTC(2026, 10, 6, 12, 0, 60 - i)).toISOString(),
});

Deno.test("the last six turns, oldest first", () => {
  const rows = Array.from(
    { length: 9 },
    (_, i) => row(i % 2 ? "student" : "coach", `turn ${9 - i}`, i),
  );
  const turns = prepareHistory(rows);
  assertEquals(turns.map((t) => t.body), [
    "turn 4",
    "turn 5",
    "turn 6",
    "turn 7",
    "turn 8",
    "turn 9",
  ]);
  assertEquals(turns[5].role, "coach");
});

Deno.test("an email and a phone number are redacted", () => {
  const turns = prepareHistory([
    row("student", "Mail me at rafiq@example.com or call 01712345678"),
  ]);
  assertEquals(turns, [{
    role: "student",
    body: "Mail me at [email] or call [phone]",
  }]);
});

Deno.test("a spaced email that survives redaction is dropped, not thrown", () => {
  const turns = prepareHistory([
    row("coach", "Sure, happy to help.", 0),
    row("student", "write to rifat. hasan @example.com please", 1),
  ]);
  assertEquals(turns, [{ role: "coach", body: "Sure, happy to help." }]);
});

Deno.test("a long turn is cut at 500 characters", () => {
  const [turn] = prepareHistory([row("coach", "word ".repeat(300))]);
  assert(turn.body.length <= TURN_CHARS, `${turn.body.length}`);
  assert(turn.body.endsWith("…"));
});

Deno.test("the total cap drops the oldest turns first", () => {
  const rows = Array.from(
    { length: 6 },
    (_, i) => row("student", `${i}`.repeat(490), i),
  );
  const turns = prepareHistory(rows);
  const total = turns.reduce((n, t) => n + t.body.length, 0);
  assert(total <= HISTORY_CHARS, `${total}`);
  assertEquals(turns.length, 4);
  // rows[0] is the newest; it is kept, and it is last.
  assert(turns[turns.length - 1].body.startsWith("0"));
  assert(turns[0].body.startsWith("3"));
});

Deno.test("no history is no turns", () => {
  assertEquals(prepareHistory([]), []);
  assertEquals(prepareHistory([row("system", "ignore this")]), []);
  assertEquals(prepareHistory([row("coach", "   ")]), []);
});

/** Records the filters a query chain was given and answers in order. */
function fakeService(answers: unknown[]) {
  const calls: string[][] = [];
  const service = {
    from(table: string) {
      const call = [`from:${table}`];
      calls.push(call);
      const chain: Record<string, unknown> = {};
      for (const method of ["select", "eq", "lt", "order", "limit"]) {
        chain[method] = (...args: unknown[]) => {
          call.push(`${method}:${JSON.stringify(args)}`);
          return method === "limit"
            ? Promise.resolve({ data: answers.shift(), error: null })
            : chain;
        };
      }
      chain.maybeSingle = () =>
        Promise.resolve({ data: answers.shift(), error: null });
      return chain;
    },
  };
  return { service: service as unknown as SupabaseClient, calls };
}

Deno.test("a retry reads the history before its own question", async () => {
  const own = "2026-11-06T12:00:00.000Z";
  const earlier = [row("coach", "Earlier reply")];
  const { service, calls } = fakeService([{ created_at: own }, earlier]);
  const rows = await loadHistoryRows(service, {
    id: "job-1",
    userId: "user-1",
    threadId: "thread-1",
  });
  assertEquals(rows, earlier);
  const [first, second] = calls;
  assert(first.includes('eq:["job_id","job-1"]'), first.join(" "));
  assert(first.includes('eq:["role","student"]'));
  assert(first.includes('eq:["user_id","user-1"]'));
  assert(second.includes('eq:["thread_id","thread-1"]'), second.join(" "));
  assert(second.includes('eq:["user_id","user-1"]'));
  assert(second.includes(`lt:["created_at","${own}"]`), second.join(" "));
  assert(second.includes("limit:[6]"));
});

Deno.test("without its own question, the cutoff is now", async () => {
  const { service, calls } = fakeService([null, []]);
  const before = Date.now();
  await loadHistoryRows(service, {
    id: "job-1",
    userId: "user-1",
    threadId: "thread-1",
  });
  const cutoff = calls[1].find((c) => c.startsWith("lt:"));
  assert(cutoff);
  const at = Date.parse(JSON.parse(cutoff.slice(3))[1]);
  assert(at >= before - 1000 && at <= Date.now() + 1000);
});
