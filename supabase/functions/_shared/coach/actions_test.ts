import { assert, assertEquals } from "@std/assert";
import {
  COACH_ROUTES,
  type CoachRoute,
  componentRoute,
  defaultAction,
  EARLY_MODES,
  finaliseActions,
  labelFor,
  MODE_WORDS,
  MODEL_ROUTES,
  MODES,
  normaliseMode,
  routesForMode,
} from "./actions.ts";
import type { Context } from "./router.ts";

const ctx: Context = {
  score: {
    total: 30,
    components: {
      cv_quality: { earned: 0, max: 13, available: 13 },
      projects: { earned: 2, max: 10, available: 8 },
      application_activity: { earned: 0, max: 0, available: 0 },
    },
  },
};

Deno.test("finaliseActions keeps the allowed, drops the rest, caps at two", () => {
  const out = finaliseActions(
    [
      { route: "nowhere" },
      { route: "applications" }, // not for a second-year
      { route: "roadmap" },
      { route: "roadmap" },
      { route: "score" },
      { route: "profile" },
    ],
    "build",
    ctx,
  );
  assertEquals(out, [
    { route: "roadmap", label: "Open your roadmap" },
    { route: "score", label: "See your score" },
  ]);
});

Deno.test("labels are Tack's, whatever the proposal said", () => {
  const out = finaliseActions(
    [{ route: "radar", label: "Apply now!!" }],
    "build",
    ctx,
  );
  assertEquals(out, [{ route: "radar", label: "See internships" }]);
});

Deno.test("with nothing usable, the default is added", () => {
  for (const raw of [[], null, "roadmap", [{ route: 7 }, "x", null]]) {
    const out = finaliseActions(raw, "launch", ctx);
    // cv_quality has the most left, so its route leads.
    assertEquals(out, [{ route: "cv_check", label: "Check your CV" }]);
  }
});

Deno.test("the default falls back to the roadmap when the gap is not allowed", () => {
  // cv_check is not offered in explore.
  assertEquals(defaultAction(ctx, "explore"), {
    route: "roadmap",
    label: "Open your roadmap",
  });
  assertEquals(defaultAction({}, "launch"), {
    route: "roadmap",
    label: "Open your roadmap",
  });
});

Deno.test("path needs a real slug, and its label names the path", () => {
  const out = finaliseActions(
    [
      { route: "path", slug: "Data Analyst", title: "Data analyst" },
      { route: "path", slug: "data-analyst", title: "Data analyst" },
    ],
    "explore",
    ctx,
  );
  assertEquals(out, [{
    route: "path",
    slug: "data-analyst",
    label: "Read about Data analyst",
  }]);
  const long = labelFor("path", "explore", "A".repeat(80));
  assert(long.length <= 48, long);
  assert(long.endsWith("…"), long);
});

Deno.test("a model can pick any route but path", () => {
  assertEquals(MODEL_ROUTES.includes("path"), false);
  assertEquals(MODEL_ROUTES.length, COACH_ROUTES.length - 1);
});

Deno.test("each year sees the routes C7.2 gives it", () => {
  const first = ["analyser", "roadmap", "score", "paths", "path", "profile"];
  assertEquals(routesForMode("discover"), first);
  assertEquals(routesForMode("explore"), first);
  const middle = [
    "interview",
    "practice",
    "analyser",
    "cv_check",
    "cv_builder",
    "roadmap",
    "radar",
    "score",
    "paths",
    "path",
    "profile",
  ];
  assertEquals(routesForMode("build"), middle);
  assertEquals(routesForMode("prove"), middle);
  assertEquals(routesForMode("launch"), [...COACH_ROUTES]);
  assertEquals(routesForMode("graduate"), [...COACH_ROUTES]);
});

Deno.test("no early-year label uses a word about applying", () => {
  for (const mode of EARLY_MODES) {
    for (const route of routesForMode(mode)) {
      const label = labelFor(route, mode, "Data analyst");
      assert(!MODE_WORDS.test(label), `${mode}/${route}: ${label}`);
    }
  }
});

Deno.test("every label fits the database's 2 to 48 characters", () => {
  for (const mode of MODES) {
    for (const route of COACH_ROUTES) {
      const label = labelFor(route, mode, "Data analyst");
      assert(label.length >= 2 && label.length <= 48, `${route}: ${label}`);
    }
  }
});

Deno.test("an unknown mode is treated as explore", () => {
  assertEquals(normaliseMode("launch"), "launch");
  assertEquals(normaliseMode("school"), "explore");
  assertEquals(normaliseMode(undefined), "explore");
  assertEquals(normaliseMode(42), "explore");
});

Deno.test("componentRoute agrees with the score screen's routes", async () => {
  const dart = await Deno.readTextFile(
    new URL(
      "../../../../app/lib/features/score/data/readiness.dart",
      import.meta.url,
    ),
  );
  const body = dart.split("String get route => switch (key) {")[1]
    .split("};")[0];
  // The app's paths, as chip route ids. /vault/check is where the score's CV
  // action goes once the Toolkit lands; /vault is where it goes today.
  const ids: Record<string, CoachRoute> = {
    "/profile": "profile",
    "/vault": "cv_check",
    "/vault/check": "cv_check",
    "/interview": "interview",
    "/applications": "applications",
    "/roadmap": "roadmap",
  };
  let checked = 0;
  for (
    const arm of body.matchAll(
      /((?:'[a-z_]+'\s*\|\|\s*)*'[a-z_]+')\s*=>\s*'([^']+)'/g,
    )
  ) {
    const route = ids[arm[2]];
    assert(route, `no chip route for ${arm[2]}`);
    for (const key of arm[1].matchAll(/'([a-z_]+)'/g)) {
      assertEquals(componentRoute(key[1]), route, key[1]);
      checked++;
    }
  }
  assert(checked >= 11, `only ${checked} components read`);
  assertEquals(componentRoute("something_new"), "profile");
});

Deno.test("the database CHECK names exactly these route ids", async () => {
  const sql = await Deno.readTextFile(
    new URL("../../../migrations/0097_coach_context_v2.sql", import.meta.url),
  );
  const alternation = sql.match(/@\.route like_regex "\^\(([a-z_|]+)\)\$"/);
  assert(alternation, "the route alternation was not found in 0097");
  assertEquals(alternation[1].split("|"), [...COACH_ROUTES]);
});
