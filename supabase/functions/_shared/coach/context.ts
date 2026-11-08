/**
 * The student's facts as the model sees them: smaller than coach_context(),
 * and with nothing in it an early year should not read.
 *
 * coach_context() already keeps applications and dates from discover,
 * explore and build. This is the second line behind it, so an old context or
 * a mistake in SQL still cannot put a job hunt in front of a first-year.
 * Redaction is separate (`redactJson`) and runs after this.
 */
import { isEarly, type Mode } from "./actions.ts";
import type { Context } from "./router.ts";

const MAX_HELD = 30;
const MAX_GAP = 10;

/** Every number to at most one decimal place, everywhere in the value. */
function roundNumbers(value: unknown): unknown {
  if (typeof value === "number") {
    return Number.isFinite(value) ? Math.round(value * 10) / 10 : null;
  }
  if (Array.isArray(value)) return value.map(roundNumbers);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([k, v]) => [k, roundNumbers(v)]),
    );
  }
  return value;
}

export function compactContext(
  ctx: Context,
  mode: Mode,
): Record<string, unknown> {
  const { version: _version, ...rest } = ctx;
  const out: Record<string, unknown> = { ...rest };

  if (Array.isArray(ctx.skills_held)) {
    out.skills_held = ctx.skills_held.slice(0, MAX_HELD);
  }
  if (Array.isArray(ctx.skill_gap)) {
    out.skill_gap = ctx.skill_gap.slice(0, MAX_GAP);
  }

  // A part this year does not count is noise the model would talk about.
  const components = ctx.score?.components;
  if (components && typeof components === "object") {
    out.score = {
      ...ctx.score,
      components: Object.fromEntries(
        Object.entries(components).filter(([, c]) => (c?.max ?? 0) > 0),
      ),
    };
  }

  if (isEarly(mode)) {
    delete out.applications;
    if (Array.isArray(ctx.upcoming)) {
      out.upcoming = ctx.upcoming.filter((item) =>
        item?.kind !== "follow_up" && item?.kind !== "closing"
      );
    }
  }

  return roundNumbers(out) as Record<string, unknown>;
}
