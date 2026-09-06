import { assertEquals } from "@std/assert";
import {
  analysisRequest,
  coachRequest,
  documentRequest,
  evaluateRequest,
  questionsRequest,
  readRequest,
} from "./requests.ts";

const request = (body: unknown) =>
  new Request("https://tack.test/endpoint", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
Deno.test("malformed feature requests are rejected without coercion", async () => {
  for (
    const [schema, body] of [
      [analysisRequest, { text: 42 }],
      [coachRequest, { question: 42 }],
      [documentRequest, null],
      [documentRequest, { documentId: "other-user" }],
      [questionsRequest, { role: 42 }],
      [questionsRequest, { role: "Developer", count: "5" }],
      [questionsRequest, { role: "Developer", difficulty: "impossible" }],
      [evaluateRequest, {
        questionId: crypto.randomUUID(),
        answer: "a".repeat(10001),
      }],
    ] as const
  ) {
    const result = await readRequest(
      request(body),
      schema as typeof analysisRequest,
    );
    assertEquals(result instanceof Response && result.status, 400);
  }
});
Deno.test("request streams are bounded and methods enforced", async () => {
  const oversized = await readRequest(
    request({ text: "a".repeat(100000) }),
    analysisRequest,
  );
  assertEquals(oversized instanceof Response && oversized.status, 413);
  const method = await readRequest(
    new Request("https://tack.test"),
    documentRequest,
  );
  assertEquals(method instanceof Response && method.status, 405);
});
Deno.test("valid requests retain defaults and refuse unknown fields", async () => {
  assertEquals(
    await readRequest(request({ role: "Developer" }), questionsRequest),
    {
      role: "Developer",
      count: 5,
      difficulty: "medium",
      sessionType: "mixed",
    },
  );
  const result = await readRequest(
    request({ documentId: crypto.randomUUID(), userId: crypto.randomUUID() }),
    documentRequest,
  );
  assertEquals(result instanceof Response && result.status, 400);
});
