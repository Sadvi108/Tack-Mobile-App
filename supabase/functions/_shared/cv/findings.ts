/**
 * Turning the measurements into things a student can do something about.
 *
 * `metrics.ts` counts; this decides what the counting means. Both are pure
 * functions of the text, which is the point: every finding here is produced
 * without a model, so a CV check costs nothing and can be run as often as a
 * student likes. The model is reserved for the one thing counting cannot do —
 * reading the prose and recognising a skill the taxonomy has never heard of.
 *
 * Written as findings rather than a score. A number tells a student they are
 * at 6 out of 10 and leaves them there; "nine bullet points, one of them has a
 * number in it" tells them what to open the file and change.
 */
import type { CvMetrics } from "./metrics.ts";

export type Severity = "problem" | "improve" | "good";

export interface Finding {
  kind: string;
  severity: Severity;
  title: string;
  detail: string;
}

/** Sections a student's CV is expected to carry. */
const EXPECTED = ["education", "experience", "projects", "skills"];

const SECTION_NAMES: Record<string, string> = {
  contact: "Contact details",
  summary: "Summary",
  education: "Education",
  experience: "Experience",
  projects: "Projects",
  skills: "Skills",
  certifications: "Certifications",
  activities: "Activities",
};

export function findings(
  metrics: CvMetrics,
  skillsRecognised: string[],
): Finding[] {
  const out: Finding[] = [];
  const has = (section: string) => metrics.sections.includes(section);

  // --------------------------------------------------------------- blocking
  //
  // Things that will cost an interview on their own, in the order a reader
  // notices them.

  if (metrics.placeholder_hits > 0) {
    out.push({
      kind: "placeholder",
      severity: "problem",
      title: "Template text is still in it",
      detail:
        "Something like “Lorem ipsum” or “Your Name Here” is still on the " +
        "page. It is the first thing a reader notices and the fastest way to " +
        "the reject pile.",
    });
  }

  if (!metrics.has_contact) {
    out.push({
      kind: "contact",
      severity: "problem",
      title: "No way to contact you",
      detail:
        "Tack could not find an email or a phone number. Put both at the top, " +
        "on one line.",
    });
  }

  const missing = EXPECTED.filter((s) => !has(s));
  if (missing.includes("experience") && missing.includes("projects")) {
    out.push({
      kind: "no-evidence",
      severity: "problem",
      title: "Nothing showing what you have done",
      detail:
        "There is no Experience and no Projects section. With no job yet, " +
        "projects are what you have — two you built yourself are worth more " +
        "than a list of courses.",
    });
  }

  for (const section of missing) {
    if (section === "experience" || section === "projects") continue;
    out.push({
      kind: `missing-${section}`,
      severity: "improve",
      title: `No ${SECTION_NAMES[section] ?? section} section`,
      detail: section === "skills"
        ? "Employers scan for this first, and so does software. A short list " +
          "of what you can actually do is enough."
        : "A reader expects to find this and will look for it.",
    });
  }

  // ------------------------------------------------------------ the bullets
  //
  // The single most useful thing this check says. Students write duties;
  // employers read results.

  if (metrics.bullets > 0) {
    const quantified = metrics.bullets_quantified;
    if (quantified === 0) {
      out.push({
        kind: "no-numbers",
        severity: "improve",
        title: `${metrics.bullets} bullet points, none with a number in`,
        detail:
          "“Improved the checkout page” is a claim. “Cut checkout time from " +
          "6s to 2s” is evidence. Put a number on two or three of them — how " +
          "many, how much faster, how many people used it.",
      });
    } else if (quantified * 3 < metrics.bullets) {
      out.push({
        kind: "few-numbers",
        severity: "improve",
        title:
          `${quantified} of ${metrics.bullets} bullet points have a number in`,
        detail:
          "The ones with numbers are the ones a reader believes. See how many " +
          "more you can put a figure on.",
      });
    } else {
      out.push({
        kind: "numbers",
        severity: "good",
        title: `${quantified} of ${metrics.bullets} bullets carry a number`,
        detail: "That is what makes a claim believable. Keep doing it.",
      });
    }

    if (metrics.bullets_action_led * 2 < metrics.bullets) {
      out.push({
        kind: "weak-openers",
        severity: "improve",
        title: "Most bullets do not open with what you did",
        detail:
          "Start each with a verb — built, measured, ran, fixed. “Responsible " +
          "for the website” says less than “Rebuilt the website”.",
      });
    }
  }

  // ---------------------------------------------------------------- dates
  if (metrics.undated_entries > 0) {
    out.push({
      kind: "undated",
      severity: "improve",
      title: metrics.undated_entries === 1
        ? "One entry has no dates"
        : `${metrics.undated_entries} entries have no dates`,
      detail:
        "A reader cannot tell whether this was last month or three years ago, " +
        "and assumes the worse of the two. Month and year is enough.",
    });
  }

  // ---------------------------------------------------------------- length
  if (metrics.pages > 2) {
    out.push({
      kind: "too-long",
      severity: "improve",
      title: `${metrics.pages} pages`,
      detail:
        "For a student, one page is normal and two is the limit. Anything a " +
        "reader will not reach is not doing any work.",
    });
  } else if (metrics.words > 0 && metrics.words < 180) {
    out.push({
      kind: "too-thin",
      severity: "improve",
      title: "There is not much on the page",
      detail: `About ${metrics.words} words. Add what you actually did in ` +
        "your projects and coursework — one line each is enough.",
    });
  }

  // ---------------------------------------------------------------- skills
  if (skillsRecognised.length === 0) {
    out.push({
      kind: "no-skills-found",
      severity: "improve",
      title: "Tack did not recognise any skills in this",
      detail: "Name the tools and languages plainly — “Python”, “Excel”, " +
        "“Figma”. Employers' software searches for the words, not for what " +
        "you meant.",
    });
  } else {
    out.push({
      kind: "skills-found",
      severity: "good",
      title: `Tack recognised ${skillsRecognised.length} ` +
        `${skillsRecognised.length === 1 ? "skill" : "skills"} in this`,
      detail: skillsRecognised.slice(0, 12).join(", ") +
        (skillsRecognised.length > 12 ? ", and more" : ""),
    });
  }

  // -------------------------------------------------------------- how we read
  //
  // Said plainly, because a photograph read badly produces findings that look
  // like criticism of the CV rather than of the photograph.
  if (metrics.ocr_confidence !== null && metrics.ocr_confidence < 80) {
    out.push({
      kind: "poor-scan",
      severity: "improve",
      title: "This was read from a photograph, and not clearly",
      detail:
        "Some of the findings above may be wrong because of that. A PDF " +
        "gives a much better result — and is what you should be sending " +
        "anyway.",
    });
  }

  if (metrics.truncated) {
    out.push({
      kind: "truncated",
      severity: "improve",
      title: "Tack only read the beginning",
      detail: "The file was long enough that the rest was not checked.",
    });
  }

  return out;
}

/** Problems first, then improvements, then what is already working. */
export function sortFindings(list: Finding[]): Finding[] {
  const rank: Record<Severity, number> = { problem: 0, improve: 1, good: 2 };
  return [...list].sort((a, b) => rank[a.severity] - rank[b.severity]);
}
