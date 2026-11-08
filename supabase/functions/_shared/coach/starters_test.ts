import { assert, assertEquals } from "@std/assert";
import { answerFromData, type Context } from "./router.ts";
import { MODES } from "./actions.ts";

/** The app's starters, read from the Dart file the screen uses. */
async function starters(): Promise<Record<string, string[]>> {
  const dart = await Deno.readTextFile(
    new URL(
      "../../../../app/lib/features/coach/application/coach_starters.dart",
      import.meta.url,
    ),
  );
  const out: Record<string, string[]> = {};
  const arm =
    /((?:YearMode\.\w+\s*\|\|\s*)*YearMode\.\w+)\s*=>\s*const\s*\[([^\]]*)\]/g;
  for (const m of dart.matchAll(arm)) {
    const questions = [...m[2].matchAll(/'([^'\n]+)'/g)].map((q) => q[1]);
    for (const mode of m[1].matchAll(/YearMode\.(\w+)/g)) {
      out[mode[1]] = questions;
    }
  }
  return out;
}

const rich = (mode: string): Context => ({
  version: 2,
  today: "2026-11-06",
  mode,
  target_path: { title: "Data analyst", slug: "data-analyst" },
  score: {
    total: 41,
    components: {
      cv_quality: { earned: 6, max: 13, available: 7 },
      projects: { earned: 2, max: 10, available: 8 },
      skills: { earned: 9, max: 12, available: 3 },
    },
  },
  cohort: { average: 38, size: 12 },
  skill_gap: ["Python", "Tableau"],
  roadmap: { done: 4, total: 12, overdue: 1, next: "Learn SQL joins" },
  applications: { saved: 2, applied: 1 },
  cv: {
    has_cv: true,
    last_check: {
      on: "2026-11-04",
      problems: 1,
      suggestions: 3,
      top: [{ kind: "contact", severity: "problem", title: "No contact" }],
    },
  },
  interview: {
    sessions: 3,
    last: { on: "2026-11-04", role: "Data analyst", score: 5.7 },
    by_category: [{ category: "SQL", average: 4.5, answers: 2 }],
    due_reviews: 2,
  },
  upcoming: [{ kind: "task", title: "Learn SQL joins", on: "2026-11-08" }],
});

Deno.test("the app's starters were all read", async () => {
  const byMode = await starters();
  assertEquals(Object.keys(byMode).sort(), [...MODES].sort());
  for (const mode of MODES) assertEquals(byMode[mode].length, 4, mode);
});

Deno.test("every starter is answered for free, with nothing known", async () => {
  // A starter that went to the model would spend an AI action on the one
  // question the screen promised was free.
  for (const [mode, questions] of Object.entries(await starters())) {
    for (const q of questions) {
      const a = answerFromData(q, { mode });
      assert(a, `${mode}: "${q}" needs the model with an empty context`);
      assert(a.actions.length >= 1, `${mode}: "${q}" has no chip`);
    }
  }
});

Deno.test("every starter is answered for free, with everything known", async () => {
  for (const [mode, questions] of Object.entries(await starters())) {
    for (const q of questions) {
      const a = answerFromData(q, rich(mode));
      assert(a, `${mode}: "${q}" needs the model with a full context`);
    }
  }
});
