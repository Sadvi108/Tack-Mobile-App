import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { importBdjobs } from "./bdjobs_import.ts";

Deno.test("Bdjobs imports a page once, schedules continuation, and stops on cache failure", async () => {
  const originalFetch = globalThis.fetch;
  const oldToken = Deno.env.get("APIFY_API_TOKEN");
  const oldTask = Deno.env.get("APIFY_BDJOBS_TASK_ID");
  const queued: Record<string, unknown>[] = [];
  const calls: { name: string; params: Record<string, unknown> }[] = [];
  let failCache = false;
  const service = {
    from: (table: string) => ({
      upsert: (
        body: Record<string, unknown>,
        options: Record<string, unknown>,
      ) => {
        assertEquals(table, "jobs_queue");
        assertEquals(options, {
          onConflict: "idempotency_key",
          ignoreDuplicates: true,
        });
        queued.push(body);
        return Promise.resolve({ error: null });
      },
    }),
    rpc: (name: string, params: Record<string, unknown>) => {
      calls.push({ name, params });
      return Promise.resolve({
        data: 100,
        error: failCache ? { message: "failure" } : null,
      });
    },
  } as unknown as SupabaseClient;
  const page = {
    runId: "Run123",
    datasetId: "Dataset123",
    offset: 0,
    finishedAt: new Date().toISOString(),
  };
  const job = { id: "job", user_id: null, payload: page };
  try {
    Deno.env.delete("APIFY_API_TOKEN");
    assertEquals(await importBdjobs(service, job), {
      skipped: "bdjobs not configured",
    });
    Deno.env.set("APIFY_API_TOKEN", "fixture-only");
    Deno.env.set("APIFY_BDJOBS_TASK_ID", "Task123");
    globalThis.fetch = () =>
      Promise.resolve(Response.json(Array.from({ length: 100 }, (_, i) => ({
        result_type: "bdjobs-job-search",
        status: "success",
        id: String(i + 1),
        url: `https://bdjobs.com/h/details/${i + 1}`,
        title: `Accountant ${i}`,
      }))));
    const result = await importBdjobs(service, job) as Record<string, unknown>;
    assertEquals(result.complete, false);
    assertEquals(result.imported, 100);
    assertEquals(calls[0].name, "cache_bdjobs_page");
    assertEquals(queued[0].idempotency_key, "bdjobs:Run123:100");
    assertEquals((queued[0].payload as typeof page).offset, 100);
    failCache = true;
    await assertRejects(
      () => importBdjobs(service, job),
      Error,
      "bdjobs_cache_failed",
    );
    assertEquals(queued.length, 1); // Never skip a failed page.
    failCache = false;
    globalThis.fetch = () => Promise.resolve(Response.json([]));
    const last = await importBdjobs(service, {
      ...job,
      payload: { ...page, offset: 100 },
    }) as Record<string, unknown>;
    assertEquals(last.complete, true);
    assertEquals(queued.length, 1);
  } finally {
    globalThis.fetch = originalFetch;
    for (
      const [key, value] of [["APIFY_API_TOKEN", oldToken], [
        "APIFY_BDJOBS_TASK_ID",
        oldTask,
      ]]
    ) {
      if (value == null) Deno.env.delete(key!);
      else Deno.env.set(key!, value);
    }
  }
});
