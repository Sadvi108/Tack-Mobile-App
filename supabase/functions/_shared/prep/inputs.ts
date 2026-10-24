/**
 * What an interview prep brief is built from, and nothing more.
 *
 * The role, the posting, and the student's own skills and projects. Read from
 * the student's rows by the endpoint (to find a cached brief) and again by the
 * worker (so the brief reflects the latest profile). The gateway redacts the
 * prompt before it leaves; nothing here holds a name, email or phone number to
 * begin with.
 */
import { SupabaseClient } from "@supabase/supabase-js";
import { hashText } from "../ai/gateway.ts";

export interface PrepInputs {
  role: string;
  company: string;
  description: string | null;
  requirements: {
    skills: string[];
    responsibilities: string[];
    qualifications: string[];
  } | null;
  skills: string[];
  projects: { title: string; summary: string | null }[];
}

const strings = (value: unknown, max: number): string[] =>
  Array.isArray(value)
    ? value.filter((v): v is string => typeof v === "string").slice(0, max)
    : [];

/** Null when the application is not the student's, or not at interview. */
export async function loadPrepInputs(
  service: SupabaseClient,
  userId: string,
  applicationId: string,
): Promise<PrepInputs | null> {
  const { data: app } = await service.from("job_applications")
    .select("status, jobs(title, company_name, description)")
    .eq("id", applicationId).eq("user_id", userId).is("deleted_at", null)
    .maybeSingle();
  if (!app || app.status !== "interview") return null;

  const job = (Array.isArray(app.jobs) ? app.jobs[0] : app.jobs) as {
    title?: string;
    company_name?: string | null;
    description?: string | null;
  } | null;
  const description = job?.description?.trim() || null;

  let requirements: PrepInputs["requirements"] = null;
  if (description) {
    // The analysis is keyed by the text's hash, so a description checked by
    // anyone is used here without being linked to this job.
    const { data: analysis } = await service.from("job_analyses")
      .select("extracted").eq("raw_text_hash", await hashText(description))
      .maybeSingle();
    const extracted = analysis?.extracted as Record<string, unknown> | null;
    if (extracted) {
      requirements = {
        skills: strings(extracted.skills, 30),
        responsibilities: strings(extracted.responsibilities, 15),
        qualifications: strings(extracted.qualifications, 15),
      };
    }
  }

  const { data: skillRows } = await service.from("user_skills")
    .select("skills(name)").eq("user_id", userId);
  const skills = [
    ...new Set(
      (skillRows ?? []).flatMap((row) => {
        const s = row.skills as { name?: string } | { name?: string }[] | null;
        const list = Array.isArray(s) ? s : s ? [s] : [];
        return list.map((x) => x.name).filter((n): n is string => !!n);
      }),
    ),
  ].sort();

  const { data: projectRows } = await service.from("projects")
    .select("title, summary").eq("user_id", userId).is("deleted_at", null)
    .order("created_at").limit(8);

  return {
    role: job?.title ?? "This role",
    company: job?.company_name ?? "",
    description: description ? description.slice(0, 6000) : null,
    requirements,
    skills,
    projects: (projectRows ?? []).map((p) => ({
      title: String(p.title),
      summary: p.summary ? String(p.summary).slice(0, 400) : null,
    })),
  };
}

export function prepPrompt(i: PrepInputs): string {
  const lines = [
    `Role: ${i.role}`,
    `Company: ${i.company || "Not given"}`,
    `Job description: ${i.description ?? "Not given"}`,
  ];
  if (i.requirements) {
    lines.push(
      `Required skills: ${i.requirements.skills.join(", ") || "None listed"}`,
      `Responsibilities: ${
        i.requirements.responsibilities.join("; ") || "None listed"
      }`,
      `Qualifications: ${
        i.requirements.qualifications.join("; ") || "None listed"
      }`,
    );
  }
  lines.push(`Your skills: ${i.skills.join(", ") || "None listed"}`);
  lines.push("Your projects:");
  if (i.projects.length === 0) lines.push("- None listed");
  for (const p of i.projects) {
    lines.push(`- ${p.title}${p.summary ? `: ${p.summary}` : ""}`);
  }
  return lines.join("\n");
}

/** The same inputs always make the same brief, and are never paid for twice. */
export function prepHash(i: PrepInputs): Promise<string> {
  return hashText(JSON.stringify(i));
}
