import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { apifyJobTasks, importBdjobs } from "./bdjobs_import.ts";

Deno.test("Apify task configuration is bounded, deduplicated and backward compatible", () => {
  assertEquals(apifyJobTasks("TaskA,TaskB TaskA", "TaskB"), ["TaskA", "TaskB"]);
  assertEquals(apifyJobTasks(undefined, "Legacy123"), ["Legacy123"]);
  assertEquals(apifyJobTasks(), []);
  assertThrows(() => apifyJobTasks("../evil"));
  assertThrows(() =>
    apifyJobTasks(Array.from({ length: 9 }, (_, n) => `Task${n}`).join(","))
  );
});

Deno.test("each configured Apify task is queued independently without starting paid runs", async () => {
  const originalFetch = globalThis.fetch;
  const keys = [
    "APIFY_API_TOKEN",
    "APIFY_BDJOBS_TASK_ID",
    "APIFY_JOB_TASK_IDS",
  ];
  const before = keys.map((key) => Deno.env.get(key));
  const queued: Record<string, unknown>[] = [];
  const service = {
    from: () => ({
      upsert: (row: Record<string, unknown>) => {
        queued.push(row);
        return Promise.resolve({ error: null });
      },
    }),
  } as unknown as SupabaseClient;
  try {
    Deno.env.set(keys[0], "fixture-only");
    Deno.env.delete(keys[1]);
    Deno.env.set(keys[2], "TaskA,TaskB");
    assertEquals(
      await importBdjobs(service, { id: "job", user_id: null, payload: {} }),
      { queuedTasks: 2 },
    );
    assertEquals(queued.map((row) => row.payload), [{ taskId: "TaskA" }, {
      taskId: "TaskB",
    }]);
    globalThis.fetch = (input, init) => {
      assertEquals(
        new URL(String(input)).pathname,
        "/v2/actor-tasks/TaskA/runs/last",
      );
      assertEquals(init?.method, undefined);
      return Promise.resolve(Response.json({
        data: {
          id: "VeroRun123",
          actId: "5rkl00rFGoyw7UclT",
          status: "SUCCEEDED",
          defaultDatasetId: "Dataset123",
          finishedAt: new Date().toISOString(),
        },
      }));
    };
    await importBdjobs(service, {
      id: "task",
      user_id: null,
      payload: { taskId: "TaskA" },
    });
    assertEquals(
      (queued[2].payload as Record<string, unknown>).actorId,
      "5rkl00rFGoyw7UclT",
    );
    assertEquals(
      (queued[2].payload as Record<string, unknown>).datasetId,
      "Dataset123",
    );
  } finally {
    globalThis.fetch = originalFetch;
    keys.forEach((key, index) =>
      before[index] == null
        ? Deno.env.delete(key)
        : Deno.env.set(key, before[index]!)
    );
  }
});

Deno.test("Bdjobs imports a page once, schedules continuation, and stops on cache failure", async () => {
  const originalFetch = globalThis.fetch;
  const oldToken = Deno.env.get("APIFY_API_TOKEN");
  const oldTask = Deno.env.get("APIFY_BDJOBS_TASK_ID");
  const oldTasks = Deno.env.get("APIFY_JOB_TASK_IDS");
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
    Deno.env.delete("APIFY_JOB_TASK_IDS");
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
        location: "Dhaka",
      }))));
    const result = await importBdjobs(service, job) as Record<string, unknown>;
    assertEquals(result.complete, false);
    assertEquals(result.imported, 100);
    assertEquals(calls[0].name, "cache_apify_job_page");
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
      ], ["APIFY_JOB_TASK_IDS", oldTasks]]
    ) {
      if (value == null) Deno.env.delete(key!);
      else Deno.env.set(key!, value);
    }
  }
});

// Re-reading a dataset is not seeing its jobs again. If an import stamped the
// time it ran, an hourly re-read of yesterday's collection would keep closed
// vacancies inside Radar's 48-hour window forever.
Deno.test("an import stamps the run's finish time, not the time it read the page", async () => {
  const originalFetch = globalThis.fetch;
  const oldToken = Deno.env.get("APIFY_API_TOKEN");
  const oldTask = Deno.env.get("APIFY_BDJOBS_TASK_ID");
  const stamped: unknown[] = [];
  const service = {
    from: () => ({ upsert: () => Promise.resolve({ error: null }) }),
    rpc: (_name: string, params: { p_rows: { last_seen_at: unknown }[] }) => {
      stamped.push(...params.p_rows.map((r) => r.last_seen_at));
      return Promise.resolve({ data: params.p_rows.length, error: null });
    },
  } as unknown as SupabaseClient;
  const finishedAt = new Date(Date.now() - 20 * 60 * 60 * 1000).toISOString();
  const page = { runId: "Run9", datasetId: "Data9", offset: 0, finishedAt };
  try {
    Deno.env.set("APIFY_API_TOKEN", "fixture-only");
    Deno.env.set("APIFY_BDJOBS_TASK_ID", "Task9");
    globalThis.fetch = () =>
      Promise.resolve(Response.json([{
        result_type: "bdjobs-job-search",
        status: "success",
        id: "1",
        url: "https://bdjobs.com/h/details/1",
        title: "Accountant",
        location: "Dhaka",
      }]));
    // The same page, read twice an hour apart, keeps the run's time both times.
    await importBdjobs(service, { id: "job", user_id: null, payload: page });
    await importBdjobs(service, { id: "job", user_id: null, payload: page });
    assertEquals(stamped.length, 2);
    for (const seen of stamped) {
      assertEquals(new Date(seen as string).toISOString(), finishedAt);
    }

    // A run older than the cache window is not read at all.
    const stale = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000).toISOString();
    assertEquals(
      await importBdjobs(service, {
        id: "job",
        user_id: null,
        payload: { ...page, finishedAt: stale },
      }),
      { skipped: "bdjobs run is stale" },
    );
    assertEquals(stamped.length, 2);
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
