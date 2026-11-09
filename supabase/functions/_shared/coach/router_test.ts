import { assert, assertEquals } from "@std/assert";
import {
  answerFromData,
  answerIntent,
  type Context,
  INTENTS,
  matchIntent,
  MODE_WORDS,
  normalise,
} from "./router.ts";
import { EARLY_MODES, type Mode, MODES, routesForMode } from "./actions.ts";

const ctx: Context = {
  mode: "launch",
  target_role: "Backend developer",
  target_path: { title: "Frontend developer", slug: "frontend-developer" },
  score: {
    total: 13,
    components: {
      projects: { earned: 0, max: 10, available: 10 },
      skills: { earned: 6, max: 12, available: 6 },
      cv_quality: { earned: 0, max: 13, available: 13 },
      application_activity: { earned: 0, max: 0, available: 0 },
    },
  },
  skills_held: ["Python"],
  skill_gap: ["CSS", "HTML", "JavaScript"],
  roadmap: { done: 4, total: 23, next: "Learn TypeScript basics" },
  applications: { applied: 1, interview: 1 },
  has_cv: false,
  streak: 2,
};

Deno.test("a question about what to do next is answered from the numbers", () => {
  const a = answerFromData("What should I do next?", ctx);
  assert(a, "should not need the model");
  assertEquals(a.answeredBy, "data");
  // cv_quality has the most available, so it leads.
  assert(a.body.includes("your CV"), a.body);
  assert(a.body.includes("13 points"), a.body);
  assert(a.body.includes("Learn TypeScript basics"), a.body);
});

Deno.test("a component this mode does not count is never offered", () => {
  // application_activity is weighted zero here; suggesting it would be the
  // same bug the dashboard had.
  const a = answerFromData("what should I work on", ctx);
  assert(a);
  assert(!a.body.includes("applications"), a.body);
});

Deno.test("the score question quotes the real total", () => {
  const a = answerFromData("how am I doing?", ctx);
  assert(a);
  assert(a.body.startsWith("You are on 13 out of 100."), a.body);
});

Deno.test("the skill gap names the target path, not the typed role", () => {
  // The path is what the roadmap and score are built from. Saying "Backend
  // developer" here would repeat the bug the dashboard had.
  const a = answerFromData("what skills am I missing?", ctx);
  assert(a);
  assert(a.body.includes("Frontend developer"), a.body);
  assert(a.body.includes("CSS, HTML and JavaScript"), a.body);
});

Deno.test("no target path is said plainly rather than guessed at", () => {
  const a = answerFromData("what skills do I need?", {
    ...ctx,
    target_path: null,
  });
  assert(a);
  assert(a.body.includes("not picked a target path"), a.body);
});

Deno.test("roadmap progress comes from the count, not a guess", () => {
  const a = answerFromData("how far through my roadmap am I?", ctx);
  assert(a);
  assert(a.body.includes("4 of 23"), a.body);
});

Deno.test("an empty roadmap says so instead of reporting zero of zero", () => {
  const a = answerFromData("my roadmap progress", {
    ...ctx,
    roadmap: { done: 0, total: 0, next: null },
  });
  assert(a);
  assert(a.body.includes("do not have a roadmap yet"), a.body);
});

Deno.test("a real question still goes to the model", () => {
  // The allowance exists for these.
  for (
    const q of [
      "How do I explain a gap year in an interview?",
      "Is a to-do app good enough to put on my CV?",
      "Write me a message to send a recruiter on LinkedIn",
      "Should I take an unpaid internship?",
    ]
  ) {
    assertEquals(answerFromData(q, ctx), null, q);
  }
});

Deno.test("a question that matches but has no data falls through to the model", () => {
  // Rather than answering "your weakest area is undefined".
  const empty: Context = { score: { total: 0, components: {} } };
  assertEquals(answerFromData("what is my weakest area?", empty), null);
});

Deno.test("what next is always answered, even with nothing measured", () => {
  // It used to fall through to the model and spend an action on a student
  // who had nothing to measure yet.
  const empty = answerFromData("What should I do next?", {});
  assert(empty, "next must be total");
  assertEquals(
    empty.body,
    "Pick a target path first. It turns your score into a plan.",
  );

  const roadmapOnly = answerFromData("What should I do next?", {
    roadmap: { done: 0, total: 5, next: "Read the role guide" },
  });
  assert(roadmapOnly);
  assert(roadmapOnly.body.includes("Read the role guide"), roadmapOnly.body);
});

Deno.test("early years hear about their focus, not an application count", () => {
  for (
    const [mode, focus] of [
      ["discover", "exploring paths"],
      ["explore", "exploring paths"],
      ["build", "building skills"],
    ]
  ) {
    const a = answerFromData("how are my applications going", {
      ...ctx,
      mode,
    });
    assert(a, mode);
    assertEquals(
      a.body,
      `Right now your focus is on ${focus}. Tracking jobs comes later, in your final year.`,
    );
  }
  const launch = answerFromData("how are my applications going", ctx);
  assert(launch);
  assert(launch.body.startsWith("You are tracking 2"), launch.body);
});

Deno.test("progress means roadmap progress only when it says so", () => {
  const mine = answerFromData("my progress", ctx);
  assert(mine);
  assert(mine.body.includes("4 of 23"), mine.body);
  const roadmap = answerFromData("show my roadmap progress", ctx);
  assert(roadmap);
  assert(roadmap.body.includes("4 of 23"), roadmap.body);
  // Not the roadmap: this is about interviews, and now the interview intent
  // answers it.
  assertEquals(
    answerFromData("my interview progress", ctx)?.intent,
    "interview",
  );
});

// ---------------------------------------------------------------- router v2

/** Everything coach_context() v2 can say, for a final-year. */
const rich: Context = {
  version: 2,
  today: "2026-11-06",
  mode: "launch",
  year_of_study: 4,
  target_role: "Data analyst",
  target_path: { title: "Data analyst", slug: "data-analyst" },
  score: {
    total: 41,
    components: {
      cv_quality: { earned: 6, max: 13, available: 7 },
      projects: { earned: 2, max: 10, available: 8 },
      skills: { earned: 9, max: 12, available: 3 },
      application_activity: { earned: 0, max: 5, available: 5 },
      academic: { earned: 10, max: 10, available: 0 },
    },
  },
  cohort: { average: 38, size: 12 },
  skills_held: ["Excel", "SQL"],
  skill_gap: ["Python", "Tableau"],
  roadmap: {
    done: 4,
    total: 12,
    overdue: 1,
    next: "Learn SQL joins",
    next_due: "2026-11-03",
    next_points: 3,
  },
  applications: { saved: 2, applied: 1 },
  has_cv: true,
  cv: {
    has_cv: true,
    last_check: {
      on: "2026-11-04",
      problems: 1,
      suggestions: 3,
      top: [
        {
          kind: "contact",
          severity: "problem",
          title: "No way to contact you",
        },
      ],
    },
  },
  interview: {
    sessions: 3,
    last: { on: "2026-11-04", role: "Data analyst", score: 5.7 },
    average: 6.2,
    by_category: [
      { category: "SQL", average: 4.5, answers: 2 },
      { category: "Behavioural", average: 8, answers: 1 },
    ],
    due_reviews: 2,
  },
  upcoming: [
    { kind: "task", title: "Learn SQL joins", on: "2026-11-03" },
    { kind: "follow_up", title: "Junior analyst · A bank", on: "2026-11-08" },
    { kind: "task", title: "Build a dashboard", on: "2026-11-10" },
    { kind: "closing", title: "Junior analyst · A bank", on: "2026-11-12" },
  ],
  streak: 5,
};

const CORPUS: [string, Mode, string | null][] = [
  // interview
  ["How do I prepare for an interview?", "launch", "interview"],
  ["help me prepare for interviews", "launch", "interview"],
  ["How should I practise for an interview?", "prove", "interview"],
  ["my interview scores", "launch", "interview"],
  ["How did I do in my last interview?", "launch", "interview"],
  ["Am I ready for interviews?", "launch", "interview"],
  ["What is my weakest area in interviews?", "launch", "interview"],
  ["my interview progress", "build", "interview"],
  ["how am i doing in interviews", "prove", "interview"],
  ["Hi coach, how do I prepare for an interview?", "build", "interview"],
  ["How do I explain a gap year in an interview?", "launch", null],
  ["How do I answer tell me about yourself in an interview?", "launch", null],
  ["Prepare for an interview at a bank next week", "launch", null],
  // cv
  ["Is my CV ok?", "prove", "cv"],
  ["does my resume look good", "launch", "cv"],
  ["check my CV", "launch", "cv"],
  ["please check my resume", "build", "cv"],
  ["How is my CV?", "launch", "cv"],
  ["What's wrong with my CV?", "launch", "cv"],
  ["What’s wrong with my CV?", "launch", "cv"],
  ["my cv score", "launch", "cv"],
  ["Is a to-do app good enough to put on my CV?", "launch", null],
  ["Should I put my CGPA on my CV?", "launch", null],
  ["Write my CV summary", "launch", null],
  // score_explain
  ["Explain my score", "explore", "score_explain"],
  ["break down my readiness score", "launch", "score_explain"],
  ["Why is my score so low?", "build", "score_explain"],
  ["How is my score calculated?", "launch", "score_explain"],
  ["What makes up my score?", "discover", "score_explain"],
  ["How do I get my score to 80 by June?", "launch", null],
  // dates
  ["What is coming up this week?", "launch", "dates"],
  ["what's due", "prove", "dates"],
  ["Upcoming deadlines", "graduate", "dates"],
  ["my important dates", "launch", "dates"],
  ["Any deadlines this week?", "launch", "dates"],
  ["hey coach, what's coming up this week?", "launch", "dates"],
  ["When is the BCS exam deadline?", "launch", null],
  ["What is coming up this week?", "explore", null],
  ["What is coming up this week?", "build", null],
  // the rules that came first
  ["What should I do next?", "launch", "next"],
  ["what should I work on", "explore", "next"],
  ["How am I doing?", "launch", "score"],
  ["What skills am I missing?", "build", "skills"],
  ["How far through my roadmap am I?", "explore", "roadmap"],
  ["how many jobs have I applied to", "launch", "applications"],
  ["what is my weakest area?", "launch", "weakest"],
  // what the allowance is for
  ["Write me a message to send a recruiter on LinkedIn", "launch", null],
  ["Should I take an unpaid internship?", "prove", null],
  ["What does a data analyst do day to day?", "launch", null],
  [
    "How do I prepare for an interview when I am nervous and have never done one before?",
    "launch",
    null,
  ],
  ["Tell me a joke", "explore", null],
];

Deno.test("the corpus routes where it should, and the rest goes to the model", () => {
  assert(CORPUS.length >= 50, `${CORPUS.length} rows`);
  for (const [q, mode, expected] of CORPUS) {
    assertEquals(matchIntent(q, { ...rich, mode }), expected, `${mode}: ${q}`);
  }
});

Deno.test("normalise drops greetings, please and closing punctuation", () => {
  assertEquals(normalise("  Hi coach, PLEASE check my CV?! "), "check my cv");
  assertEquals(normalise("What’s due?"), "what's due");
});

Deno.test("each new intent answers a rich context and an empty one", () => {
  for (const id of ["interview", "cv", "score_explain", "dates"] as const) {
    assert(answerIntent(id, rich), `${id} on the rich context`);
  }
  for (const id of ["interview", "cv", "score_explain"] as const) {
    assert(answerIntent(id, {}), `${id} on {}`);
  }
  // {} is an explore context, where dates do not exist.
  assertEquals(answerIntent("dates", {}), null);
  assert(answerIntent("dates", { mode: "launch" }));
});

Deno.test("dates are for prove and later only", () => {
  for (const mode of EARLY_MODES) {
    assertEquals(answerIntent("dates", { ...rich, mode }), null, mode);
  }
  for (const mode of ["prove", "launch", "graduate"]) {
    assert(answerIntent("dates", { ...rich, mode }), mode);
  }
});

Deno.test("next is total in every year", () => {
  for (const mode of MODES) {
    assert(answerIntent("next", { mode }), `${mode} empty`);
    assert(answerIntent("next", { ...rich, mode }), `${mode} rich`);
  }
});

Deno.test("early years never read a word about applying", () => {
  for (const mode of EARLY_MODES) {
    for (const id of INTENTS) {
      const a = answerIntent(id, { ...rich, mode });
      if (!a) continue;
      assert(!MODE_WORDS.test(a.body), `${mode}/${id}: ${a.body}`);
      for (const action of a.actions) {
        assert(
          !MODE_WORDS.test(action.label),
          `${mode}/${id}: ${action.label}`,
        );
      }
    }
  }
});

Deno.test("every answer points somewhere the year may go", () => {
  for (const mode of MODES) {
    for (const base of [rich, {}]) {
      for (const id of INTENTS) {
        const a = answerIntent(id, { ...base, mode });
        if (!a) continue;
        assertEquals(a.intent, id);
        assertEquals(a.answeredBy, "data");
        assert(a.actions.length >= 1, `${mode}/${id} has no action`);
        assert(a.actions.length <= 2, `${mode}/${id} has too many`);
        for (const action of a.actions) {
          assert(
            routesForMode(mode).includes(action.route),
            `${mode}/${id}: ${action.route}`,
          );
        }
        assert(!/vault/i.test(a.body), `${mode}/${id} says vault`);
      }
    }
  }
});

Deno.test("the interview answer reads the practice record", () => {
  const a = answerIntent("interview", rich);
  assert(a);
  assertEquals(
    a.body,
    "Your last practice interview, 2 days ago, scored 5.7 out of 10. " +
      "SQL questions are your weakest so far, at 4.5 on average. " +
      "2 of your answers are ready to practise again today. That practice is free. " +
      "Practise those answers again first.",
  );
  assertEquals(a.actions.map((x) => x.route), ["practice", "interview"]);

  const fresh = answerIntent("interview", { mode: "build" });
  assert(fresh);
  assert(fresh.body.includes("safe way"), fresh.body);
  const later = answerIntent("interview", { mode: "launch" });
  assert(later && !later.body.includes("safe"), later?.body);
  assertEquals(
    answerIntent("interview", { mode: "discover" })?.actions[0].route,
    "paths",
  );
});

Deno.test("the CV answer starts with the first finding", () => {
  const a = answerIntent("cv", rich);
  assert(a);
  assertEquals(
    a.body,
    "Your last CV check, 2 days ago, found 1 problem and 3 things to improve. " +
      "Your CV can still add 7 points to your score. " +
      "Start with this one: No way to contact you.",
  );
  assertEquals(a.actions.map((x) => x.route), ["cv_check"]);
  const none = answerIntent("cv", { mode: "build", has_cv: false });
  assert(none);
  assert(none.body.includes("your documents"), none.body);
  assertEquals(none.actions.map((x) => x.route), ["cv_check", "cv_builder"]);
  const unchecked = answerIntent("cv", {
    mode: "prove",
    cv: { has_cv: true, last_check: null },
  });
  assert(
    unchecked?.body.startsWith("Your CV is saved but has not been checked"),
  );
});

Deno.test("the score is explained against the student's own year", () => {
  const close = answerIntent("score_explain", rich);
  assert(close);
  assertEquals(
    close.body,
    "You are on 41 out of 100. Most of it comes from your academic record and your skills. " +
      "The most room left is in projects and your CV (15 points). " +
      "That is close to the final-years average. Start with projects this week.",
  );
  const behind = answerIntent("score_explain", {
    ...rich,
    mode: "explore",
    cohort: { average: 60, size: 30 },
  });
  assert(behind);
  assert(
    behind.body.includes(
      "Most first-years are a little ahead right now. Projects is the quickest way to catch up.",
    ),
    behind.body,
  );
  const ahead = answerIntent("score_explain", {
    ...rich,
    mode: "build",
    cohort: { average: 20, size: 30 },
  });
  assert(ahead?.body.includes("That is ahead of most second-years."));
  const alone = answerIntent("score_explain", { ...rich, cohort: null });
  assert(alone && !alone.body.includes("average"), alone?.body);
});

Deno.test("dates lead with what is still open, kindly", () => {
  const a = answerIntent("dates", rich);
  assert(a);
  assertEquals(
    a.body,
    [
      "Still open from earlier: Learn SQL joins, which was due 3 days ago.",
      "Follow up: Junior analyst · A bank, in 2 days.",
      "Build a dashboard is due in 4 days.",
      "Applications close: Junior analyst · A bank, in 6 days.",
      "Start with the first one on this list.",
    ].join("\n"),
  );
  assertEquals(a.actions.map((x) => x.route), ["roadmap"]);

  const empty = answerIntent("dates", { ...rich, upcoming: [] });
  assertEquals(
    empty?.body,
    "Nothing is due in the next two weeks. A good time for the next roadmap step: Learn SQL joins.",
  );
  const followUp = answerIntent("dates", {
    ...rich,
    upcoming: [{
      kind: "follow_up",
      title: "Intern · A bank",
      on: "2026-11-06",
    }],
  });
  assertEquals(followUp?.actions.map((x) => x.route), ["applications"]);
  assert(followUp?.body.startsWith("Follow up: Intern · A bank, today."));
});

Deno.test("a date within three days leads what next, in later years only", () => {
  const launch = answerIntent("next", rich);
  assert(launch);
  assert(
    launch.body.startsWith(
      "First, a follow-up is due in 2 days: Junior analyst · A bank.",
    ),
    launch.body,
  );
  assertEquals(launch.actions[0].route, "applications");

  const build = answerIntent("next", { ...rich, mode: "build" });
  assert(build);
  assert(!build.body.includes("follow-up"), build.body);
  assert(build.body.startsWith("The biggest win right now is projects"));
});

Deno.test("prove's dates point at the roadmap, which it may open", () => {
  // The application list is not a prove route. Offering it meant the chip
  // was silently swapped for the default; the roadmap is chosen instead.
  const followUpFirst = {
    ...rich,
    mode: "prove",
    upcoming: [
      { kind: "follow_up", title: "Intern · A bank", on: "2026-11-07" },
      { kind: "task", title: "Build a dashboard", on: "2026-11-10" },
    ],
  };
  const dates = answerIntent("dates", followUpFirst);
  assertEquals(dates?.actions.map((a) => a.route), ["roadmap"]);
  const next = answerIntent("next", followUpFirst);
  assert(next?.body.startsWith("First, a follow-up is due tomorrow"));
  assertEquals(next?.actions[0].route, "roadmap");
  // Launch may open it, so it still leads there.
  assertEquals(
    answerIntent("dates", { ...followUpFirst, mode: "launch" })?.actions.map(
      (a) => a.route,
    ),
    ["applications"],
  );
});

Deno.test("old rules gain chips but keep their words", () => {
  assertEquals(
    answerFromData("how am I doing?", ctx)?.actions.map((a) => a.route),
    ["score"],
  );
  const skills = answerFromData("what skills am I missing?", ctx);
  assertEquals(skills?.actions.map((a) => a.route), ["paths", "profile"]);
  const weakest = answerFromData("what is my weakest area?", ctx);
  // cv_quality has the most left, so the chip opens the CV check.
  assertEquals(weakest?.actions.map((a) => a.route), ["cv_check"]);
});
