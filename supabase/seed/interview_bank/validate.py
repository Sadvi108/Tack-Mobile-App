#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Checks Tack interview pool content. Standard library only, Python 3.9+.

Run from the repository root:

    python3 supabase/seed/interview_bank/validate.py --manifest
    python3 supabase/seed/interview_bank/validate.py supabase/seed/interview_bank/roles_rmg.py
    python3 supabase/seed/interview_bank/validate.py --strict supabase/seed/interview_bank/roles_rmg.py
    python3 supabase/seed/interview_bank/validate.py --strict --all \
        supabase/seed/interview_bank/roles_*.py supabase/seed/interview_bank/behavioural.py

Errors fail (exit 1). Warnings never fail.

Plan: docs/superpowers/plans/2026-11-05-practice-hub-and-smarter-coach.md,
contract C1. Committed before the workstreams branched; owned by W3 from then
on. build.py imports this module, so what a writer sees locally is exactly what
the generator enforces. Writers run it and never edit it.
"""
import argparse
import ast
import datetime
import importlib.util
import os
import re
import sys

E, M, H = "easy", "medium", "hard"
TIERS = (E, M, H)

# ----------------------------------------------------------------- manifest
# slug: (cluster, title, field, field_default, aliases, paths)
# Owned by W3. Writers never change it: they write content only (contract C1).
MANIFEST = {
    # software, data and telecom (W2)
    "software-engineer": ("software", "Software engineer", "computer-science", True,
        ["software developer", "junior software engineer", "sde", "programmer"], []),
    "frontend-developer": ("software", "Frontend developer", "computer-science", False,
        ["front end developer", "front-end developer", "web developer", "react developer"], []),
    "backend-developer": ("software", "Backend developer", "computer-science", False,
        ["back end developer", "back-end developer", "api developer"], ["database-developer"]),
    "full-stack-developer": ("software", "Full stack developer", "computer-science", False,
        ["fullstack developer", "mern developer"], []),
    "mobile-app-developer": ("software", "Mobile app developer", "computer-science", False,
        ["android developer", "ios developer", "flutter developer", "app developer"], []),
    "qa-engineer": ("software", "QA engineer", "computer-science", False,
        ["sqa engineer", "sqa", "software tester", "test engineer"], []),
    "data-analyst": ("software", "Data analyst", "statistics", True,
        ["junior data analyst", "mis executive", "reporting analyst"],
        ["operations-research-analyst", "gis-analyst", "health-informatics-analyst",
         "bioinformatics-analyst", "machine-learning-engineer", "quantitative-analyst",
         "actuarial-analyst"]),
    "it-support-specialist": ("software", "IT support specialist", "computer-science", False,
        ["it support", "it officer", "it executive", "help desk", "desktop support"], []),
    "network-engineer": ("software", "Network engineer", "computer-science", False,
        ["network administrator", "noc engineer", "isp engineer"], ["cybersecurity-analyst"]),
    "telecommunications-engineer": ("software", "Telecommunications engineer",
        "electrical-engineering", False, ["telecom engineer", "rf engineer", "ran engineer"], []),
    # engineering (W1)
    "civil-site-engineer": ("engineering", "Civil site engineer", "civil-engineering", True,
        ["civil engineer", "site engineer", "junior civil engineer"], ["bim-modeller"]),
    "electrical-engineer": ("engineering", "Electrical engineer", "electrical-engineering", True,
        ["eee engineer", "power engineer", "substation engineer", "electrical engineer power"],
        ["instrumentation-associate"]),
    "mechanical-engineer": ("engineering", "Mechanical engineer", "mechanical-engineering", True,
        ["maintenance engineer", "mechanical maintenance engineer", "hvac engineer"],
        ["marine-engineering", "naval-design-assistant", "aircraft-maintenance-career"]),
    # RMG and textiles (W2)
    "apparel-merchandiser": ("rmg", "Apparel merchandiser", "textile", True,
        ["merchandiser", "garments merchandiser", "junior merchandiser"], []),
    "industrial-engineer": ("rmg", "Industrial engineer", "engineering", True,
        ["ie executive", "ie officer", "rmg industrial engineer"], []),
    "textile-production-associate": ("rmg", "Textile production associate", "textile", False,
        ["production officer", "dyeing officer", "knitting officer", "textile engineer"], []),
    "textile-quality-inspector": ("rmg", "Textile quality inspector", "textile", False,
        ["quality inspector", "qc inspector", "quality controller"], []),
    # business, finance and banking (W1)
    "management-trainee": ("business", "Management trainee", "business", True,
        ["mt", "mto", "management trainee officer", "graduate trainee"], []),
    "banking-officer": ("business", "Banking officer", "banking", True,
        ["bank officer", "junior officer", "probationary officer", "trainee officer",
         "cash officer"], []),
    "credit-analyst": ("business", "Credit analyst", "banking", False,
        ["credit officer", "sme credit officer", "loan officer"], []),
    "accountant": ("business", "Accountant", "accounting", True,
        ["junior accountant", "accounts officer", "accounts executive"], []),
    "audit-associate": ("business", "Audit associate", "accounting", False,
        ["audit assistant", "article student", "internal auditor", "audit officer"], []),
    "business-analyst": ("business", "Business analyst", "business", False,
        ["ba", "junior business analyst"], ["airline-commercial-analyst"]),
    "supply-chain-analyst": ("business", "Supply chain analyst", "business", False,
        ["supply chain executive", "scm executive", "procurement executive",
         "logistics executive"], ["procurement-associate", "port-operations-associate"]),
    "operations-executive": ("business", "Operations executive", "business", False,
        ["operations officer", "operations associate"],
        ["project-coordinator", "hotel-operations-associate", "travel-operations-executive",
         "event-coordinator", "airport-operations-associate", "patient-services-coordinator",
         "clinical-research-coordinator"]),
    "hr-executive": ("business", "HR executive", "business", False,
        ["hr officer", "human resources executive", "hr and admin executive", "hr assistant"],
        ["people-research-analyst"]),
    "sales-executive": ("business", "Sales executive", "business", False,
        ["sales officer", "territory officer", "territory sales officer",
         "business development executive"], []),
    "digital-marketer": ("business", "Digital marketer", "marketing", True,
        ["digital marketing executive", "social media executive", "marketing executive"], []),
    "brand-executive": ("business", "Brand executive", "marketing", False,
        ["brand officer", "assistant brand manager"], ["public-relations-executive"]),
    "market-research-analyst": ("business", "Market research analyst", "economics", True,
        ["research analyst", "market research executive"],
        ["agribusiness-analyst", "trade-research-analyst"]),
    # pharma and development (W1)
    "pharmaceutical-quality-analyst": ("pharma_development", "Pharmaceutical quality analyst",
        "pharmacy", True, ["qc officer", "qa officer", "quality control officer", "pharma qc"],
        ["laboratory-quality-associate", "biotechnology-research-assistant",
         "chemical-laboratory-analyst", "chemical-quality-associate", "food-quality-associate"]),
    "medical-promotion-officer": ("pharma_development", "Medical promotion officer", "pharmacy",
        False, ["mpo", "medical representative", "medical rep"], []),
    "development-programme-associate": ("pharma_development", "Development programme associate",
        "development", True, ["programme officer", "program officer", "project officer",
                              "ngo officer"],
        ["social-research-assistant", "community-programme-officer",
         "international-programme-associate", "community-health-coordinator",
         "agriculture-extension-assistant"]),
    "monitoring-and-evaluation-assistant": ("pharma_development",
        "Monitoring and evaluation assistant", "development", False,
        ["m&e officer", "m and e officer", "monitoring officer"],
        ["research-and-evaluation-officer"]),
    # creative, teaching, public service and law (W2)
    "graphic-designer": ("creative_public", "Graphic designer", "design", True,
        ["junior graphic designer", "visualiser", "visualizer"], ["fine-artist"]),
    "ui-and-ux-designer": ("creative_public", "UI and UX designer", "design", False,
        ["ui ux designer", "ui/ux designer", "ux designer", "ui designer"], ["product-designer"]),
    "content-writer": ("creative_public", "Content writer", "media", True,
        ["copywriter", "content creator", "content executive"],
        ["translator", "editor-and-proofreader"]),
    "school-teacher": ("creative_public", "School teacher", "education", True,
        ["teacher", "assistant teacher", "english teacher", "maths teacher"],
        ["language-teaching", "physical-education-teaching", "islamic-studies-teaching"]),
    "civil-service-officer": ("creative_public", "Civil service officer", "public-admin", True,
        ["bcs", "bcs cadre", "bcs viva", "government officer", "civil servant"], []),
    "legal-associate": ("creative_public", "Legal associate", "law", True,
        ["legal officer", "junior lawyer", "law officer", "legal assistant"], []),
}

# cluster id -> (file name, author, second reader)
CLUSTERS = {
    "business": ("roles_business.py", "W1", "W2"),
    "pharma_development": ("roles_pharma_development.py", "W1", "W2"),
    "engineering": ("roles_engineering.py", "W1", "W2"),
    "rmg": ("roles_rmg.py", "W2", "W1"),
    "creative_public": ("roles_creative_public.py", "W2", "W1"),
    "software": ("roles_software.py", "W2", "W1"),
}
BEHAVIOURAL_FILE = "behavioural.py"

LEGACY_ROLES = ("frontend-developer", "backend-developer", "data-analyst", "digital-marketer",
                "hr-executive", "business-analyst", "graphic-designer", "qa-engineer",
                "accountant", "content-writer")
GENERAL_ROLE = "management-trainee"

QUESTIONS_PER_ROLE = 15
PER_TIER = 5
BEHAVIOURAL_TOTAL = 24
BEHAVIOURAL_PER_TIER = 8
HR_ROUND = "HR round"
HR_ROUND_MIN = 4

# ----------------------------------------------------------------- rules
SLUG_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
CATEGORY_RE = re.compile(r"^[A-Z0-9][A-Za-z0-9 +&/'-]{1,29}$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
CAPITALISED_WORD = re.compile(r"^[A-Z][a-z]+$")
PROPER_NOUNS = {
    "Bangladesh", "Bangladeshi", "Bangla", "Bengali", "English", "Dhaka", "Chattogram",
    "Chittagong", "Sylhet", "Khulna", "Rajshahi", "Gazipur", "Narayanganj", "Eid", "Ramadan",
    "Boishakh", "Pohela", "Islamic", "Shariah", "React", "Flutter", "Kotlin", "Swift", "Java",
    "Python", "Excel", "Git", "Linux", "Windows", "Android", "Figma", "Facebook", "Google",
    "Tally", "Power", "Docker", "Laravel", "Django", "Node", "Postgres", "Rana", "Plaza",
    "Bank", "Act", "Code", "Commission", "Bureau", "Authority",
}
RULE_WORDS = re.compile(
    r"\b(bangladesh bank|bfiu|nbr|vat|mushak|income tax|finance act|tax return|withholding|"
    r"tds|vds|dgda|drugs and cosmetics act|bcs|bpsc|labou?r act|labou?r law|bnbc|"
    r"building code|rajuk|btrc|ppr|e-gp|ntrca|ngo affairs bureau|mra|bsec|crr|slr|"
    r"companies act)\b", re.I)
BANNED = re.compile(
    r"\b(politic\w*|religio\w*|prime minister|election\w*|married|marriage|spouse|husband|"
    r"wife|pregnan\w*|caste|your age|how old|current affairs)\b", re.I)
EMPLOYERS = re.compile(
    r"\b(bkash|nagad|rocket|grameenphone|robi|banglalink|teletalk|pathao|shohoz|brac|"
    r"square pharmaceuticals|square group|beximco|walton|pran|unilever|nestle|"
    r"dutch[- ]bangla|city bank|eastern bank|prime bank|islami bank|sonali bank|janata bank|"
    r"agrani bank|incepta|renata|akij|bashundhara|meghna group|ha-meem|epyllion|"
    r"summit|daraz|chaldal|foodpanda)\b", re.I)
PERCENT = re.compile(r"\d\s*%|\d\s*percent", re.I)
SOURCE_HOSTS = {
    "bb.org.bd", "www.bb.org.bd", "bfiu.org.bd", "www.bfiu.org.bd", "icab.org.bd",
    "www.icab.org.bd", "icmab.org.bd", "www.icmab.org.bd", "bgmea.com.bd",
    "www.bgmea.com.bd", "www.bkmea.com", "bkmea.com", "www.ilo.org", "ilo.org",
    "www.who.int", "who.int", "www.ich.org", "ich.org", "www.ifrs.org", "ifrs.org",
    "www.tbsnews.net", "tbsnews.net", "thefinancialexpress.com.bd",
    "today.thefinancialexpress.com.bd", "www.thedailystar.net",
}

REPO_FILES = {
    "fields": "supabase/seed/career_fields.txt",
    "paths_py": "supabase/seed/career_paths.py",
    "catalog_sql": "supabase/migrations/0075_expand_career_catalog.sql",
    "legacy": ["supabase/seed/interview_bank/legacy_0069.py", "supabase/seed/interview_bank.py"],
}


def slugify(text):
    return re.sub(r"[^a-z0-9]+", "-", (text or "").strip().lower()).strip("-")


def normalise(text):
    return re.sub(r"\s+", " ", text.strip().lower())


class Report:
    def __init__(self):
        self.errors, self.warnings = [], []

    def error(self, where, msg):
        self.errors.append("ERROR %s: %s" % (where, msg))

    def warn(self, where, msg):
        self.warnings.append("WARN  %s: %s" % (where, msg))


# ----------------------------------------------------------------- repo data
def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def load_fields():
    out = []
    for line in read(REPO_FILES["fields"]).splitlines():
        if line.strip():
            out.append(line.split("|")[0].strip())
    return out


def load_catalog_slugs():
    slugs = set(re.findall(r'slug="([a-z0-9-]+)"', read(REPO_FILES["paths_py"])))
    sql = read(REPO_FILES["catalog_sql"])
    m = re.search(r"\$catalog\$(.*?)\$catalog\$", sql, re.S)
    if m:
        slugs |= set(re.findall(r'"slug": "([a-z0-9-]+)"', m.group(1)))
    return slugs


def load_legacy():
    """Runs only the E/M/H, BEHAVIOURAL and TECHNICAL assignments of the legacy file."""
    wanted = {"E", "M", "H", "BEHAVIOURAL", "TECHNICAL"}

    def names(target):
        return [e.id for e in getattr(target, "elts", [target]) if isinstance(e, ast.Name)]

    for path in REPO_FILES["legacy"]:
        if os.path.exists(path):
            tree = ast.parse(read(path))
            keep = [n for n in tree.body if isinstance(n, ast.Assign)
                    and any(set(names(t)) & wanted for t in n.targets)]
            ns = {}
            exec(compile(ast.Module(body=keep, type_ignores=[]), path, "exec"), ns)
            return ns["TECHNICAL"], ns["BEHAVIOURAL"]
    raise SystemExit("legacy question file not found; run from the repository root")


def load_module(path):
    name = "tack_pool_" + re.sub(r"\W", "_", os.path.abspath(path))
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ----------------------------------------------------------------- checks
def sentence_case(text, where, report, level="error"):
    """Only the first word of each sentence may be capitalised, unless it is a name."""
    for sentence in re.split(r"(?<=[.?!:])\s+", text):
        words = re.findall(r"[A-Za-z][A-Za-z'&/-]*", sentence)
        for w in words[1:]:
            if CAPITALISED_WORD.match(w) and w not in PROPER_NOUNS:
                getattr(report, level)(where, "'%s' should be lowercase (sentence case)" % w)


def check_manifest(report, fields=None, catalog=None):
    fields = fields if fields is not None else load_fields()
    catalog = catalog if catalog is not None else load_catalog_slugs()
    if len(MANIFEST) != 40:
        report.error("manifest", "expected 40 roles, found %d" % len(MANIFEST))
    seen_alias, seen_path, defaults = {}, {}, {}
    titles = {slugify(v[1]) for v in MANIFEST.values()}
    for slug, (cluster, title, field, is_default, aliases, paths) in MANIFEST.items():
        w = "manifest:" + slug
        if cluster not in CLUSTERS:
            report.error(w, "unknown cluster " + cluster)
        if not SLUG_RE.match(slug) or slugify(title) != slug:
            report.error(w, "slug must equal slugify(title)")
        sentence_case(title, w, report)
        if field not in fields or field == "undecided":
            report.error(w, "field %s is not in career_fields.txt" % field)
        if is_default:
            if field in defaults:
                report.error(w, "second default for field %s (%s)" % (field, defaults[field]))
            defaults[field] = slug
        for a in aliases:
            if a != a.strip().lower() or not 2 <= len(a) <= 60:
                report.error(w, "alias '%s' must be lowercase, trimmed, 2-60 chars" % a)
            if a in seen_alias:
                report.error(w, "alias '%s' also used by %s" % (a, seen_alias[a]))
            if a in MANIFEST or slugify(a) in titles:
                report.error(w, "alias '%s' equals a role slug or title" % a)
            seen_alias[a] = slug
        for p in paths:
            if p not in catalog:
                report.error(w, "path %s is not a career_paths slug" % p)
            if p in MANIFEST:
                report.error(w, "path %s is itself a role slug" % p)
            if p in seen_path:
                report.error(w, "path %s also claimed by %s" % (p, seen_path[p]))
            seen_path[p] = slug
    for field in {v[2] for v in MANIFEST.values()}:
        if field not in defaults:
            report.error("manifest", "field %s has roles but no default" % field)
    for legacy in LEGACY_ROLES + (GENERAL_ROLE,):
        if legacy not in MANIFEST:
            report.error("manifest", "missing required role " + legacy)


def check_source(src, where, report):
    m = re.match(r"^https://([^/\s]+)(/\S*)?$", src or "")
    if not m:
        report.error(where, "source must be an https URL")
        return
    host = m.group(1).lower()
    if not (host.endswith(".gov.bd") or host in SOURCE_HOSTS):
        report.error(where, "source host %s is not on the allowed list" % host)


def check_question(item, where, report, seen):
    if not isinstance(item, tuple) or len(item) not in (4, 5):
        report.error(where, "each question is (tier, category, text, key_points[, source])")
        return None
    tier, category, text, points = item[:4]
    source = item[4] if len(item) == 5 else None
    if tier not in TIERS:
        report.error(where, "tier must be E, M or H")
    if not isinstance(category, str) or not CATEGORY_RE.match(category):
        report.error(where, "category %r: sentence case, 2-30 chars, letters/digits/space/+&/'-"
                     % (category,))
    else:
        sentence_case(category, where, report)
    if not isinstance(text, str) or text != text.strip() or not 12 <= len(text) <= 240:
        report.error(where, "question must be a trimmed string of 12-240 chars")
        return None
    if not text.endswith(("?", ".")):
        report.error(where, "question must end with ? or .")
    if "  " in text:
        report.error(where, "double space in question")
    sentence_case(text, where, report, "warn")
    key = normalise(text)
    if key in seen:
        report.error(where, "duplicate question in this role")
    seen.add(key)
    if not isinstance(points, list) or not 2 <= len(points) <= 4:
        report.error(where, "key_points must be a list of 2-4 strings")
        points = points if isinstance(points, list) else []
    norm_points = set()
    for p in points:
        if not isinstance(p, str) or p != p.strip() or not 8 <= len(p) <= 120:
            report.error(where, "key point must be a trimmed string of 8-120 chars: %r" % (p,))
            continue
        if p.endswith("."):
            report.error(where, "key point must not end with a full stop: %r" % p)
        if not p[0].isupper() and not p[0].isdigit():
            report.error(where, "key point must start with a capital letter: %r" % p)
        if normalise(p) in norm_points:
            report.error(where, "duplicate key point")
        norm_points.add(normalise(p))
    blob = " ".join([text] + [p for p in points if isinstance(p, str)])
    if BANNED.search(blob):
        report.error(where, "off-limits topic (politics, religion, current affairs or "
                            "personal life): '%s'" % BANNED.search(blob).group(0))
    if EMPLOYERS.search(blob):
        report.error(where, "names an employer: '%s'" % EMPLOYERS.search(blob).group(0))
    if PERCENT.search(blob):
        report.error(where, "a percentage or rate; ask how the rule works, not the number")
    if RULE_WORDS.search(blob) and source is None:
        report.error(where, "mentions '%s', so it needs a source URL as the 5th element"
                     % RULE_WORDS.search(blob).group(0))
    if source is not None:
        check_source(source, where, report)
    return tier, category, text


def check_reviewed(value, where, report, strict):
    if value is None:
        if strict:
            report.error(where, "reviewed_on is required (the second reader signs off)")
        return
    if not isinstance(value, str) or not DATE_RE.match(value):
        report.error(where, "reviewed_on must be None or 'YYYY-MM-DD'")
        return
    try:
        datetime.date.fromisoformat(value)
    except ValueError:
        report.error(where, "reviewed_on is not a real date")


def check_role_file(path, report, strict, legacy_technical, all_questions):
    base = os.path.basename(path)
    mod = load_module(path)
    cluster = getattr(mod, "CLUSTER", None)
    roles = getattr(mod, "ROLES", None)
    if cluster not in CLUSTERS or CLUSTERS[cluster][0] != base:
        report.error(base, "CLUSTER must be the id that owns this file name")
        return set()
    if not isinstance(roles, dict):
        report.error(base, "ROLES must be a dict")
        return set()
    expected = [s for s, v in MANIFEST.items() if v[0] == cluster]
    for slug in roles:
        if slug not in expected:
            report.error(base, "role %s does not belong to cluster %s" % (slug, cluster))
    missing = [s for s in expected if s not in roles]
    if missing:
        (report.error if strict else report.warn)(base, "roles not written yet: " + ", ".join(missing))
    for slug, role in roles.items():
        if slug not in MANIFEST:
            continue
        w = "%s:%s" % (base, slug)
        if not isinstance(role, dict) or set(role) != {"summary", "reviewed_on", "questions"}:
            report.error(w, "role keys must be exactly summary, reviewed_on, questions")
            continue
        s = role["summary"]
        if not isinstance(s, str) or s != s.strip() or not 20 <= len(s) <= 160 \
                or not s.endswith(".") or not s[0].isupper():
            report.error(w, "summary: one sentence, 20-160 chars, capital first, full stop last")
        check_reviewed(role["reviewed_on"], w, report, strict)
        qs = role["questions"]
        if not isinstance(qs, list):
            report.error(w, "questions must be a list")
            continue
        seen, parsed = set(), []
        for i, item in enumerate(qs, 1):
            got = check_question(item, "%s#%d" % (w, i), report, seen)
            if got:
                parsed.append(got)
                all_questions.setdefault(normalise(got[2]), []).append(slug)
        if len(qs) != QUESTIONS_PER_ROLE:
            report.error(w, "needs exactly %d questions, has %d" % (QUESTIONS_PER_ROLE, len(qs)))
        for t in TIERS:
            n = sum(1 for p in parsed if p[0] == t)
            if n != PER_TIER:
                report.error(w, "needs exactly %d %s questions, has %d" % (PER_TIER, t, n))
        cats = {p[1] for p in parsed}
        if len(cats) < 3:
            report.error(w, "needs at least 3 categories")
        if len(cats) > 8:
            report.warn(w, "more than 8 categories reads as noise on the summary card")
        if slug in legacy_technical:
            want = [(t, x) for t, _c, x in legacy_technical[slug]]
            got = [(p[0], p[2]) for p in parsed[:len(want)]]
            if got != want:
                report.error(w, "the first %d questions must be the legacy questions, same "
                                "order, same tier, same wording" % len(want))
    return {r for r in roles if r in expected}


def check_behavioural(path, report, strict, legacy_behavioural):
    base = os.path.basename(path)
    mod = load_module(path)
    if getattr(mod, "CLUSTER", None) != "behavioural":
        report.error(base, "CLUSTER must be 'behavioural'")
    check_reviewed(getattr(mod, "REVIEWED_ON", None), base, report, strict)
    qs = getattr(mod, "QUESTIONS", None)
    if not isinstance(qs, list):
        report.error(base, "QUESTIONS must be a list")
        return
    seen, parsed = set(), []
    for i, item in enumerate(qs, 1):
        got = check_question(item, "%s#%d" % (base, i), report, seen)
        if got:
            parsed.append(got)
    if len(qs) != BEHAVIOURAL_TOTAL:
        report.error(base, "needs exactly %d questions, has %d" % (BEHAVIOURAL_TOTAL, len(qs)))
    for t in TIERS:
        n = sum(1 for p in parsed if p[0] == t)
        if n != BEHAVIOURAL_PER_TIER:
            report.error(base, "needs exactly %d %s questions, has %d"
                         % (BEHAVIOURAL_PER_TIER, t, n))
    if sum(1 for p in parsed if p[1] == HR_ROUND) < HR_ROUND_MIN:
        report.error(base, "needs at least %d questions in category '%s'"
                     % (HR_ROUND_MIN, HR_ROUND))
    want = [(t, x) for t, _c, x in legacy_behavioural]
    if [(p[0], p[2]) for p in parsed[:len(want)]] != want:
        report.error(base, "the first %d questions must be the legacy behavioural questions, "
                           "same order, same tier, same wording" % len(want))


def validate(paths, strict=False, require_all=False):
    report = Report()
    check_manifest(report)
    legacy_technical, legacy_behavioural = load_legacy()
    all_questions, present, files = {}, set(), set()
    for path in paths:
        base = os.path.basename(path)
        if base in files:
            report.error(base, "given twice")
            continue
        files.add(base)
        if base == BEHAVIOURAL_FILE:
            check_behavioural(path, report, strict, legacy_behavioural)
        elif base in {v[0] for v in CLUSTERS.values()}:
            present |= check_role_file(path, report, strict, legacy_technical, all_questions)
        else:
            report.warn(base, "not a content file; skipped")
    for text, slugs in all_questions.items():
        if len(set(slugs)) > 1:
            report.warn("cross-role", "same question in %s: %s" % (", ".join(sorted(set(slugs))),
                                                                 text[:60]))
    if require_all:
        for cluster, (name, _a, _r) in CLUSTERS.items():
            if name not in files:
                report.error("all", "missing " + name)
        if BEHAVIOURAL_FILE not in files:
            report.error("all", "missing " + BEHAVIOURAL_FILE)
    return report, present


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("files", nargs="*")
    ap.add_argument("--strict", action="store_true",
                    help="every role of each given file written, and every role reviewed")
    ap.add_argument("--all", action="store_true",
                    help="also require all six cluster files and behavioural.py")
    ap.add_argument("--manifest", action="store_true", help="check the manifest only")
    args = ap.parse_args(argv)
    if args.manifest or not args.files:
        report = Report()
        check_manifest(report)
        present = set()
    else:
        report, present = validate(args.files, args.strict, args.all)
    for line in report.warnings + report.errors:
        print(line)
    print("roles checked: %d of %d; errors: %d; warnings: %d"
          % (len(present), len(MANIFEST), len(report.errors), len(report.warnings)))
    return 1 if report.errors else 0


if __name__ == "__main__":
    sys.exit(main())
