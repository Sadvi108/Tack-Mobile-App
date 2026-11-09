import { assert, assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { InvalidModelReply, runCompletion } from "./gateway.ts";
import {
  type CompletionRequest,
  type CompletionResult,
  type LLMProvider,
  MockProvider,
} from "./provider.ts";
import { coachReplySchema, coachReplyShape } from "./schemas.ts";
import {
  FALLBACK_LEAD,
  jobContext,
  replyToCoach,
} from "../jobs/conversation_handlers.ts";
import { routesForMode } from "../coach/actions.ts";

/** Replies in order, and remembers what it was asked. */
class Scripted implements LLMProvider {
  readonly name = "scripted";
  requests: CompletionRequest[] = [];
  constructor(private replies: unknown[]) {}
  complete(request: CompletionRequest): Promise<CompletionResult> {
    this.requests.push(request);
    return Promise.resolve({
      data: this.replies.shift(),
      provider: this.name,
      model: "scripted-1",
      promptTokens: 1,
      completionTokens: 1,
    });
  }
}

type Fn = (...args: unknown[]) => unknown;

/**
 * Just enough of the service client for the gateway and the coach handler:
 * chat_messages reads answer from `reads` in order, history rows come from
 * `rows`, and every write is recorded.
 */
function fakeService(
  { reads = [], rows = [] }: { reads?: unknown[]; rows?: unknown[] } = {},
) {
  const usage: Record<string, unknown>[] = [];
  const saved: Record<string, unknown>[] = [];
  const service = {
    rpc: () => Promise.resolve({ data: 7, error: null }),
    from(table: string) {
      const chain: Record<string, Fn> = {};
      for (const method of ["select", "eq", "lt", "order"]) {
        chain[method] = () => chain;
      }
      chain.limit = () => Promise.resolve({ data: rows, error: null });
      chain.maybeSingle = () =>
        Promise.resolve({ data: reads.shift() ?? null, error: null });
      chain.insert = (row) => {
        if (table === "ai_usage") usage.push(row as Record<string, unknown>);
        return Promise.resolve({ error: null });
      };
      chain.upsert = (row) => {
        saved.push(row as Record<string, unknown>);
        return Promise.resolve({ error: null });
      };
      return chain;
    },
  };
  return { service: service as unknown as SupabaseClient, usage, saved };
}

const request = (user = "FACTS: {}\n\nLATEST QUESTION:\nWhat now?") => ({
  feature: "coach_chat",
  system: "system",
  user,
  schema: coachReplySchema(["roadmap", "score"]),
});

const good = {
  body: "Open your roadmap this week.",
  actions: [{ route: "roadmap" }],
};

// ----------------------------------------------------------- the check hook

Deno.test("a check's problems get the one corrective retry", async () => {
  const { service, usage } = fakeService();
  const provider = new Scripted([{ ...good, body: "Bad one." }, good]);
  let calls = 0;
  const outcome = await runCompletion(
    service,
    "user-1",
    request(),
    coachReplyShape,
    ["body", "actions"],
    {
      consumeQuota: false,
      provider,
      check: () => calls++ === 0 ? ["body_unknown_number"] : [],
    },
  );
  assertEquals(outcome.data, good);
  assertEquals(provider.requests.length, 2);
  assert(
    provider.requests[1].user.includes(
      "Your previous reply was rejected: body_unknown_number",
    ),
    provider.requests[1].user,
  );
  assertEquals(usage[0].succeeded, true);
  assertEquals(usage[0].error_code, null);
});

Deno.test("failing twice throws InvalidModelReply, recorded as before", async () => {
  const { service, usage } = fakeService();
  const provider = new Scripted([good, good]);
  const error = await assertRejects(
    () =>
      runCompletion(service, "user-1", request(), coachReplyShape, [
        "body",
        "actions",
      ], {
        consumeQuota: false,
        provider,
        check: () => ["body_mode_word"],
      }),
    InvalidModelReply,
  );
  assertEquals(error.problems, ["body_mode_word"]);
  assertEquals(error.name, "InvalidModelReply");
  assertEquals(usage[0].succeeded, false);
  assertEquals(usage[0].error_code, "invalid_model_reply");
});

Deno.test("a wrong shape still fails as InvalidModelReply", async () => {
  const { service } = fakeService();
  const provider = new Scripted([{ reply: "old" }, { reply: "old" }]);
  await assertRejects(
    () =>
      runCompletion(service, "user-1", request(), coachReplyShape, [
        "body",
        "actions",
      ], { consumeQuota: false, provider }),
    InvalidModelReply,
  );
});

Deno.test("with no check and a good reply, nothing is asked twice", async () => {
  const { service } = fakeService();
  const provider = new Scripted([good]);
  const outcome = await runCompletion(
    service,
    "user-1",
    request(),
    coachReplyShape,
    ["body", "actions"],
    { consumeQuota: false, provider },
  );
  assertEquals(outcome.data, good);
  assertEquals(provider.requests.length, 1);
});

// ------------------------------------------- the coach reply, end to end

const job = (payload: Record<string, unknown>) => ({
  id: "job-1",
  user_id: "user-1",
  payload: { thread_id: "thread-1", question: "How do I network?", ...payload },
});

const context = {
  today: "2026-11-06",
  mode: "explore",
  score: {
    total: 41,
    components: { projects: { earned: 2, max: 10, available: 8 } },
  },
  roadmap: { done: 4, total: 12, next: "Learn SQL joins" },
};

Deno.test("the mock drives a full model reply with chips", async () => {
  const { service, saved } = fakeService();
  const result = await replyToCoach(
    service,
    job({ mode: "explore", context }),
    new MockProvider(),
  );
  assertEquals(result.answeredBy, "model");
  assertEquals(result.intent, "model");
  assertEquals(result.spent, true);
  assertEquals(result.actions, [{
    route: "roadmap",
    label: "Open your roadmap",
  }]);
  assert(String(result.reply).startsWith("This is a mock reply."));
  assertEquals(saved.length, 1);
  assertEquals(saved[0].role, "coach");
  assertEquals(saved[0].answered_by, "model");
  assertEquals(saved[0].intent, "model");
  assertEquals(saved[0].actions, result.actions);
  assertEquals(saved[0].user_id, "user-1");
  assertEquals(saved[0].thread_id, "thread-1");
});

Deno.test("a reply that fails twice becomes a free fallback", async () => {
  const { service, saved, usage } = fakeService();
  const bad = {
    body: "Most students reach 65 by June. Explore one path.",
    actions: [{ route: "paths" }],
  };
  const result = await replyToCoach(
    service,
    job({ mode: "explore", context }),
    new Scripted([bad, bad]),
  );
  assertEquals(result.answeredBy, "data");
  assertEquals(result.intent, "fallback");
  assertEquals(result.spent, false);
  assertEquals(result.skipped, "invalid_reply");
  assert(String(result.reply).startsWith(FALLBACK_LEAD));
  assert(String(result.reply).includes("projects"), String(result.reply));
  const actions = result.actions as { route: string }[];
  assert(actions.length >= 1);
  for (const a of actions) {
    assert(routesForMode("explore").includes(a.route as never), a.route);
  }
  assertEquals(saved[0].answered_by, "data");
  assertEquals(saved[0].intent, "fallback");
  assertEquals(usage[0].error_code, "invalid_model_reply");
});

Deno.test("a mode word in explore is caught and asked again", async () => {
  const { service } = fakeService();
  const provider = new Scripted([
    {
      body: "Apply to an internship this week.",
      actions: [{ route: "roadmap" }],
    },
    good,
  ]);
  const result = await replyToCoach(
    service,
    job({ mode: "explore", context }),
    provider,
  );
  assertEquals(result.intent, "model");
  assert(provider.requests[1].user.includes("body_mode_word"));
  // The model never sees path, nor anything an explore student cannot open.
  const schema = provider.requests[0].schema as {
    properties: {
      actions: { items: { properties: { route: { enum: string[] } } } };
    };
  };
  assertEquals(
    schema.properties.actions.items.properties.route.enum,
    ["analyser", "roadmap", "score", "paths", "profile"],
  );
});

Deno.test("an old payload with a string context still works", async () => {
  const { service } = fakeService();
  const provider = new Scripted([good]);
  const result = await replyToCoach(
    service,
    job({ context: JSON.stringify({ ...context, mode: "launch" }) }),
    provider,
  );
  assertEquals(result.intent, "model");
  // No mode in the payload: the context's is used.
  assert(provider.requests[0].system.includes("final-year"));
});

Deno.test("the last turns reach the prompt, redacted, before the question", async () => {
  const rows = [
    {
      role: "coach",
      body: "Write to rafiq@example.com about it.",
      job_id: null,
      created_at: "2026-11-06T11:59:00Z",
    },
    {
      role: "student",
      body: "Who should I ask about internships?",
      job_id: null,
      created_at: "2026-11-06T11:58:00Z",
    },
  ];
  const { service } = fakeService({
    reads: [null, { created_at: "2026-11-06T12:00:00Z" }],
    rows,
  });
  const provider = new Scripted([good]);
  await replyToCoach(service, job({ mode: "prove", context }), provider);
  const user = provider.requests[0].user;
  assert(user.includes("EARLIER IN THIS CONVERSATION"), user);
  assert(
    user.includes(
      "Student: Who should I ask about internships?\nCoach: Write to [email] about it.",
    ),
    user,
  );
  assert(!user.includes("rafiq@"), user);
  assert(user.trimEnd().endsWith("LATEST QUESTION:\nHow do I network?"), user);
});

Deno.test("a retry after the reply was saved returns it as it was", async () => {
  const saved = {
    body: "Saved reply.",
    actions: [{ route: "roadmap", label: "Open your roadmap" }],
    answered_by: "model",
    intent: "model",
  };
  const { service } = fakeService({ reads: [saved] });
  const provider = new Scripted([]);
  const result = await replyToCoach(
    service,
    job({ mode: "explore", context }),
    provider,
  );
  assertEquals(provider.requests.length, 0);
  assertEquals(result.reply, "Saved reply.");
  assertEquals(result.actions, saved.actions);
  assertEquals(result.spent, true);

  const { service: again } = fakeService({
    reads: [{ ...saved, answered_by: "data", intent: "fallback" }],
  });
  const fallback = await replyToCoach(again, job({ context }), provider);
  assertEquals(fallback.spent, false);
  assertEquals(fallback.skipped, "invalid_reply");
});

Deno.test("a job's context is read whatever shape it came in", () => {
  assertEquals(jobContext({ mode: "build" }), { mode: "build" });
  assertEquals(jobContext('{"mode":"launch"}'), { mode: "launch" });
  assertEquals(jobContext('{"mode": "lau [link]'), {});
  assertEquals(jobContext(null), {});
  assertEquals(jobContext([1, 2]), {});
});
