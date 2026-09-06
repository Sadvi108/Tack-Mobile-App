import { z } from "zod";
import { fail } from "./http.ts";

const id = z.uuid();
export const documentRequest = z.strictObject({ documentId: id });
export const analysisRequest = z.strictObject({
  text: z.string().trim().min(80).max(20000),
  jobId: id.optional(),
});
export const coachRequest = z.strictObject({
  question: z.string().trim().min(2).max(1000),
  threadId: id.optional(),
  operationId: id.optional(),
});
export const questionsRequest = z.strictObject({
  role: z.string().trim().min(2).max(120),
  sessionType: z.enum(["mixed", "technical", "behavioural"]).default("mixed"),
  difficulty: z.enum(["easy", "medium", "hard"]).default("medium"),
  count: z.number().int().min(3).max(10).default(5),
});
export const evaluateRequest = z.strictObject({
  questionId: id,
  answer: z.string().trim().min(20).max(10000),
});

/** Bound the stream before JSON decoding, including requests without a length. */
export async function readRequest<T>(
  req: Request,
  schema: z.ZodType<T>,
): Promise<T | Response> {
  if (req.method !== "POST") {
    return fail("Use POST.", 405, "method_not_allowed");
  }
  if (
    !req.headers.get("content-type")?.toLowerCase().startsWith(
      "application/json",
    )
  ) {
    return fail("Send this request as JSON.", 415, "unsupported_media_type");
  }
  const reader = req.body?.getReader();
  if (!reader) {
    return fail("That request could not be read.", 400, "invalid_request");
  }
  try {
    let size = 0;
    const chunks: Uint8Array[] = [];
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 96 * 1024) {
        await reader.cancel();
        return fail(
          "That request is too long. Shorten it and try again.",
          413,
          "request_too_large",
        );
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
    const parsed = schema.safeParse(
      JSON.parse(new TextDecoder().decode(bytes)),
    );
    if (!parsed.success) {
      return fail("Check the details and try again.", 400, "invalid_request");
    }
    return parsed.data;
  } catch {
    return fail("That request could not be read.", 400, "invalid_request");
  } finally {
    reader.releaseLock();
  }
}
