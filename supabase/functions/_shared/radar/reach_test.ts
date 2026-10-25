import { assertEquals } from "@std/assert";
import { careerjet, providers } from "./providers.ts";
import { bangladeshSourceStatus } from "./reach.ts";

// Radar showed a Dhaka student nothing but foreign roles. These two boards
// are German and American, and none of their rows survive the Bangladesh
// reach rule (0095), so asking them is a wasted call on every search.
Deno.test("the live search no longer asks boards with no Bangladesh reach", () => {
  const names = providers.map((p) => p.name);
  assertEquals(names.includes("arbeitnow"), false);
  assertEquals(names.includes("themuse"), false);
  assertEquals(names.includes("careerjet"), true);
  assertEquals(names.includes("remotive"), true);
});

// "Bangladesh" was appended to every Careerjet location because of the
// locale, which made the word worthless as evidence of where a job is.
Deno.test("a Careerjet location is stored as the board gave it", async () => {
  const realFetch = globalThis.fetch;
  Deno.env.set("CAREERJET_API_KEY", "test-key");
  globalThis.fetch = () =>
    Promise.resolve(
      new Response(
        JSON.stringify({
          jobs: [
            {
              url: "https://careerjet.example/1",
              title: "Analyst",
              locations: "Dhaka",
            },
            {
              url: "https://careerjet.example/2",
              title: "Engineer",
              locations: "Dubai",
            },
          ],
        }),
      ),
    );
  try {
    const result = await careerjet({ q: "analyst" });
    assertEquals(result.listings.map((l) => l.location), ["Dhaka", "Dubai"]);
  } finally {
    globalThis.fetch = realFetch;
    Deno.env.delete("CAREERJET_API_KEY");
  }
});

// The importer and the database decide "is this in Bangladesh" from the same
// names. If one list gains a district the other lacks, a real job is kept by
// one and dropped by the other.
Deno.test("the SQL place list matches the importer's", async () => {
  const ts = await Deno.readTextFile(
    new URL("./apify_sources.ts", import.meta.url),
  );
  const sql = await Deno.readTextFile(
    new URL(
      "../../../migrations/0095_radar_bangladesh_reach.sql",
      import.meta.url,
    ),
  );
  const names = (text: string, start: RegExp, quote: string) => {
    const block = text.split(start)[1].split("]")[0];
    return [
      ...block.matchAll(
        new RegExp(`${quote}((?:[^${quote}]|${quote}${quote})+)${quote}`, "g"),
      ),
    ]
      .map((m) => m[1].replaceAll(`${quote}${quote}`, quote));
  };
  const importer = names(ts, /const places = \[/, '"');
  assertEquals(importer.length > 70, true, "the importer's list was not read");
  assertEquals(importer.includes("Cox's Bazar"), true);
  assertEquals(names(sql, /select array\[/, "'"), importer);
});

Deno.test("no Apify token means the Bangladesh sources are not configured", () => {
  assertEquals(
    bangladeshSourceStatus({ token: undefined, tasks: "task-1", fresh: false }),
    "not configured",
  );
});

Deno.test("a token without any saved task is not configured either", () => {
  assertEquals(
    bangladeshSourceStatus({ token: "t", tasks: undefined, fresh: false }),
    "not configured",
  );
  assertEquals(
    bangladeshSourceStatus({ token: "t", tasks: " , ", fresh: false }),
    "not configured",
  );
});

Deno.test("configured but with nothing fresh is not refreshed", () => {
  assertEquals(
    bangladeshSourceStatus({ token: "t", tasks: "task-1", fresh: false }),
    "not refreshed",
  );
});

Deno.test("configured and fresh is not a problem", () => {
  assertEquals(
    bangladeshSourceStatus({ token: "t", tasks: "task-1", fresh: true }),
    null,
  );
});
