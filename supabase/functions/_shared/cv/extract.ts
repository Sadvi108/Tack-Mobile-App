/**
 * Turning an uploaded file into plain text.
 *
 * This runs in the worker rather than on the phone, and that is not an
 * arbitrary choice. Redaction is mandatory before anything reaches a model and
 * redaction operates on text, so whoever produces the text has to be trusted.
 * Extracting on the device would make the text a client-supplied payload the
 * server could produce itself — and would make re-extraction impossible
 * without asking the student to upload the file again.
 *
 * Photos can be stored and opened in the vault. Reading them is deferred:
 * direct WASM OCR exceeded the hosted worker's CPU limit in the live test.
 */

/** Beyond this the extractor stops. A CV is not a book. */
export const MAX_PAGES = 6;

/** Beyond this the text is cut, and the cut is recorded in the metrics. */
export const MAX_CHARS = 40_000;

/** Under this there is no usable text layer, whatever the page count says. */
export const MIN_CHARS = 200;

export interface Extraction {
  text: string;
  pages: number;
  truncated: boolean;
  extractor: "unpdf" | "docx" | "ocr";
  /** Tesseract's own confidence, 0-100. Absent when no OCR was involved. */
  confidence?: number;
}

/**
 * A file Tack cannot read. Carries the sentence the student sees, so the
 * failure reason is written once, here, rather than guessed at each call site.
 */
export class UnreadableDocument extends Error {
  constructor(
    public readonly studentMessage: string,
    options?: { cause?: unknown },
  ) {
    super(studentMessage, options);
    this.name = "UnreadableDocument";
  }
}

const PDF = "application/pdf";
const DOCX =
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document";

export const SUPPORTED_CV_MESSAGE =
  "For CV feedback, upload a text PDF or Word (.docx) file. You can still keep and open photos in your vault.";

/** Stored photo types. These must not start the experimental OCR engine. */
const IMAGES = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/heic",
  "image/heif",
]);

export function isExtractable(mimeType: string | null): boolean {
  return mimeType === PDF || mimeType === DOCX;
}

export async function extractDocument(
  bytes: Uint8Array,
  mimeType: string | null,
): Promise<Extraction> {
  if (mimeType === PDF) return finish(await fromPdf(bytes), "unpdf");
  if (mimeType === DOCX) return finish(await fromDocx(bytes), "docx");

  if (mimeType !== null && IMAGES.has(mimeType)) {
    throw new UnreadableDocument(SUPPORTED_CV_MESSAGE);
  }

  // A legacy .doc is a binary format nothing here can open.
  throw new UnreadableDocument(SUPPORTED_CV_MESSAGE);
}

function finish(
  raw: { text: string; pages: number },
  extractor: "unpdf" | "docx" | "ocr",
  confidence?: number,
): Extraction {
  const cleaned = normalise(raw.text);

  if (cleaned.length < MIN_CHARS) {
    throw new UnreadableDocument(
      extractor === "ocr"
        ? "Tack could not find enough writing in that photo. Make sure the " +
          "whole CV is in frame and in focus, or upload a PDF instead."
        : "That file has no text Tack can read — it is probably a scan. " +
          "Export your CV as a PDF from the app you wrote it in and upload that.",
    );
  }

  const truncated = cleaned.length > MAX_CHARS;
  return {
    text: truncated ? cleaned.slice(0, MAX_CHARS) : cleaned,
    pages: raw.pages,
    truncated,
    extractor,
    confidence,
  };
}

/** Collapses the whitespace an extractor leaves behind, keeping line breaks. */
export function normalise(text: string): string {
  return text
    .replace(/\r\n?/g, "\n")
    .replace(/ /g, " ")
    .split("\n")
    .map((line) => line.replace(/[ \t]+/g, " ").trim())
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

// ---------------------------------------------------------------------- PDF

async function fromPdf(
  bytes: Uint8Array,
): Promise<{ text: string; pages: number }> {
  // Imported lazily so a DOCX upload does not pay for loading a PDF engine.
  const { extractText, getDocumentProxy } = await import("unpdf");

  let pdf;
  try {
    pdf = await getDocumentProxy(bytes);
  } catch {
    throw new UnreadableDocument(
      "That PDF could not be opened. It may be password protected — save an " +
        "unprotected copy and upload that.",
    );
  }

  const total: number = pdf.numPages ?? 1;
  const { text } = await extractText(pdf, { mergePages: true });

  // unpdf merges every page into one string, so the page limit is applied to
  // the text proportionally rather than page by page.
  //
  // The count returned is the real one, not the capped one: hygiene asks
  // whether a junior's CV runs past a single page, and reporting 6 for a
  // forty-page upload would hide exactly the thing it is looking for.
  const share = total > MAX_PAGES
    ? Math.ceil(text.length * (MAX_PAGES / total))
    : text.length;

  return { text: text.slice(0, share), pages: total };
}

// --------------------------------------------------------------------- DOCX

/**
 * A .docx is a zip holding word/document.xml.
 *
 * Read with the platform's own DecompressionStream rather than a zip library:
 * one dependency for PDF is a considered cost, a second one for unzipping a
 * single known entry is not.
 */
async function fromDocx(
  bytes: Uint8Array,
): Promise<{ text: string; pages: number }> {
  const xml = await readZipEntry(bytes, "word/document.xml");
  if (!xml) {
    throw new UnreadableDocument(
      "That Word file could not be read. Save it as a PDF and upload that instead.",
    );
  }

  const text = new TextDecoder().decode(xml)
    // Paragraph and line breaks carry the structure the metrics read, so they
    // survive; every other tag goes.
    .replace(/<w:tab\b[^>]*\/>/g, " ")
    .replace(/<w:br\b[^>]*\/>/g, "\n")
    .replace(/<\/w:p>/g, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&");

  // Word does not record a page count anywhere reliable, and the layout that
  // would produce one is not reconstructed here. Estimated from length, which
  // is only ever used to check the CV is not enormous.
  const pages = Math.max(1, Math.ceil(text.length / 3000));
  return { text, pages };
}

const u16 = (b: Uint8Array, o: number) => b[o] | (b[o + 1] << 8);
const u32 = (b: Uint8Array, o: number) =>
  (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)) >>> 0;

/** Returns the decompressed bytes of one entry, or null when it is absent. */
export async function readZipEntry(
  zip: Uint8Array,
  name: string,
): Promise<Uint8Array | null> {
  // The end-of-central-directory record lives in the last 64KB, after a
  // comment of unknown length, so it is found by scanning backwards.
  let eocd = -1;
  const floor = Math.max(0, zip.length - 66_000);
  for (let i = zip.length - 22; i >= floor; i--) {
    if (u32(zip, i) === 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) return null;

  const count = u16(zip, eocd + 10);
  let p = u32(zip, eocd + 16);
  const wanted = new TextEncoder().encode(name);

  for (let i = 0; i < count; i++) {
    if (u32(zip, p) !== 0x02014b50) return null;
    const method = u16(zip, p + 10);
    const compressed = u32(zip, p + 20);
    const nameLen = u16(zip, p + 28);
    const extraLen = u16(zip, p + 30);
    const commentLen = u16(zip, p + 32);
    const localOffset = u32(zip, p + 42);
    const entryName = zip.subarray(p + 46, p + 46 + nameLen);

    if (sameBytes(entryName, wanted)) {
      if (u32(zip, localOffset) !== 0x04034b50) return null;
      // The local header repeats the name and extra fields, and its lengths
      // are the authoritative ones for locating the data.
      const dataStart = localOffset + 30 + u16(zip, localOffset + 26) +
        u16(zip, localOffset + 28);
      // Copied rather than viewed: a subarray keeps the whole zip's buffer
      // alive, and its ArrayBufferLike type is not a BufferSource.
      const data = new Uint8Array(
        zip.subarray(dataStart, dataStart + compressed),
      );

      if (method === 0) return data;
      if (method !== 8) return null;

      const source = new ReadableStream<BufferSource>({
        start(controller) {
          controller.enqueue(data);
          controller.close();
        },
      });
      const stream = source.pipeThrough(new DecompressionStream("deflate-raw"));
      return new Uint8Array(await new Response(stream).arrayBuffer());
    }

    p += 46 + nameLen + extraLen + commentLen;
  }

  return null;
}

function sameBytes(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}
