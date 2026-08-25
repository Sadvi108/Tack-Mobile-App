/**
 * Strips personal details before anything is sent to a model.
 *
 * This is not best-effort tidying: contact details are extracted locally and
 * the model only ever sees the anonymised remainder. What is pulled out here
 * is returned to the caller so the app can keep it — it goes into the
 * database, never into a prompt.
 */

export interface Redaction {
  text: string;
  found: {
    emails: string[];
    phones: string[];
    urls: string[];
    nationalIds: string[];
  };
}

const EMAIL = /[\w.+-]+@[\w-]+\.[\w.-]+/g;

// Bangladeshi mobiles, written the several ways students actually write them.
const PHONE = /(?:\+?880[\s-]?|0)1[3-9]\d{2}[\s-]?\d{3}[\s-]?\d{3}/g;

// Long digit runs that look like a national ID or birth registration number.
const NATIONAL_ID = /\b\d{10}\b|\b\d{13}\b|\b\d{17}\b/g;

const URL = /https?:\/\/[^\s)]+/g;

export function redact(input: string): Redaction {
  const found = { emails: [] as string[], phones: [] as string[], urls: [] as string[], nationalIds: [] as string[] };

  let text = input.replace(EMAIL, (match) => {
    found.emails.push(match);
    return '[email]';
  });

  text = text.replace(PHONE, (match) => {
    found.phones.push(match);
    return '[phone]';
  });

  text = text.replace(NATIONAL_ID, (match) => {
    found.nationalIds.push(match);
    return '[id]';
  });

  // Portfolio and repository links are kept in a structured field rather than
  // sent as free text.
  text = text.replace(URL, (match) => {
    found.urls.push(match);
    return '[link]';
  });

  return { text, found };
}

/** Throws if anything that looks personal survived redaction. */
export function assertClean(text: string): void {
  for (const [name, pattern] of [
    ['an email address', EMAIL],
    ['a phone number', PHONE],
    ['a national ID', NATIONAL_ID],
  ] as const) {
    pattern.lastIndex = 0;
    if (pattern.test(text)) {
      throw new Error(`refusing to send text still containing ${name}`);
    }
  }
}
