/**
 * Reading a CV that is a photograph.
 *
 * Most students here have a paper CV and a phone camera, not a scanner, so a
 * photo is the first thing many will upload. Until now that was refused.
 *
 * The engine is Tesseract, running as WebAssembly in the worker. It is not a
 * model, and that is the whole reason it can be here: `AGENTS.md` requires
 * contact details to be stripped before anything reaches a model, and stripping
 * them requires text. Handing the raw photograph to a multimodal model would
 * send the student's phone number and email to a provider in the one step that
 * exists to stop exactly that.
 */
import { normalise, UnreadableDocument } from "./extract.ts";

/** Below this the text is guesswork, and a score built on it would be a lie. */
export const MIN_CONFIDENCE = 55;

export interface OcrResult {
  text: string;
  confidence: number;
}

/**
 * The engine itself could not start.
 *
 * Deliberately not an UnreadableDocument: nothing is wrong with the student's
 * photo, and telling them to take a better one would be a lie. The job fails,
 * the worker records it, and somebody looks at the logs.
 */
export class OcrUnavailable extends Error {
  constructor(message: string, options?: { cause?: unknown }) {
    super(message, options);
    this.name = "OcrUnavailable";
  }
}

/**
 * Does this actually start like an image?
 *
 * Checked before Tesseract sees it, and not as belt and braces. Handed data it
 * cannot decode, the engine throws from inside its own worker's message
 * handler — an unhandled rejection that escapes a try/catch around the call
 * and takes the isolate down with it. A truncated upload should cost one
 * student a readable error, not everyone else their queued jobs.
 */
export function looksLikeImage(bytes: Uint8Array): boolean {
  // No photograph of a CV is under a kilobyte.
  if (bytes.length < 1024) return false;

  const starts = (...sig: number[]) => sig.every((b, i) => bytes[i] === b);
  const ascii = (offset: number, text: string) =>
    [...text].every((c, i) => bytes[offset + i] === c.charCodeAt(0));

  if (starts(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)) return true; // PNG
  if (starts(0xff, 0xd8, 0xff)) return true; // JPEG
  if (ascii(0, "RIFF") && ascii(8, "WEBP")) return true; // WebP
  if (ascii(4, "ftyp")) return true; // HEIC and friends

  return false;
}

export async function recogniseImage(bytes: Uint8Array): Promise<OcrResult> {
  if (!looksLikeImage(bytes)) {
    throw new UnreadableDocument(
      "That file did not arrive as a readable photo. Try taking it again, or " +
        "upload your CV as a PDF instead.",
    );
  }

  const { createWorker } = await import("tesseract.js");

  // Tesseract fetches ~5MB of trained data on first use and caches it beside
  // the process. An Edge Function's filesystem is read-only apart from /tmp,
  // so left alone this writes eng.traineddata into the working directory —
  // which fails there, and which littered the repository here.
  //
  // Starting the engine is caught apart from reading the image, because the
  // two failures mean completely different things. A bad photo is one
  // student's problem. An engine that will not start is OCR not working at
  // all — most likely because Supabase's Edge Runtime does not give
  // tesseract.js the worker threads it wants, which could not be tested here
  // without Docker. That distinction is what makes it findable in the logs
  // rather than a mystery.
  let worker;
  try {
    worker = await createWorker("eng", undefined, { cachePath: "/tmp" });
  } catch (error) {
    throw new OcrUnavailable(
      `the OCR engine did not start: ${(error as Error).message}`,
      { cause: error },
    );
  }
  try {
    // The bytes go in as they are. tesseract.js types its input as a Node
    // Buffer, which Deno has no business constructing, and wrapping them in a
    // Blob to satisfy that type made the engine read a truncated file — the
    // types are wrong about what the runtime accepts, so the cast is the
    // honest fix rather than changing the value to suit them.
    const { data } = await worker.recognize(
      bytes as unknown as Parameters<typeof worker.recognize>[0],
    );
    return {
      text: repairOcrText(normalise(data.text ?? "")),
      confidence: data.confidence ?? 0,
    };
  } catch (error) {
    // Tesseract says "Error attempting to read image" for anything it cannot
    // decode — a truncated upload, a HEIC variant it does not know, a file
    // whose extension lied. None of that is the student's fault to diagnose.
    throw new UnreadableDocument(
      "Tack could not open that image. Try taking the photo again, or upload " +
        "your CV as a PDF instead.",
      { cause: error },
    );
  } finally {
    await worker.terminate();
  }
}

/**
 * Puts back together what the scanner pulled apart.
 *
 * Tesseract reads `rifat.hasan@example.com` as `rifat. hasan @example.com`,
 * and that is not a cosmetic problem. The redaction regexes are written for
 * text a person typed, so a spaced address matches nothing, survives redact(),
 * survives assertClean(), and goes to the model — which is the one outcome the
 * redaction step exists to prevent. Verified before this function existed:
 *
 *   emails found: []
 *   assertClean: passed
 *
 * So the repair runs before anything else sees the text. It is deliberately
 * narrow: it only closes gaps inside spans that already look like an address,
 * rather than collapsing spaces generally, which would weld sentences together
 * and wreck the bullet counting that the score depends on.
 */
export function repairOcrText(text: string): string {
  return text
    // An address, however badly spaced. The left side may pick up at most two
    // stray words, which is enough for "rifat. hasan @…" without swallowing
    // the sentence in front of it.
    //
    // The ending is a list of real top-level domains, not "two or more
    // letters": the looser rule welded "cost @ scale. Shipped" into an address
    // and mangled ordinary prose on the way past.
    //
    // Spaces and tabs only, never \s: an address does not span lines, and
    // allowing newlines pulled the surname off the line above into it.
    .replace(
      /[A-Za-z0-9._%+-]+(?:[ \t]+[A-Za-z0-9._%+-]+){0,2}[ \t]*@[ \t]*[A-Za-z0-9.-]+[ \t]*\.[ \t]*(?:com|org|net|edu|gov|io|co|dev|me|info|app|ai|bd|uk|us|xyz)\b/gi,
      (match) => match.replace(/\s+/g, ""),
    )
    // github.com/name and linkedin.com/in/name, which OCR spaces the same way
    // and which redact() treats as contact details too.
    .replace(
      /\b(?:https?:\/\/)?(?:www[ \t]*\.[ \t]*)?[A-Za-z0-9-]+[ \t]*\.[ \t]*(?:com|org|net|edu|gov|io|co|dev|me|info|app|ai|bd|uk|us|xyz)\b(?:[ \t]*\/[ \t]*[A-Za-z0-9._~-]+)*/gi,
      (match) => match.replace(/\s+/g, ""),
    );
}
