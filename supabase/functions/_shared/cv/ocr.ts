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

  // Run the WASM API in this isolate. Supabase does not implement Node's
  // Worker constructor, which createWorker() requires.
  let core: OcrCore;
  try {
    const { default: createCore } = await import("tesseract.js-core");
    core = await createCore({ print: () => {}, printErr: () => {} }) as OcrCore;
    const response = await fetch(
      "https://cdn.jsdelivr.net/npm/@tesseract.js-data/eng@1.0.0/4.0.0_best_int/eng.traineddata.gz",
      { signal: AbortSignal.timeout(20000) },
    );
    if (!response.ok || !response.body) {
      throw new Error("language_data_unavailable");
    }
    const language = new Uint8Array(
      await new Response(
        response.body.pipeThrough(new DecompressionStream("gzip")),
      ).arrayBuffer(),
    );
    core.FS.writeFile("/eng.traineddata", language);
  } catch (error) {
    throw new OcrUnavailable("The text reader is temporarily unavailable.", {
      cause: error,
    });
  }
  const api = new core.TessBaseAPI();
  try {
    if (api.Init("/", "eng", 1) !== 0) {
      throw new OcrUnavailable("ocr_initialization_failed");
    }
    core.FS.writeFile("/input", bytes);
    if (api.SetImageFile(1, 0) !== 0) {
      throw new UnreadableDocument(
        "Tack could not open that image. Upload your CV as a text PDF instead.",
      );
    }
    api.Recognize(null);
    return {
      text: repairOcrText(normalise(api.GetUTF8Text())),
      confidence: api.MeanTextConf(),
    };
  } finally {
    api.End();
    core.destroy(api);
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

interface OcrCore {
  destroy(object: unknown): void;
  FS: { writeFile(path: string, bytes: Uint8Array): void };
  TessBaseAPI: new () => {
    Init(path: string, language: string, mode: number): number;
    SetImageFile(orientation: number, angle: number): number;
    Recognize(monitor: null): number;
    GetUTF8Text(): string;
    MeanTextConf(): number;
    End(): void;
  };
}
