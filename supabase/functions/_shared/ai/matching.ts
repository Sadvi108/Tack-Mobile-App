/**
 * Deterministic skill matching.
 *
 * A model extracts the skills a job asks for; comparing them against what a
 * student has is a set operation and is done here, in code. Using a model for
 * this would make the same inputs give different answers on different days,
 * which is unacceptable for a number the student is asked to trust.
 */

export interface MatchResult {
  matchPercent: number;
  matched: string[];
  missing: string[];
}

/** Loose equality: "Node.js" and "nodejs" are the same skill to a student. */
function normalise(skill: string): string {
  return skill.toLowerCase().replace(/[^a-z0-9]/g, '');
}

export function matchSkills(
  requiredSkills: string[],
  userSkillNames: string[],
): MatchResult {
  const have = new Set(userSkillNames.map(normalise));
  const matched: string[] = [];
  const missing: string[] = [];
  const seen = new Set<string>();

  for (const skill of requiredSkills) {
    const key = normalise(skill);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    (have.has(key) ? matched : missing).push(skill);
  }

  const total = matched.length + missing.length;
  return {
    matchPercent: total === 0 ? 0 : Math.round((matched.length * 100) / total),
    matched,
    missing,
  };
}
