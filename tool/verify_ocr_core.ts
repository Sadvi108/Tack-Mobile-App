// Uses only the repository's synthetic CV photograph. No student data.
import { recogniseImage } from "../supabase/functions/_shared/cv/ocr.ts";
const file = Deno.args[0];
if (!file) throw new Error("Pass a synthetic image fixture path");
const started = performance.now();
const result = await recogniseImage(await Deno.readFile(file));
console.log(JSON.stringify({ confidence: result.confidence, chars: result.text.length, elapsedMs: Math.round(performance.now()-started) }));
if (result.confidence < 55 || result.text.length < 200) throw new Error("OCR acceptance failed");
