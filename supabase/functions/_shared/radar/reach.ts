/**
 * Whether Radar's Bangladesh sources can be expected to have anything.
 *
 * Bdjobs and LinkedIn arrive through the Apify importer, so they are only
 * configured when there is a token and at least one saved task to read.
 * "Not configured" and "configured but nothing fresh" are different problems
 * with different fixes, and the screen says which one it is.
 */
export function bangladeshSourceStatus(input: {
  token: string | undefined;
  tasks: string | undefined;
  fresh: boolean;
}): "not configured" | "not refreshed" | null {
  const tasks = (input.tasks ?? "").split(",").map((t) => t.trim()).filter(
    Boolean,
  );
  if (!input.token?.trim() || tasks.length === 0) return "not configured";
  return input.fresh ? null : "not refreshed";
}

/** The task ids the importer reads, in either of its two settings. */
export function apifyTaskSetting(): string | undefined {
  return [
    Deno.env.get("APIFY_JOB_TASK_IDS"),
    Deno.env.get("APIFY_BDJOBS_TASK_ID"),
  ].filter(Boolean).join(",") || undefined;
}
