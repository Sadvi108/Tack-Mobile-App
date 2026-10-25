// Public Actor identities verified through Apify Store + deployed schemas.
// An arbitrary task/Actor is never trusted as a source of app listings.
export const APIFY_JOB_ACTORS = {
  scrapingmonkey: "fHgKbgS18BmU9mLGL",
  vero: "5rkl00rFGoyw7UclT",
  hipersoft: "NCRg9YAecOBoUmecL",
  multiboard: "GZ7ITdk4Y6BDhNwDj",
} as const;
export const APIFY_JOB_ACTOR_IDS = [
  APIFY_JOB_ACTORS.scrapingmonkey,
  APIFY_JOB_ACTORS.vero,
  APIFY_JOB_ACTORS.hipersoft,
  APIFY_JOB_ACTORS.multiboard,
] as const;
