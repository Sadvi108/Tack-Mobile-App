import { assert, assertEquals } from "@std/assert";
import { compactContext } from "./context.ts";
import type { Context } from "./router.ts";

const ctx: Context = {
  version: 2,
  today: "2026-11-06",
  mode: "explore",
  score: {
    total: 41.26,
    components: {
      projects: { earned: 2, max: 10, available: 8 },
      application_activity: { earned: 0, max: 0, available: 0 },
    },
  },
  cohort: { average: 38.449, size: 12 },
  skills_held: Array.from({ length: 45 }, (_, i) => `Skill ${i}`),
  skill_gap: Array.from({ length: 14 }, (_, i) => `Gap ${i}`),
  applications: { saved: 2 },
  upcoming: [
    { kind: "task", title: "Learn SQL joins", on: "2026-11-08" },
    { kind: "follow_up", title: "Junior analyst · A bank", on: "2026-11-08" },
    { kind: "closing", title: "Junior analyst · A bank", on: "2026-11-12" },
  ],
  interview: {
    by_category: [{ category: "SQL", average: 4.567, answers: 2 }],
  },
};

Deno.test("an early year's facts carry no job hunt", () => {
  const out = compactContext(ctx, "explore");
  assertEquals("applications" in out, false);
  assertEquals(out.upcoming, [
    { kind: "task", title: "Learn SQL joins", on: "2026-11-08" },
  ]);
});

Deno.test("a later year keeps applications and every date", () => {
  const out = compactContext({ ...ctx, mode: "launch" }, "launch");
  assertEquals(out.applications, { saved: 2 });
  assertEquals((out.upcoming as unknown[]).length, 3);
});

Deno.test("version and zero-weight parts are dropped, lists are capped", () => {
  const out = compactContext(ctx, "launch");
  assertEquals("version" in out, false);
  const score = out.score as { components: Record<string, unknown> };
  assertEquals(Object.keys(score.components), ["projects"]);
  assertEquals((out.skills_held as string[]).length, 30);
  assertEquals((out.skill_gap as string[]).length, 10);
  assertEquals((out.skills_held as string[])[0], "Skill 0");
});

Deno.test("numbers keep one decimal place", () => {
  const out = compactContext(ctx, "launch");
  assertEquals((out.score as { total: number }).total, 41.3);
  assertEquals((out.cohort as { average: number }).average, 38.4);
  const interview = out.interview as {
    by_category: { average: number; answers: number }[];
  };
  assertEquals(interview.by_category[0].average, 4.6);
  assertEquals(interview.by_category[0].answers, 2);
});

Deno.test("the input is not changed, and an empty context stays empty", () => {
  compactContext(ctx, "explore");
  assertEquals(ctx.version, 2);
  assertEquals(ctx.skills_held?.length, 45);
  assert(ctx.applications);
  assertEquals(compactContext({}, "explore"), {});
});
