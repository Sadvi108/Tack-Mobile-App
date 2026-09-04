import { assertEquals } from "@std/assert";
import { parseRepo } from "./github.ts";

// Students paste the address bar, so the parser sees every shape a browser
// can produce. Each of these was a real thing somebody would paste.
Deno.test("parses the shapes a student actually pastes", () => {
  const expected = { owner: "rafiq", repo: "bus-tracker" };
  for (
    const url of [
      "https://github.com/rafiq/bus-tracker",
      "http://github.com/rafiq/bus-tracker",
      "github.com/rafiq/bus-tracker",
      "https://github.com/rafiq/bus-tracker/",
      "https://github.com/rafiq/bus-tracker.git",
      "https://www.github.com/rafiq/bus-tracker",
      "  https://github.com/rafiq/bus-tracker  ",
      // Pasted from deep inside the tree, which is what happens when they
      // copy the link to the file they are proud of.
      "https://github.com/rafiq/bus-tracker/blob/main/lib/main.dart",
    ]
  ) {
    assertEquals(parseRepo(url), expected, url);
  }
});

Deno.test("refuses what is not a repository", () => {
  for (
    const url of [
      "",
      "   ",
      // A profile has an owner and no repo. Verifying it would claim a person
      // is a project.
      "https://github.com/rafiq",
      "https://gitlab.com/rafiq/bus-tracker",
      "https://notgithub.com/rafiq/bus-tracker",
      "https://github.evil.com/rafiq/bus-tracker",
      "not a url at all",
    ]
  ) {
    assertEquals(parseRepo(url), null, url);
  }
});

Deno.test("refuses owner names GitHub itself would refuse", () => {
  assertEquals(parseRepo("https://github.com/-bad/repo"), null);
  assertEquals(parseRepo("https://github.com/bad-/repo"), null);
});
