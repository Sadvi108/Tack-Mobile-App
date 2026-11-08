import { assertEquals } from "@std/assert";

import { privacy } from "../policies/content.ts";

// The policies function serves its own copy of the privacy policy, because an
// Edge Function cannot read the repository at run time. A copy is only safe
// while it is the same text: the policy a student reads in the app and the one
// in the repository must never say different things.
Deno.test("the served privacy policy is PRIVACY.md, word for word", () => {
  assertEquals(privacy, Deno.readTextFileSync("../../PRIVACY.md"));
});
