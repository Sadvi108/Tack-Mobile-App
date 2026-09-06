/**
 * The only place a model is spoken to.
 *
 * Feature code calls `complete()` and never imports a provider SDK. Swapping
 * Gemini for anything else is a change in this file alone, and switching to
 * the mock is an environment variable rather than a code path.
 */

export interface CompletionRequest {
  /** Which prompt template produced this. Recorded against usage. */
  feature: string;
  system: string;
  user: string;
  /** JSON Schema the reply must satisfy. Omitted for a prose reply. */
  schema?: Record<string, unknown>;
  maxOutputTokens?: number;

  /**
   * Prose instead of JSON.
   *
   * Every other feature extracts structure and is validated against a schema
   * before anything is stored — that rule stands. The coach is the one place
   * where the reply *is* the product: a sentence a student reads, with nothing
   * to parse out of it. A schema there would mean asking the model for JSON
   * containing an English paragraph, validating the wrapper, and displaying
   * the paragraph unchecked — the appearance of validation over none.
   *
   * The trade is real and narrow: this reply is not schema-checked, so it is
   * never stored as structured data and never drives a number on screen.
   */
  format?: "json" | "text";

  /** Free-form replies want some warmth; extraction wants none. */
  temperature?: number;

  /**
   * How long the model may deliberate before answering.
   *
   * This model thinks by default and it is slow: a coaching answer took ten to
   * twenty-six seconds, which is unusable in a conversation. "low" brought the
   * same question back in six to eight with no visible loss of quality, and it
   * is set only where a person is waiting on the reply. Extraction runs in the
   * worker where nobody is watching a spinner, so it keeps the default.
   */
  thinking?: "low";
}

export interface CompletionResult {
  data: unknown;
  provider: string;
  model: string;
  promptTokens: number;
  completionTokens: number;
}

export interface LLMProvider {
  readonly name: string;
  complete(request: CompletionRequest): Promise<CompletionResult>;
}

/** Returns fixtures. The default everywhere except a deliberate live test. */
export class MockProvider implements LLMProvider {
  readonly name = "mock";

  // Not async: there is nothing to await, and the interface only asks for a
  // promise.
  complete(request: CompletionRequest): Promise<CompletionResult> {
    if (request.format === "text") {
      return Promise.resolve({
        data:
          "This is a mock reply. Set AI_PROVIDER=gemini to talk to the real model.",
        provider: this.name,
        model: "mock-1",
        promptTokens: Math.ceil(request.user.length / 4),
        completionTokens: 16,
      });
    }

    return Promise.resolve({
      data: mockFixture(request.feature, request.user),
      provider: this.name,
      model: "mock-1",
      promptTokens: Math.ceil(request.user.length / 4),
      completionTokens: 128,
    });
  }
}

export class GeminiProvider implements LLMProvider {
  readonly name = "gemini";

  // A Flash-class model: this workload is extraction and short structured
  // writing, and paying for a larger model would buy nothing a student sees.
  //
  // 2.5-flash was retired for new keys — Google answers 404 with "no longer
  // available to new users". Every AI feature in Tack shares this provider, so
  // that single dead string meant the CV score, the JD analyser, interview
  // practice and the coach would all have failed the moment AI_PROVIDER was
  // switched off mock. Nothing caught it because mock never calls Google.
  private readonly model = "gemini-3.6-flash";

  async complete(request: CompletionRequest): Promise<CompletionResult> {
    const key = Deno.env.get("GEMINI_API_KEY");
    if (!key) throw new Error("GEMINI_API_KEY is not configured");

    const url =
      `https://generativelanguage.googleapis.com/v1beta/models/${this.model}:generateContent`;

    // 429 is normal operation on a free tier, not an incident. Back off and
    // retry rather than failing the student's request.
    const delays = [0, 1000, 4000];
    let lastError: unknown;

    for (const delay of delays) {
      if (delay) await new Promise((r) => setTimeout(r, delay));

      const response = await fetch(url, {
        method: "POST",
        signal: AbortSignal.timeout(45000),
        headers: { "Content-Type": "application/json", "x-goog-api-key": key },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: request.system }] },
          contents: [{ role: "user", parts: [{ text: request.user }] }],
          generationConfig: {
            ...(request.format === "text" ? {} : {
              responseMimeType: "application/json",
              responseSchema: request.schema,
            }),
            // This model thinks before it answers, and those tokens come out
            // of the same budget: a one-word reply spent 111 thinking tokens
            // in testing. Too small a ceiling returns an empty candidate,
            // which surfaces to a student as "the coach could not answer".
            ...(request.thinking
              ? { thinkingConfig: { thinkingLevel: request.thinking } }
              : {}),
            maxOutputTokens: request.maxOutputTokens ?? 2048,
            temperature: request.temperature ?? 0.2,
          },
        }),
      });

      if (response.status === 429 || response.status >= 500) {
        lastError = new Error(`provider returned ${response.status}`);
        continue;
      }
      if (!response.ok) {
        throw new Error(`provider returned ${response.status}`);
      }

      const body = await response.json();
      const text = body?.candidates?.[0]?.content?.parts?.[0]?.text;
      if (!text) throw new Error("provider returned no content");

      return {
        // Prose is returned as it came. Nothing downstream parses it, and
        // JSON.parse on a paragraph would throw on the first apostrophe.
        data: request.format === "text" ? text : JSON.parse(text),
        provider: this.name,
        model: this.model,
        promptTokens: body?.usageMetadata?.promptTokenCount ?? 0,
        completionTokens: body?.usageMetadata?.candidatesTokenCount ?? 0,
      };
    }

    throw lastError ?? new Error("provider unavailable");
  }
}

export function selectProvider(): LLMProvider {
  return Deno.env.get("AI_PROVIDER") === "gemini"
    ? new GeminiProvider()
    : new MockProvider();
}

function mockFixture(feature: string, input: string): unknown {
  switch (feature) {
    case "coach_chat":
      return {
        reply:
          "Choose one skill from your roadmap and practise it in a small project this week.",
      };
    case "analyse_jd":
      return {
        job_title: "Junior frontend developer",
        seniority: "entry",
        skills: ["JavaScript", "React", "CSS", "Git", "REST APIs"],
        qualifications: ["Bachelor's degree in computer science or equivalent"],
        responsibilities: [
          "Build and maintain user-facing features",
          "Work with designers to turn mockups into screens",
        ],
        experience: "0 to 2 years",
      };
    case "parse_cv":
      return {
        headline: "Computer science student",
        summary:
          "Final-year student with two personal projects and one internship.",
        skills: ["Python", "SQL", "Git"],
        education: [{
          degree: "BSc Computer Science",
          institution: "University",
          year: 2027,
        }],
        experience: [{ title: "Intern", organisation: "A company", months: 3 }],
        projects: [{
          title: "A project",
          summary: "Something built for a course.",
        }],
        quality_score: 62,
        warnings: ["No measurable results on any bullet point"],
      };
    case "interview_questions":
      return {
        questions: [
          {
            question: "Tell me about a project you are proud of.",
            category: "behavioural",
          },
          {
            question: "Describe a bug you found difficult to fix.",
            category: "technical",
          },
          {
            question: "How do you decide what to work on first?",
            category: "behavioural",
          },
          {
            question: "What would you like to be better at?",
            category: "behavioural",
          },
          { question: "Why this role?", category: "behavioural" },
        ],
      };
    case "evaluate_answer":
      return {
        score: 6.5,
        went_well: [
          "You gave a specific example rather than a general claim",
          "The situation was easy to follow",
        ],
        to_improve: [
          "Say what the result was — a number if you have one",
          "Shorten the setup and spend longer on what you did",
        ],
        model_answer:
          "Name the situation in one sentence, spend most of the answer on what you " +
          "personally did, and finish with the outcome.",
      };
    default:
      return { echo: input.slice(0, 120) };
  }
}
