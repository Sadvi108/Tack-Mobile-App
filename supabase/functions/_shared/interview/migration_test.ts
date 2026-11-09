import { assert, assertEquals } from "@std/assert";

// 0096 cannot be run from here, so its promises are read off the text. Each
// test is one thing tool/verify_rpc_surface.js would otherwise find only
// after the migration was applied.
const sql = await Deno.readTextFile(
  new URL("../../../migrations/0096_question_pool_schema.sql", import.meta.url),
);

/** Every function the file defines, with the header that sets its options. */
function functions(): { name: string; header: string }[] {
  const out: { name: string; header: string }[] = [];
  const re = /create or replace function public\.(\w+)\(/g;
  for (const m of sql.matchAll(re)) {
    const start = m.index!;
    const body = sql.indexOf("as $$", start);
    out.push({ name: m[1], header: sql.slice(start, body) });
  }
  return out;
}

const grantLines = sql.split("\n").filter((l) =>
  /^\s*grant /.test(l) || /^\s*to /.test(l)
);

/** The full grant statement for a function, joined across its lines. */
function grantsOf(name: string): string[] {
  const statements = sql.replace(/--[^\n]*/g, "").split(";")
    .map((s) => s.replace(/\s+/g, " ").trim());
  return statements.filter((s) =>
    s.startsWith(`grant execute on function public.${name}(`)
  );
}

Deno.test("0096 defines the functions of contract C3.3", () => {
  const names = functions().map((f) => f.name).sort();
  assertEquals(names, [
    "interview_bank_keep_seed",
    "interview_catalog",
    "interview_draw",
    "interview_due",
    "interview_resolve_role_for",
    "interview_role_for_path",
    "interview_role_from_text",
    "interview_slots",
    "interview_slug",
    "start_practice_session",
  ]);
});

Deno.test("every function 0096 defines has its own revoke all", () => {
  for (const { name } of functions()) {
    assert(
      sql.includes(`revoke all on function public.${name}(`),
      `${name} has no revoke all line`,
    );
  }
});

Deno.test("every function 0096 defines pins its search path", () => {
  for (const { name, header } of functions()) {
    assert(
      header.includes("set search_path = public"),
      `${name} does not set search_path`,
    );
  }
});

Deno.test("only the catalog, the start and the due list reach a student", () => {
  const toAuthenticated = functions()
    .map((f) => f.name)
    .filter((name) =>
      grantsOf(name).some((g) => g.endsWith("to authenticated"))
    )
    .sort();
  assertEquals(toAuthenticated, [
    "interview_catalog",
    "interview_due",
    "start_practice_session",
  ]);
  assert(
    !/to anon/.test(grantLines.join("\n")),
    "something is granted to anon",
  );
});

Deno.test("role resolution is the service role's alone", () => {
  const grants = grantsOf("interview_resolve_role_for");
  assertEquals(grants.length, 1);
  assert(grants[0].endsWith("to service_role"), grants[0]);
});

Deno.test("each pool table forces row level security and is read-only", () => {
  for (
    const table of [
      "interview_roles",
      "interview_role_aliases",
      "interview_role_paths",
      "interview_pool_questions",
    ]
  ) {
    assert(
      sql.includes(`alter table public.${table} force row level security;`),
      `${table} does not force RLS`,
    );
    assert(
      sql.includes(
        `revoke insert, update, delete, truncate on public.${table} from anon, authenticated;`,
      ),
      `${table} is writable by a client`,
    );
    const policies = [...sql.matchAll(
      new RegExp(`create policy \\w+ on public\\.${table}\\s+for (\\w+)`, "g"),
    )].map((m) => m[1]);
    assertEquals(policies, ["select"], `${table} policies`);
  }
});

Deno.test("only a seed migration turns the seed guard off", () => {
  assert(!sql.includes("set local tack.seeding"));
  assert(sql.includes("current_setting('tack.seeding', true)"));
  assert(
    sql.includes(
      "create trigger interview_bank_keep_seed before update on public.interview_question_bank",
    ),
  );
});

Deno.test("the start is free: it never touches the quota or the job queue", () => {
  const start = sql.indexOf(
    "create or replace function public.start_practice_session(",
  );
  const end = sql.indexOf("end $$;", start);
  const body = sql.slice(start, end);
  for (const word of ["consume_quota", "ai_usage", "jobs_queue", "enqueue"]) {
    assert(!body.includes(word), `start_practice_session mentions ${word}`);
  }
});

Deno.test("the daily cap counts every session started, deleted or not", () => {
  const start = sql.indexOf(
    "create or replace function public.start_practice_session(",
  );
  const body = sql.slice(start, sql.indexOf("end $$;", start));
  const cap = body.slice(
    body.indexOf("if (select count(*)"),
    body.indexOf("too_many_sessions"),
  );
  assert(cap.includes("interval '1 day'"), "the cap query was not found");
  assert(!cap.includes("deleted_at"), "the cap skips deleted sessions");
});

Deno.test("0096 ends by checking itself", () => {
  const last = sql.lastIndexOf("\ndo $$");
  assert(last > sql.lastIndexOf("create or replace function"));
  const tail = sql.slice(last);
  assert(/end \$\$;\s*$/.test(tail), "the file does not end with a do block");
  assert(!/\n(create|grant|revoke|alter|insert|update|delete) /.test(tail));
});
