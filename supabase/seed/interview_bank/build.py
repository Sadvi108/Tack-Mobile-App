#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Builds the interview pool seed migration from the content files.

Run from the repository root:

    python3 supabase/seed/interview_bank/build.py --check            # validate + compose, print stats
    python3 supabase/seed/interview_bank/build.py --check --strict   # also every role reviewed
    python3 supabase/seed/interview_bank/build.py --out supabase/migrations/0098_interview_pool_seed.sql
    python3 supabase/seed/interview_bank/build.py --verify           # rebuild == newest *_interview_pool_*.sql

Standard library only, Python 3.9+. Contract C4 of
docs/superpowers/plans/2026-11-05-practice-hub-and-smarter-coach.md.

Every content rule lives in validate.py and is imported from there, so a
writer's local check and this build can never disagree. This file adds only
what a migration needs on top: the roles a build cannot ship without, stable
ids, sort orders, the fixed sets old app builds still read, and the checks
the migration runs on itself.
"""
import argparse
import glob
import json
import os
import re
import sys
import uuid

sys.dont_write_bytecode = True  # content files are imported; keep the tree clean
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import companies  # noqa: E402
import validate  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
MIGRATIONS = os.path.join(REPO, "supabase", "migrations")
GENERATED_GLOB = "*_interview_pool_*.sql"

# Fixed for ever: a question's id is uuid5(NAMESPACE, "<role>|<normalised
# text>"), so the same question keeps its id across builds and a student's
# history stays attached to it. Changing this re-keys every question.
NAMESPACE = uuid.UUID("2f6b8c1e-7d4a-4e52-9a1b-5c3d8e0f6a27")

E, M, H = validate.TIERS
MANIFEST = validate.MANIFEST
SESSION_TYPES = ("behavioural", "technical", "mixed")
SET_SIZE = 5
TAGS = ("roles", "aliases", "paths", "pool", "sets", "packs")

# Tenths of a session that are easy and hard; the rest is medium. The same
# shares as interview_slots() in 0096.
SHARES = {E: (6, 0), M: (2, 2), H: (0, 6)}


# ------------------------------------------------------------- composition
def half_up(numerator, denominator):
    """round(numerator / denominator) as Postgres rounds a positive numeric."""
    return (2 * numerator + denominator) // (2 * denominator)


def slots(difficulty, n):
    """interview_slots(): the tiers of an n-question session, easiest first."""
    e10, h10 = SHARES[difficulty]
    n_e, n_h = half_up(n * e10, 10), half_up(n * h10, 10)
    return [E] * n_e + [M] * (n - n_e - n_h) + [H] * n_h


def behavioural_slots(session_type, n):
    """How many of the first slots interview_draw() fills from the behavioural pool."""
    if session_type == "behavioural":
        return n
    if session_type == "technical":
        return 0
    return min(n, max(1, half_up(n * 4, 10)))


def pool_id(role_slug, question):
    key = "%s|%s" % (role_slug or "behavioural", validate.normalise(question))
    return str(uuid.uuid5(NAMESPACE, key))


def pool_item(role_slug, position, entry):
    """One $pool$ row from a content tuple (tier, category, text, points[, source])."""
    tier, category, text, points = entry[:4]
    return {
        "id": pool_id(role_slug, text),
        "role": role_slug,
        "kind": "role" if role_slug else "behavioural",
        "difficulty": tier,
        "category": category,
        "question": text,
        "key_points": list(points),
        "source_url": entry[4] if len(entry) == 5 else None,
        "sort_order": position,
    }


def _rank(tier):
    return validate.TIERS.index(tier)


def _pick(pool, tier, used):
    """The slot's own tier first, then the nearest (easier on a tie), then the
    first written. interview_draw() orders the same way, before freshness."""
    best = None
    for q in pool:
        if q["id"] in used:
            continue
        key = (abs(_rank(q["difficulty"]) - _rank(tier)), _rank(q["difficulty"]), q["sort_order"])
        if best is None or key < best[0]:
            best = (key, q)
    return best[1] if best else None


def compose(role_pool, behavioural_pool, session_type, difficulty, n=SET_SIZE):
    """A fixed set for interview_question_bank, drawn as interview_draw() would
    draw it for a student who has seen nothing, without the chance."""
    b = behavioural_slots(session_type, n)
    used, out = set(), []
    for i, tier in enumerate(slots(difficulty, n)):
        q = _pick(behavioural_pool if i < b else role_pool, tier, used)
        if q is not None:
            used.add(q["id"])
            out.append({"question": q["question"], "category": q["category"],
                        "key_points": q["key_points"], "pool_id": q["id"]})
    return out


# ----------------------------------------------------------------- content
def content_files(content_dir):
    files = sorted(glob.glob(os.path.join(content_dir, "roles_*.py")))
    behavioural = os.path.join(content_dir, validate.BEHAVIOURAL_FILE)
    if os.path.exists(behavioural):
        files.append(behavioural)
    return files


def load_content(files):
    """Roles by slug and the behavioural questions. Run only after validate()."""
    names = {v[0] for v in validate.CLUSTERS.values()}
    roles, behavioural = {}, None
    for path in files:
        base = os.path.basename(path)
        mod = validate.load_module(path)
        if base == validate.BEHAVIOURAL_FILE:
            behavioural = list(mod.QUESTIONS)
        elif base in names:
            for slug, role in mod.ROLES.items():
                if slug in MANIFEST and MANIFEST[slug][0] == mod.CLUSTER:
                    roles[slug] = role
    return roles, behavioural


def catalog_titles():
    """Career path titles by slug, from the same two files validate.py reads."""
    py = validate.read(validate.REPO_FILES["paths_py"])
    titles = dict(re.findall(r'slug="([a-z0-9-]+)",\s*title="([^"]+)"', py))
    sql = validate.read(validate.REPO_FILES["catalog_sql"])
    m = re.search(r"\$catalog\$(.*?)\$catalog\$", sql, re.S)
    if m:
        for item in json.loads(m.group(1)):
            titles.setdefault(item["slug"], item["title"])
    return titles


def _text_role(text, roles):
    """interview_role_from_text()'s exact and alias steps, over these roles."""
    txt = " ".join(text.lower().split())
    slug = validate.slugify(text)
    for s in sorted(roles):
        if s == slug or MANIFEST[s][1].lower() == txt:
            return s
    aliases = sorted((a, s) for s in roles for a in MANIFEST[s][4])
    for a, s in aliases:
        if a == txt:
            return s
    for a, s in aliases:
        if slug and validate.slugify(a) == slug:
            return s
    return None


def resolution_errors(roles, titles=None):
    """0098 checks that each mapped path's title resolves to its role. A path
    title that is another role's name or alias would fail that check on the
    database; say so here instead."""
    titles = catalog_titles() if titles is None else titles
    errors = []
    for s in sorted(roles):
        for path in MANIFEST[s][5]:
            title = titles.get(path)
            if title is None:
                continue  # validate.py reports a path that is not in the catalog
            hit = _text_role(title, roles)
            if hit not in (None, s):
                errors.append("path %s (%r) would resolve to %s, not %s" % (path, title, hit, s))
    return errors


def requirements(roles, has_behavioural, require_all):
    """What a build needs beyond valid content. Returns (errors, warnings)."""
    errors, warnings = [], []
    if not has_behavioural:
        errors.append("%s is missing" % validate.BEHAVIOURAL_FILE)
    for slug in (validate.GENERAL_ROLE,) + validate.LEGACY_ROLES:
        if slug not in roles:
            errors.append("%s must be in every build and is missing" % slug)
    defaults = {m[2]: s for s, m in MANIFEST.items() if m[3]}
    for field in sorted({MANIFEST[s][2] for s in roles}):
        if defaults[field] not in roles:
            errors.append("field %s has roles but its default, %s, is missing"
                          % (field, defaults[field]))
    missing = [s for s in MANIFEST if s not in roles]
    if missing:
        (errors if require_all else warnings).append(
            "roles not in this build: " + ", ".join(missing))
    errors += resolution_errors(roles)
    return errors, warnings


# ------------------------------------------------------------------ render
def field_lines():
    """Each field's 1-based line number in career_fields.txt."""
    out = {}
    for i, line in enumerate(validate.read(validate.REPO_FILES["fields"]).splitlines(), 1):
        if line.strip():
            out[line.split("|")[0].strip()] = i
    return out


def role_sort_orders():
    """Line of the field x 100, then the field default first, then by title.
    Ranked over the whole manifest, so a role keeps its place in every build."""
    lines = field_lines()
    order = {}
    for field in {m[2] for m in MANIFEST.values()}:
        in_field = sorted((s for s, m in MANIFEST.items() if m[2] == field),
                          key=lambda s: (not MANIFEST[s][3], MANIFEST[s][1].casefold(), s))
        for rank, slug in enumerate(in_field):
            order[slug] = lines[field] * 100 + rank
    return order


def compose_build(roles, behavioural):
    order = role_sort_orders()
    slugs = sorted(roles, key=lambda s: (order[s], s))
    role_rows = [{
        "slug": s, "title": MANIFEST[s][1], "cluster": MANIFEST[s][0], "field": MANIFEST[s][2],
        "summary": roles[s]["summary"], "field_default": MANIFEST[s][3], "sort_order": order[s],
    } for s in slugs]
    pools = {s: [pool_item(s, i, q) for i, q in enumerate(roles[s]["questions"], 1)]
             for s in slugs}
    beh = [pool_item(None, i, q) for i, q in enumerate(behavioural, 1)]
    sets = [{"role": s, "session_type": t, "difficulty": d,
             "questions": compose(pools[s], beh, t, d)}
            for s in slugs for t in SESSION_TYPES for d in validate.TIERS]
    return {
        "roles": role_rows,
        "aliases": [{"alias": a, "role": s} for s in slugs for a in MANIFEST[s][4]],
        "paths": [{"path": p, "role": s} for s in slugs for p in MANIFEST[s][5]],
        "pool": [q for s in slugs for q in pools[s]] + beh,
        "sets": sets,
        "packs": [{"slug": k, "about": v} for k, v in companies.ABOUT.items()],
    }


# `set local` lasts only inside a transaction. Run outside one it does nothing,
# 0096's guard then silently skips every update to a seed set, and old app
# builds keep 0069's sets with no error anywhere. This makes that run fail.
SEEDING_GUARD = """
do $$
begin
  if coalesce(current_setting('tack.seeding', true), '') <> 'on' then
    raise exception 'run this inside a transaction: tack.seeding is off, so seed sets would be skipped';
  end if;
end $$;
"""


def _block(tag, items):
    lines = [json.dumps(item, ensure_ascii=False) for item in items]
    body = "[\n" + ",\n".join(lines) + "\n]"
    marker = "$%s$" % tag
    if marker in body:
        raise SystemExit("content contains %s, which would end the SQL string early" % marker)
    return marker + body + marker


def _sql_list(values):
    return ", ".join("'%s'" % v.replace("'", "''") for v in values)


def draw_roles(slugs):
    """Three roles 0098's draw check exercises: the general one, a legacy
    default and the last role in catalog order."""
    picked = [validate.GENERAL_ROLE, "data-analyst"]
    for s in reversed(slugs):
        if s not in picked:
            picked.append(s)
            break
    return picked


def render(data):
    n_roles = len(data["roles"])
    slugs = [r["slug"] for r in data["roles"]]
    missing = [s for s in MANIFEST if s not in slugs]
    v = validate
    required = (v.GENERAL_ROLE,) + v.LEGACY_ROLES
    parts = []
    w = parts.append

    w("-- Generated by supabase/seed/interview_bank/build.py. Do not edit by hand.\n"
      "--\n"
      "-- The interview pool: %d roles with %d hand-written questions each, the\n"
      "-- behavioural pool of %d, and the fixed sets old app builds still read.\n"
      "-- Every question has the key points a strong answer covers, and every role\n"
      "-- was read by a second writer. Content: supabase/seed/interview_bank/\n"
      "-- roles_*.py and behavioural.py. Regenerate with build.py --out and check\n"
      "-- with build.py --verify. 0096 built the tables; this fills them.\n"
      "--\n"
      "-- 0096's trigger keeps model sets off seed rows. This file may change\n"
      "-- them because its first statement turns tack.seeding on, for this\n"
      "-- transaction only.\n"
      % (n_roles, v.QUESTIONS_PER_ROLE, v.BEHAVIOURAL_TOTAL))
    if missing:
        w("--\n-- Not in this build (a later cluster ships them): %s.\n"
          % ", ".join(missing))
    w("\nset local tack.seeding = 'on';\n")
    w(SEEDING_GUARD)

    w("""
-- ------------------------------------------------------------------ roles
create temp table pool_seed_roles on commit drop as
select * from jsonb_to_recordset(%s::jsonb)
  as r(slug text, title text, cluster text, field text, summary text,
       field_default boolean, sort_order int);

-- A field's default may move to another role. Clear them first, so the
-- one-default-per-field index never sees two at once.
update public.interview_roles set is_field_default = false where is_field_default;

insert into public.interview_roles
  (slug, title, cluster, field_slug, summary, is_field_default, sort_order, is_active)
select slug, title, cluster, field, summary, field_default, sort_order, true
  from pool_seed_roles
on conflict (slug) do update set
  title = excluded.title, cluster = excluded.cluster, field_slug = excluded.field_slug,
  summary = excluded.summary, is_field_default = excluded.is_field_default,
  sort_order = excluded.sort_order, is_active = true;

-- A role is retired, never deleted: old sessions still point at it.
update public.interview_roles set is_active = false
 where is_active and slug not in (select slug from pool_seed_roles);

-- ---------------------------------------------------------------- aliases
delete from public.interview_role_aliases;
insert into public.interview_role_aliases (alias, role_slug)
select a.alias, a.role
  from jsonb_to_recordset(%s::jsonb) as a(alias text, role text);

-- ------------------------------------------------------------------ paths
-- Only paths the catalog has and shows; a retired path keeps its field default.
delete from public.interview_role_paths;
insert into public.interview_role_paths (path_slug, role_slug)
select p.path, p.role
  from jsonb_to_recordset(%s::jsonb) as p(path text, role text)
 where exists (select 1 from public.career_paths cp where cp.slug = p.path and cp.is_active);

-- ------------------------------------------------------------------- pool
-- Ids come from the question's text, so an unchanged question keeps its id
-- and a student's history stays attached to it.
create temp table pool_seed_questions on commit drop as
select * from jsonb_to_recordset(%s::jsonb)
  as q(id uuid, role text, kind text, difficulty difficulty_level, category text,
       question text, key_points jsonb, source_url text, sort_order int);

insert into public.interview_pool_questions
  (id, role_slug, kind, difficulty, category, question, key_points, source_url,
   sort_order, is_active)
select id, role, kind, difficulty, category, question, key_points, source_url,
       sort_order, true
  from pool_seed_questions
on conflict (id) do update set
  role_slug = excluded.role_slug, kind = excluded.kind, difficulty = excluded.difficulty,
  category = excluded.category, question = excluded.question,
  key_points = excluded.key_points, source_url = excluded.source_url,
  sort_order = excluded.sort_order, is_active = true;

update public.interview_pool_questions set is_active = false
 where is_active and id not in (select id from pool_seed_questions);

-- ------------------------------------------------------------------- sets
-- The fixed sets old app builds read through the interview function: the
-- same item shape as 0069 plus key_points and pool_id, which they ignore.
insert into public.interview_question_bank (role_slug, session_type, difficulty, questions, source)
select s.role, s.session_type, s.difficulty, s.questions, 'seed'
  from jsonb_to_recordset(%s::jsonb)
    as s(role text, session_type interview_type, difficulty difficulty_level, questions jsonb)
on conflict (role_slug, session_type, difficulty) do update
  set questions = excluded.questions, source = 'seed';

-- ------------------------------------------------------------------ packs
-- What kind of business each is, and nothing Tack cannot check. The
-- questions stay as 0069 seeded them.
update public.company_interview_packs p
   set about = k.about
  from jsonb_to_recordset(%s::jsonb) as k(slug text, about text)
 where p.slug = k.slug;

-- --------------------------------------------------------------- backfill
-- Answers practised before this round get their pool question and key
-- points, matched by exact text within the session's role.
update public.interview_questions q
   set pool_question_id = p.id, key_points = p.key_points
  from public.interview_sessions s, public.interview_pool_questions p
 where s.id = q.session_id
   and q.pool_question_id is null
   and p.is_active
   and p.question = q.question
   and (p.kind = 'behavioural'
        or p.role_slug = coalesce(s.role_slug, public.interview_slug(s.role)));
""" % (_block("roles", data["roles"]), _block("aliases", data["aliases"]),
       _block("paths", data["paths"]), _block("pool", data["pool"]),
       _block("sets", data["sets"]), _block("packs", data["packs"])))

    picks = draw_roles(slugs)
    w("""
-- ---------------------------------------------------------------- checked
do $$
declare
  v_n        int;
  v_bad      text;
  v_row      record;
  v_got      text;
  v_role     text;
  v_type     interview_type;
  v_level    difficulty_level;
  v_size     int;
  v_b        int;
  v_distinct int;
  v_beh      int;
  v_own      int;
  v_ids      uuid[];
  v_want     uuid[];
  v_seen     uuid[];
begin
  -- The roles this build wrote, and the ones every build must have.
  select count(*) into v_n from public.interview_roles where is_active;
  if v_n <> %(n_roles)d then
    raise exception 'expected %(n_roles)d active roles, found %%', v_n;
  end if;
  select string_agg(s, ', ') into v_bad
    from unnest(array[%(required)s]) s
   where not exists (select 1 from public.interview_roles r where r.slug = s and r.is_active);
  if v_bad is not null then
    raise exception 'required roles are not active: %%', v_bad;
  end if;

  -- Each role: %(per_role)d questions, %(per_tier)d per tier, at least 3 categories.
  select string_agg(r.slug, ', ') into v_bad
    from public.interview_roles r
   where r.is_active
     and ((select count(*) from public.interview_pool_questions q
            where q.role_slug = r.slug and q.is_active) <> %(per_role)d
       or exists (select 1 from unnest(enum_range(null::difficulty_level)) d
                   where (select count(*) from public.interview_pool_questions q
                           where q.role_slug = r.slug and q.is_active
                             and q.difficulty = d) <> %(per_tier)d)
       or (select count(distinct q.category) from public.interview_pool_questions q
            where q.role_slug = r.slug and q.is_active) < 3);
  if v_bad is not null then
    raise exception 'roles without a full pool: %%', v_bad;
  end if;

  -- Every question: 2 to 4 key points, each a non-empty string of at most 120.
  select count(*) into v_n
    from public.interview_pool_questions q
   where q.is_active
     and (jsonb_array_length(q.key_points) not between 2 and 4
       or exists (select 1 from jsonb_array_elements(q.key_points) k
                   where jsonb_typeof(k) <> 'string'
                      or length(k #>> '{}') not between 1 and 120));
  if v_n > 0 then
    raise exception '%% questions have key points out of shape', v_n;
  end if;

  -- The behavioural pool: %(beh_total)d, %(beh_tier)d per tier, at least %(hr_min)d in the HR round.
  if (select count(*) from public.interview_pool_questions
       where kind = 'behavioural' and is_active) <> %(beh_total)d
  or exists (select 1 from unnest(enum_range(null::difficulty_level)) d
              where (select count(*) from public.interview_pool_questions q
                      where q.kind = 'behavioural' and q.is_active
                        and q.difficulty = d) <> %(beh_tier)d)
  or (select count(*) from public.interview_pool_questions
       where kind = 'behavioural' and is_active and category = '%(hr)s') < %(hr_min)d then
    raise exception 'the behavioural pool is not %(beh_total)d questions, %(beh_tier)d per tier, with an HR round';
  end if;

  if exists (select 1 from public.interview_pool_questions where is_active
              group by coalesce(role_slug, ''), lower(question) having count(*) > 1) then
    raise exception 'a role asks the same question twice';
  end if;

  -- Every field with a role has exactly one default.
  select string_agg(field_slug, ', ') into v_bad
    from (select r.field_slug
            from public.interview_roles r
           where r.is_active
           group by r.field_slug
          having count(*) filter (where r.is_field_default) <> 1) x;
  if v_bad is not null then
    raise exception 'fields without exactly one default role: %%', v_bad;
  end if;

  if exists (select 1 from public.interview_role_paths rp
               left join public.career_paths cp on cp.slug = rp.path_slug and cp.is_active
               left join public.interview_roles r on r.slug = rp.role_slug and r.is_active
              where cp.slug is null or r.slug is null) then
    raise exception 'a path mapping points at a retired path or role';
  end if;

  -- Old app builds: all 9 sets of every role, each with at least 5 questions.
  select string_agg(r.slug, ', ') into v_bad
    from public.interview_roles r
   where r.is_active
     and (select count(*) from public.interview_question_bank b
           where b.role_slug = r.slug and b.source = 'seed'
             and jsonb_typeof(b.questions) = 'array'
             and jsonb_array_length(b.questions) >= 5
             and not exists (select 1 from jsonb_array_elements(b.questions) i
                              where jsonb_typeof(i->'question') is distinct from 'string')) <> 9;
  if v_bad is not null then
    raise exception 'roles without their 9 seed sets: %%', v_bad;
  end if;

  -- Resolution: a role's title, each alias and each mapped path's title find it.
  for v_row in select slug, title from public.interview_roles where is_active loop
    select f.role_slug into v_got from public.interview_role_from_text(v_row.title) f;
    if v_got is distinct from v_row.slug then
      raise exception 'the title %% resolves to %%, not %%', v_row.title, v_got, v_row.slug;
    end if;
  end loop;
  for v_row in select a.alias, a.role_slug
                 from public.interview_role_aliases a
                 join public.interview_roles r on r.slug = a.role_slug and r.is_active loop
    select f.role_slug into v_got from public.interview_role_from_text(v_row.alias) f;
    if v_got is distinct from v_row.role_slug then
      raise exception 'the alias %% resolves to %%, not %%', v_row.alias, v_got, v_row.role_slug;
    end if;
  end loop;
  for v_row in select cp.title, rp.role_slug
                 from public.interview_role_paths rp
                 join public.career_paths cp on cp.slug = rp.path_slug loop
    select f.role_slug into v_got from public.interview_role_from_text(v_row.title) f;
    if v_got is distinct from v_row.role_slug then
      raise exception 'the path %% resolves to %%, not %%', v_row.title, v_got, v_row.role_slug;
    end if;
  end loop;

  -- The draw: n distinct questions with the right behavioural and role split.
  foreach v_role in array array[%(draw_roles)s] loop
    foreach v_type in array enum_range(null::interview_type) loop
      foreach v_level in array enum_range(null::difficulty_level) loop
        foreach v_size in array array[3, 5, 10] loop
          v_b := case v_type when 'behavioural' then v_size
                             when 'technical' then 0
                             else greatest(1, round(v_size * 0.4)::int) end;
          select count(distinct d.pool_question_id),
                 count(*) filter (where q.kind = 'behavioural' and d.ord <= v_b),
                 count(*) filter (where q.kind = 'role' and q.role_slug = v_role and d.ord > v_b)
            into v_distinct, v_beh, v_own
            from public.interview_draw(v_role, v_type, v_level, v_size) d
            join public.interview_pool_questions q on q.id = d.pool_question_id;
          if v_distinct <> v_size or v_beh <> v_b or v_own <> v_size - v_b then
            raise exception 'interview_draw(%%, %%, %%, %%) gave %% distinct, %% behavioural, %% role',
              v_role, v_type, v_level, v_size, v_distinct, v_beh, v_own;
          end if;
        end loop;
      end loop;
    end loop;
  end loop;

  -- Freshness: with everything else seen, the draw returns exactly the first
  -- easy, the first three medium and the first hard question.
  select array_agg(w.id) into v_want
    from ((select id from public.interview_pool_questions
            where role_slug = '%(fresh)s' and is_active and difficulty = 'easy'
            order by sort_order limit 1)
          union all
          (select id from public.interview_pool_questions
            where role_slug = '%(fresh)s' and is_active and difficulty = 'medium'
            order by sort_order limit 3)
          union all
          (select id from public.interview_pool_questions
            where role_slug = '%(fresh)s' and is_active and difficulty = 'hard'
            order by sort_order limit 1)) w;
  select array_agg(q.id) into v_seen
    from public.interview_pool_questions q
   where q.role_slug = '%(fresh)s' and q.is_active and not (q.id = any(v_want));
  select array_agg(d.pool_question_id) into v_ids
    from public.interview_draw('%(fresh)s', 'technical', 'medium', 5, v_seen) d;
  if coalesce(array_length(v_ids, 1), 0) <> 5 or not (v_ids <@ v_want and v_want <@ v_ids) then
    raise exception 'interview_draw did not prefer unseen questions';
  end if;

  -- Not an error: paths with no role, no mapping and no field default get
  -- general graduate questions, and the app says so.
  select string_agg(cp.slug, ', ' order by cp.slug) into v_bad
    from public.career_paths cp
   where cp.is_active
     and not exists (select 1 from public.interview_role_for_path(cp.slug));
  if v_bad is not null then
    raise warning 'career paths that get general graduate questions: %%', v_bad;
  end if;
end $$;
""" % {
        "n_roles": n_roles,
        "required": _sql_list(required),
        "per_role": v.QUESTIONS_PER_ROLE,
        "per_tier": v.PER_TIER,
        "beh_total": v.BEHAVIOURAL_TOTAL,
        "beh_tier": v.BEHAVIOURAL_PER_TIER,
        "hr": v.HR_ROUND.replace("'", "''"),
        "hr_min": v.HR_ROUND_MIN,
        "draw_roles": _sql_list(picks),
        "fresh": v.GENERAL_ROLE,
    })
    return "".join(parts)


# --------------------------------------------------------------------- cli
def newest_generated(migrations_dir):
    found = sorted(glob.glob(os.path.join(migrations_dir, GENERATED_GLOB)))
    return found[-1] if found else None


def print_report(report):
    for line in report.warnings + report.errors:
        print(line)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="validate and compose, print stats")
    mode.add_argument("--out", metavar="PATH", help="write the seed migration")
    mode.add_argument("--verify", action="store_true",
                      help="the newest generated migration equals a rebuild")
    ap.add_argument("--strict", action="store_true",
                    help="every role reviewed, and every --out requirement met")
    ap.add_argument("--all", action="store_true", help="all 40 roles must be present")
    # For tests: where the content and the migrations live.
    ap.add_argument("--content-dir", default=HERE, help=argparse.SUPPRESS)
    ap.add_argument("--migrations-dir", default=MIGRATIONS, help=argparse.SUPPRESS)
    args = ap.parse_args(argv)

    files = content_files(args.content_dir)
    if args.verify:
        target = newest_generated(args.migrations_dir)
        if target is None:
            print("nothing generated yet")
            return 0
    if not files:
        print("no content yet")
        return 1 if args.out or args.verify else 0

    strict = args.strict or bool(args.out)
    report, _present = validate.validate(files, strict=strict, require_all=args.all)
    roles, behavioural = load_content(files) if not report.errors else ({}, None)
    if not report.errors:
        errors, warnings = requirements(roles, behavioural is not None, args.all)
        hard = args.out or args.strict
        for e in errors:
            (report.errors if hard else report.warnings).append(
                ("ERROR" if hard else "WARN ") + " build: " + e)
        report.warnings.extend("WARN  build: " + x for x in warnings)
    print_report(report)
    if report.errors:
        print("build stopped: %d errors" % len(report.errors))
        return 1

    if behavioural is None:  # --check while the behavioural pool is still being written
        print("roles: %d of %d; behavioural pool not written yet" % (len(roles), len(MANIFEST)))
        return 0
    data = compose_build(roles, behavioural)
    sql = render(data)
    stats = ("roles: %d of %d; role questions: %d; behavioural: %d; sets: %d"
             % (len(data["roles"]), len(MANIFEST),
                sum(1 for q in data["pool"] if q["role"]), len(behavioural), len(data["sets"])))

    if args.check:
        print(stats)
        return 0
    if args.out:
        with open(args.out, "w", encoding="utf-8", newline="\n") as f:
            f.write(sql)
        print("wrote %s; %s" % (args.out, stats))
        return 0
    with open(target, encoding="utf-8") as f:
        current = f.read()
    if current == sql:
        print("%s matches the content; %s" % (os.path.basename(target), stats))
        return 0
    old, new = current.splitlines(), sql.splitlines()
    line = next((i for i, (a, b) in enumerate(zip(old, new), 1) if a != b),
                min(len(old), len(new)) + 1)
    print("drift: %s differs from a rebuild of the content, first at line %d. "
          "Run build.py --out %s." % (os.path.basename(target), line, target))
    return 1


if __name__ == "__main__":
    sys.exit(main())
