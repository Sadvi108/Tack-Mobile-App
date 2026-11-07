# -*- coding: utf-8 -*-
"""Tests for build.py. Standard library only.

    python3 -m unittest discover -s supabase/seed/interview_bank -p 'test_*.py'

Content files are written to a temporary directory: the three drafts from the
plan verbatim, and every other role built from the legacy questions plus
filler that passes validate.py. The working directory is the repository root,
because validate.py reads the career catalog from there.
"""
import contextlib
import io
import json
import os
import re
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
sys.path.insert(0, HERE)

import build  # noqa: E402
import legacy_0069  # noqa: E402
import validate  # noqa: E402

E, M, H = "easy", "medium", "hard"
REVIEWED = "2026-11-05"
_cwd = None


def setUpModule():
    global _cwd
    _cwd = os.getcwd()
    os.chdir(REPO)


def tearDownModule():
    os.chdir(_cwd)


# --------------------------------------------------------------- fixtures
# The three starting drafts in the plan (W1-1, W1-3, W2-2), as written there.
DRAFTS = {
    "banking-officer": {
        "summary": "Accounts and KYC, payments, cash, credit basics and money laundering checks at a bank branch.",
        "reviewed_on": None,
        "questions": [
            (E, "Banking basics", "What is the difference between a savings account and a current account?",
             ["Savings: for individuals to keep money and earn some profit",
              "Current: for businesses and frequent transactions, with cheque books",
              "Fees and minimum balance rules differ by bank"]),
            (E, "Banking basics", "What does Bangladesh Bank do?",
             ["It is the central bank: it issues currency and sets monetary policy",
              "It licenses, regulates and supervises banks through circulars",
              "It runs the payment systems banks use to clear cheques and move money",
              "It manages the foreign exchange reserves"],
             "https://www.bb.org.bd/"),
            (E, "Accounts and KYC", "What is KYC, and why does a bank need it before opening an account?",
             ["Know your customer: confirm who the person is and how they will use the account",
              "Collect and check the NID, photo, address, source of funds and nominee",
              "It helps stop fraud and money laundering, and it is a legal duty"]),
            (E, "Customer service", "A customer is angry because their cheque was returned. How do you handle it at the desk?",
             ["Stay calm, listen and say sorry for the trouble without blaming anyone",
              "Find the reason: balance, signature, date, or words and figures not matching",
              "Explain the reason simply and what they can do next",
              "Keep their details private and escalate if needed"]),
            (E, "Banking basics", "What is the difference between a bank account and a mobile financial service wallet?",
             ["A bank takes deposits, gives loans and offers full accounts",
              "A wallet lets people send, receive and pay from a phone, with lower limits",
              "Both are regulated by Bangladesh Bank",
              "Wallets reach people far from branches"],
             "https://www.bb.org.bd/"),
            (M, "Payments", "What is the difference between BEFTN, RTGS and NPSB transfers?",
             ["BEFTN: electronic transfers settled in batches, not instant",
              "RTGS: real-time transfers for high-value payments, in set hours",
              "NPSB: the interbank network for cards and instant online transfers",
              "Choose by amount, urgency and the channel the customer uses"]),
            (M, "Money laundering", "What is money laundering, and what would make a transaction look suspicious to you?",
             ["Making money from crime look clean: placement, layering, integration",
              "Red flags: activity that does not fit the customer, many deposits just under limits",
              "Report to the branch anti-money laundering officer, who reports to BFIU",
              "Never warn the customer"],
             "https://www.bfiu.org.bd/"),
            (M, "Accounts and KYC", "A customer wants to open an account but has only a photocopy of their NID. What do you do?",
             ["Follow the bank's KYC policy: the original must be seen and verified",
              "Banks check NID details online against the national ID database",
              "Explain politely what is needed and help them finish when they return",
              "Do not bend the rule, even for a known face"]),
            (M, "Credit basics", "What is a classified or non-performing loan, and why does it matter to a bank?",
             ["A loan unpaid past a set period is classified under Bangladesh Bank rules",
              "The bank must set money aside, which cuts profit and capital",
              "Prevention: careful checks before lending, including the CIB report, and early follow-up"],
             "https://www.bb.org.bd/"),
            (M, "Ethics", "At the end of the day your cash is short by two thousand taka. What do you do?",
             ["Do not quietly cover it from your own pocket",
              "Recount, and check every voucher, entry and log",
              "Tell the cash in-charge or manager at once and record it",
              "Find the cause so it does not happen again"]),
            (H, "Banking basics", "What are CRR and SLR, and how do they affect how much a bank can lend?",
             ["CRR: the share of deposits kept as cash with Bangladesh Bank",
              "SLR: the share kept in safe, liquid assets such as government securities",
              "Both reduce the money available to lend",
              "Quote a rate only after checking the latest circular"],
             "https://www.bb.org.bd/"),
            (H, "Banking basics", "How is Islamic banking different from conventional banking? Explain one product.",
             ["Islamic banks avoid interest and use profit-sharing or trade-based contracts",
              "Mudaraba: depositors share in the profit",
              "Murabaha: the bank buys the item and sells it on at an agreed mark-up",
              "A Shariah board approves the products"]),
            (H, "Ethics", "A senior colleague asks you to process a large transfer without the usual documents, just this once. What do you do?",
             ["Politely refuse to skip the process and explain the rule",
              "Offer to help get the documents quickly",
              "If the pressure continues, go to the manager or compliance",
              "The rules protect the customer, the bank and you"]),
            (H, "Customer service", "A customer says money left their account after they shared an OTP on a phone call. How do you help?",
             ["Act fast: block the card or channel and log the complaint",
              "Raise a dispute or trace with the receiving bank or wallet",
              "Explain kindly, without blame, that the bank never asks for an OTP",
              "Report through the bank's fraud process and follow up"]),
            (H, "Branch growth", "How would you grow deposits at a branch in a district town?",
             ["Know the area: traders, families receiving remittance, schools, small businesses",
              "Match products to them: savings schemes, remittance services, student accounts",
              "Go out to markets and schools, and ask happy customers for referrals",
              "Measure new accounts, deposit growth and cost"]),
        ],
    },
    "civil-site-engineer": {
        "summary": "Concrete, reinforcement, soil, quantities and safety on a Bangladeshi building site.",
        "reviewed_on": None,
        "questions": [
            (E, "Concrete", "What is curing, and what happens if concrete is not cured properly?",
             ["Curing keeps new concrete wet so the cement keeps hardening",
              "Common ways: ponding, wet hessian or plastic cover, for the days the spec says",
              "Poor curing gives cracks, lower strength and a weak surface"]),
            (E, "Concrete", "What does a slump test tell you, and how do you do it on site?",
             ["It checks how workable fresh concrete is",
              "Fill the cone in three layers, rod each layer, lift it and measure the drop",
              "If the slump is far from the spec, stop and check the water and mix"]),
            (E, "Reinforcement", "What is clear cover in RCC, and what goes wrong if it is too thin?",
             ["Cover is the concrete between the bars and the outside face",
              "It protects steel from rust and fire and helps the bond",
              "Thin cover leads to rust, cracks and spalling"]),
            (E, "Drawings and codes", "What is the difference between an architectural drawing and a structural drawing?",
             ["Architectural: rooms, sizes, doors, windows and finishes",
              "Structural: foundations, columns, beams, slabs and bar details",
              "On site you check they agree and raise any clash early"]),
            (E, "Site practice", "What do you check before you allow a slab to be poured?",
             ["Formwork is level, tight and well propped",
              "Bars match the drawing and someone has signed it off",
              "Materials, vibrator, workers and the curing plan are ready"]),
            (M, "Quantities", "How do you estimate the bricks for a 10-inch brick wall?",
             ["Find the wall volume and take out doors and windows",
              "Use brick size plus mortar joint to get bricks per cubic metre",
              "Add a small wastage allowance and work out the mortar"]),
            (M, "Concrete", "The cylinder test results come back below the required strength. What do you do?",
             ["Check the test record first: sampling, curing of samples, the lab",
              "Tell the senior engineer or consultant at once, in writing",
              "Test the structure itself, then accept, strengthen or remove"]),
            (M, "Soil and foundations", "Why are piles so common in Dhaka and many parts of Bangladesh?",
             ["Much of the land is soft clay or filled ground with a high water table",
              "Shallow footings may settle unevenly",
              "Piles carry the load down to firmer soil"]),
            (M, "Safety", "What are the biggest safety risks on a building site, and what do you do on your first day?",
             ["Falls from height, falling objects and electric shock",
              "Check helmets, boots and harnesses are used",
              "Barricade openings and stop any unsafe work"]),
            (M, "Site management", "You find workers using less cement than the mix design says. What do you do?",
             ["Get facts first: watch a batch, check stock and records",
              "Stop that work and talk to the contractor's site in-charge",
              "Report it in writing and check the work already done"]),
            (H, "Drawings and codes", "What is the Bangladesh National Building Code, and how does it affect your work on site?",
             ["It sets minimum rules for design, materials, construction and safety",
              "Check the current edition on the official site before quoting it",
              "On site you build to approved drawings designed under it"],
             "https://hbri.gov.bd/"),
            (H, "Site management", "The monsoon starts next week and you have an open basement excavation. What is your plan?",
             ["Dewatering pumps with backup power",
              "Protect the pit sides with shoring or safe slopes and drains",
              "Watch neighbouring buildings for cracks or settlement"]),
            (H, "Quantities", "How do you prepare a bill of quantities from drawings, and what mistakes are common?",
             ["Break the work into items by trade, each with a clear unit",
              "Measure in a fixed order so nothing is missed",
              "Common mistakes: missing items, wrong units, double counting"]),
            (H, "Site management", "Your site is three weeks behind schedule. How do you find out why and recover?",
             ["Compare planned and actual progress item by item",
              "Find the critical activities causing the delay",
              "Tell the client honestly, with a new schedule"]),
            (H, "Concrete", "A week after the formwork is removed, you see a crack in a beam. What do you do?",
             ["Keep the load off and put the props back",
              "Record the crack: width, length, pattern, photos and date",
              "Tell the structural engineer and never just plaster over it"]),
        ],
    },
    "apparel-merchandiser": {
        "summary": "Orders, costing, sampling, time and action plans, materials and shipment in a garment factory.",
        "reviewed_on": None,
        "questions": [
            (E, "Orders", "What does a merchandiser do in a garment factory, from order to shipment?",
             ["Turns the buyer's order into a plan the factory can follow",
              "Books fabric and trims, chases samples, keeps the time and action plan",
              "Talks every day with the buyer, production, quality and commercial teams",
              "Owns the order until it ships and payment is clear"]),
            (E, "Materials", "What is the difference between knit and woven fabric? Name a garment made from each.",
             ["Knit is loops from one yarn and stretches; woven crosses two sets of yarn",
              "Knit: T-shirt, polo. Woven: shirt, trousers, denim",
              "Factories usually specialise in one or the other"]),
            (E, "Materials", "What does GSM mean on a fabric, and why does the buyer care?",
             ["Grams per square metre: how heavy the fabric is",
              "Higher GSM usually means thicker fabric and a higher cost",
              "The order fixes the GSM, so fabric outside it can be rejected"]),
            (E, "Orders", "What samples does an order usually go through before bulk production?",
             ["Proto, fit, size set, pre-production, then shipment sample; names vary by buyer",
              "Each one answers a question: style, fit, sizes, final approval",
              "Bulk cutting should not start before pre-production approval"]),
            (E, "Orders", "What is a tech pack, and what do you check first when you receive one?",
             ["The buyer's full description: sketches, measurements, fabric, trims, labels, packing",
              "First check what is missing or unclear",
              "Send questions early, in writing, before costing or sampling"]),
            (M, "Costing", "How would you build the FOB price of a basic T-shirt?",
             ["Fabric: consumption per dozen times fabric price, plus wastage",
              "Add trims, any print or wash, the cost of making and overheads",
              "Add commercial costs such as testing, transport and bank charges, then profit",
              "Check the total against the buyer's target price"]),
            (M, "Time and action", "What is a time and action calendar, and what do you do when one step slips?",
             ["It lists every step from order to shipment, with a date and an owner",
              "When a step slips, work out the effect on the ship date at once",
              "Look for ways to recover: steps in parallel, more lines, faster approvals",
              "Tell the buyer early, with a new plan"]),
            (M, "Materials", "Fabric for an order arrives with a shade difference between rolls. What do you do?",
             ["Stop mixed shades going to cutting",
              "Ask quality to group the rolls by shade",
              "Raise a claim or replacement with the mill and check the delay",
              "Tell the buyer if it cannot be fixed, with options"]),
            (M, "Shipment and payment", "What is a letter of credit, and why does a garment exporter use a back-to-back LC?",
             ["An LC is a bank's promise to pay when the documents match the terms",
              "A back-to-back LC uses the export LC to open import LCs for fabric and trims",
              "It lets the factory buy materials without paying cash up front",
              "Small document mistakes can delay payment"]),
            (M, "Materials", "An order has five colours and six sizes. How do you work out how much fabric to book?",
             ["Use the colour and size breakdown of the order quantity",
              "Take consumption per size from the pattern or marker",
              "Add wastage and allow for shrinkage after washing",
              "Book by colour, and check the mill's minimum order"]),
            (H, "Shipment and payment", "Production is five days late and the ship date is fixed. What are your options, and how do you choose?",
             ["Find the real cause first: materials, capacity, quality or approvals",
              "Options: overtime, more lines, an approved subcontractor, a split shipment, air freight",
              "Compare each by cost, quality risk and who pays",
              "Agree the plan with the buyer in writing before acting"]),
            (H, "Quality", "The final inspection fails on AQL. What happens next, and what do you do?",
             ["AQL is a sampling rule, so a fail means too many defects in the lot",
              "Find the defect types, then check every piece and repair or replace",
              "Book a re-inspection and update the shipment plan",
              "Fix the root cause so the next order does not repeat it"]),
            (H, "Costing", "The buyer's target price is below your cost. How do you respond?",
             ["Break down the cost to see where the gap is",
              "Offer changes that keep quality: fabric or trim choices, simpler construction",
              "Know the factory's lowest acceptable price and do not go under it",
              "Explain your reasons and give options, to keep the relationship"]),
            (H, "Buyer communication", "After the pre-production sample is approved, the buyer asks to change the buttons. How do you handle it?",
             ["Check what it affects: cost, lead time, trims already booked",
              "Confirm the change and its cost and time impact in writing",
              "Update the tech pack, trims order and plan, and tell production and quality",
              "Never change bulk on a verbal request"]),
            (H, "Compliance", "Why do buyers audit factories for social and safety compliance, and how does it affect your work?",
             ["Buyers need proof that workers are treated fairly and buildings are safe",
              "Checks became much stricter after the Rana Plaza collapse in 2013",
              "An unapproved subcontractor or a failed audit can stop orders",
              "Place work only in approved units and keep records clean"]),
        ],
    },
}

FILLER_CATEGORIES = ("Basics", "Practice", "Judgement")
FILLER_POINTS = ["Names the idea the question is about", "Gives one example from real work"]
SOURCE = "https://nbr.gov.bd/"


def _sentence_case(category):
    return category[0].upper() + category[1:]


def _legacy_entry(tier, category, text):
    entry = (tier, _sentence_case(category), text, list(FILLER_POINTS))
    if validate.RULE_WORDS.search(text):
        entry += (SOURCE,)
    return entry


def _filler(slug, tier, i):
    return (tier, FILLER_CATEGORIES[i % 3],
            "How would you handle task %d as a new %s, step by step?" % (i, slug.replace("-", " ")),
            list(FILLER_POINTS))


def role_content(slug, reviewed=REVIEWED):
    if slug in DRAFTS:
        role = dict(DRAFTS[slug])
        role["questions"] = list(role["questions"])
    else:
        legacy, _ = validate.load_legacy()
        if slug in legacy:
            questions = [_legacy_entry(*q) for q in legacy[slug]]
            per_tier = 2
        else:
            questions = []
            per_tier = 5
        for t in (E, M, H):
            questions += [_filler(slug, t, len(questions) + 1 + k) for k in range(per_tier)]
        # validate.py wants each tier's questions in any order; keep authoring
        # order: the legacy nine first, then the filler.
        role = {"summary": "Practice questions for the %s role." % slug.replace("-", " "),
                "reviewed_on": None, "questions": questions}
    role["reviewed_on"] = reviewed
    return role


def behavioural_content():
    _, legacy = validate.load_legacy()
    questions = [_legacy_entry(*q) for q in legacy]
    n = len(questions)
    for t in (E, M, H):
        for k in range(5):
            n += 1
            category = "HR round" if n <= 13 else "Teamwork"
            questions.append((t, category, "Tell me about moment %d at work and what you did next?" % n,
                              list(FILLER_POINTS)))
    return questions


def write_content(directory, clusters=None, behavioural=True, reviewed=REVIEWED, drop=()):
    clusters = list(validate.CLUSTERS) if clusters is None else clusters
    for cluster in clusters:
        name = validate.CLUSTERS[cluster][0]
        roles = {slug: role_content(slug, reviewed) for slug, m in validate.MANIFEST.items()
                 if m[0] == cluster and slug not in drop}
        with open(os.path.join(directory, name), "w", encoding="utf-8") as f:
            f.write("# -*- coding: utf-8 -*-\nCLUSTER = %r\nROLES = %r\n" % (cluster, roles))
    if behavioural:
        with open(os.path.join(directory, validate.BEHAVIOURAL_FILE), "w", encoding="utf-8") as f:
            f.write("# -*- coding: utf-8 -*-\nCLUSTER = 'behavioural'\nREVIEWED_ON = %r\n"
                    "QUESTIONS = %r\n" % (reviewed, behavioural_content()))


def run(*argv):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = build.main(list(argv))
    return code, out.getvalue()


class TempDirs(unittest.TestCase):
    def setUp(self):
        self.content = tempfile.mkdtemp(prefix="tack_content_")
        self.migrations = tempfile.mkdtemp(prefix="tack_migrations_")
        self.addCleanup(shutil.rmtree, self.content)
        self.addCleanup(shutil.rmtree, self.migrations)

    def cli(self, *argv):
        return run("--content-dir", self.content, "--migrations-dir", self.migrations, *argv)

    def out_path(self, name="0098_interview_pool_seed.sql"):
        return os.path.join(self.migrations, name)


# ------------------------------------------------------------------ tests
class SlugTest(unittest.TestCase):
    def test_parity_table(self):
        # The same table is in bank_test.ts and 0096's checks.
        cases = {
            "Frontend developer": "frontend-developer",
            "Backend developer": "backend-developer",
            "Data analyst": "data-analyst",
            "Digital marketer": "digital-marketer",
            "HR executive": "hr-executive",
            "Business analyst": "business-analyst",
            "Graphic designer": "graphic-designer",
            "QA engineer": "qa-engineer",
            "Accountant": "accountant",
            "Content writer": "content-writer",
            "UI and UX designer": "ui-and-ux-designer",
            "C++ developer": "c-developer",
            "  Data   analyst  ": "data-analyst",
            "  বাংলা  ": "",
            "": "",
        }
        for text, slug in cases.items():
            self.assertEqual(validate.slugify(text), slug, text)

    def test_every_manifest_title_is_its_slug(self):
        for slug, m in validate.MANIFEST.items():
            self.assertEqual(validate.slugify(m[1]), slug)


class IdTest(unittest.TestCase):
    def test_stable_across_runs(self):
        a = build.pool_id("data-analyst", "What does a JOIN do?")
        self.assertEqual(a, build.pool_id("data-analyst", "What does a JOIN do?"))
        self.assertEqual(a, build.pool_id("data-analyst", "  what does a  JOIN do?"))

    def test_changes_with_text_and_role(self):
        a = build.pool_id("data-analyst", "What does a JOIN do?")
        self.assertNotEqual(a, build.pool_id("data-analyst", "What does a UNION do?"))
        self.assertNotEqual(a, build.pool_id("qa-engineer", "What does a JOIN do?"))
        self.assertNotEqual(a, build.pool_id(None, "What does a JOIN do?"))
        self.assertEqual(build.pool_id(None, "Tell me about yourself."),
                         build.pool_id("behavioural", "Tell me about yourself."))


class CompositionTest(unittest.TestCase):
    def test_slots_match_0096(self):
        self.assertEqual(build.slots(E, 5), [E, E, E, M, M])
        self.assertEqual(build.slots(M, 5), [E, M, M, M, H])
        self.assertEqual(build.slots(H, 5), [M, M, H, H, H])
        self.assertEqual(build.slots(H, 3), [M, H, H])
        for d in (E, M, H):
            for n in range(3, 11):
                s = build.slots(d, n)
                self.assertEqual(len(s), n)
                self.assertEqual(s, sorted(s, key=validate.TIERS.index))
        self.assertEqual(legacy_0069.COMPOSITION, {d: build.slots(d, 5) for d in (E, M, H)})

    def test_legacy_technical_sets_are_what_0069_shipped(self):
        legacy, _ = validate.load_legacy()
        for slug, questions in legacy.items():
            pool = [build.pool_item(slug, i, (t, c, x, [])) for i, (t, c, x) in enumerate(questions, 1)]
            for difficulty, wanted in legacy_0069.COMPOSITION.items():
                got = [q["question"] for q in build.compose(pool, [], "technical", difficulty)]
                want = [q["question"] for q in legacy_0069.pick(questions, wanted)]
                self.assertEqual(got, want, "%s %s" % (slug, difficulty))

    def test_full_legacy_roles_keep_their_technical_sets(self):
        legacy, _ = validate.load_legacy()
        for slug, questions in legacy.items():
            pool = [build.pool_item(slug, i, q) for i, q in enumerate(role_content(slug)["questions"], 1)]
            for difficulty, wanted in legacy_0069.COMPOSITION.items():
                got = [q["question"] for q in build.compose(pool, [], "technical", difficulty)]
                want = [q["question"] for q in legacy_0069.pick(questions, wanted)]
                self.assertEqual(got, want, "%s %s" % (slug, difficulty))

    def test_mixed_sets_lead_with_behavioural_questions(self):
        role = [build.pool_item("civil-site-engineer", i, q)
                for i, q in enumerate(DRAFTS["civil-site-engineer"]["questions"], 1)]
        beh = [build.pool_item(None, i, q) for i, q in enumerate(behavioural_content(), 1)]
        beh_ids = {q["id"] for q in beh}
        for d in (E, M, H):
            for n in range(3, 11):
                got = build.compose(role, beh, "mixed", d, n)
                b = max(1, int(n * 0.4 + 0.5))
                self.assertEqual(len(got), n)
                self.assertEqual([q["pool_id"] in beh_ids for q in got], [True] * b + [False] * (n - b))
        medium = build.compose(role, beh, "mixed", M)
        self.assertEqual([q["pool_id"] in beh_ids for q in medium], [True, True, False, False, False])

    def test_an_empty_tier_borrows_the_nearest_easier_one_first(self):
        # No medium questions: the medium slot takes the second easy one, not a
        # hard one, as interview_draw orders a tie.
        pool = [build.pool_item("x", i, (t, "Basics", "Question number %d here?" % i, []))
                for i, t in enumerate([E, E, H, H], 1)]
        got = build.compose(pool, [], "technical", M, 3)
        self.assertEqual([q["question"] for q in got],
                         ["Question number 1 here?", "Question number 2 here?",
                          "Question number 3 here?"])
        # An easy slot with no easy question left takes medium before hard.
        pool = [build.pool_item("x", i, (t, "Basics", "Question number %d here?" % i, []))
                for i, t in enumerate([E, H, M], 1)]
        got = build.compose(pool, [], "technical", E, 3)
        self.assertEqual([q["question"] for q in got],
                         ["Question number 1 here?", "Question number 3 here?"]
                         + ["Question number 2 here?"])

    def test_items_carry_key_points_and_pool_ids(self):
        pool = [build.pool_item("banking-officer", i, q)
                for i, q in enumerate(DRAFTS["banking-officer"]["questions"], 1)]
        first = build.compose(pool, [], "technical", E)[0]
        self.assertEqual(sorted(first), ["category", "key_points", "pool_id", "question"])
        self.assertEqual(first["pool_id"], pool[0]["id"])
        self.assertEqual(first["key_points"], DRAFTS["banking-officer"]["questions"][0][3])


class RequirementsTest(unittest.TestCase):
    def test_a_field_without_its_default_is_refused(self):
        roles = set(validate.MANIFEST) - {"electrical-engineer"}
        errors, _ = build.requirements(roles, True, False)
        self.assertTrue(any("electrical-engineer" in e for e in errors), errors)

    def test_the_general_role_is_required(self):
        roles = set(validate.MANIFEST) - {"management-trainee"}
        errors, _ = build.requirements(roles, True, False)
        self.assertTrue(any("management-trainee" in e for e in errors), errors)

    def test_missing_roles_warn_unless_all(self):
        roles = set(validate.MANIFEST) - {"textile-quality-inspector"}
        errors, warnings = build.requirements(roles, True, False)
        self.assertEqual(errors, [])
        self.assertTrue(any("textile-quality-inspector" in w for w in warnings))
        errors, _ = build.requirements(roles, True, True)
        self.assertTrue(any("textile-quality-inspector" in e for e in errors))

    def test_a_path_title_that_names_another_role_is_refused(self):
        # database-developer is mapped to backend-developer; a title equal to
        # frontend-developer's alias would resolve elsewhere in 0098's check.
        titles = {"database-developer": "Web developer"}
        errors = build.resolution_errors(set(validate.MANIFEST), titles)
        self.assertEqual(len(errors), 1)
        self.assertIn("frontend-developer", errors[0])
        self.assertEqual(build.resolution_errors(set(validate.MANIFEST)), [])


class CliTest(TempDirs):
    def test_no_content_yet(self):
        code, out = self.cli("--check")
        self.assertEqual(code, 0)
        self.assertIn("no content yet", out)

    def test_nothing_generated_yet(self):
        write_content(self.content)
        code, out = self.cli("--verify")
        self.assertEqual(code, 0)
        self.assertIn("nothing generated yet", out)

    def test_check_prints_stats(self):
        write_content(self.content, clusters=["software", "business", "creative_public"],
                      reviewed=None)
        code, out = self.cli("--check")
        self.assertEqual(code, 0, out)
        self.assertIn("roles: 29 of 40", out)
        code, out = self.cli("--check", "--strict")
        self.assertEqual(code, 1)

    def test_out_refuses_a_missing_field_default(self):
        # Telecommunications engineer is in the software file, but its field's
        # default, electrical engineer, is in the engineering file.
        write_content(self.content, clusters=["software", "business", "creative_public"])
        code, out = self.cli("--out", self.out_path())
        self.assertEqual(code, 1)
        self.assertIn("electrical-engineer", out)
        self.assertFalse(os.path.exists(self.out_path()))

    def test_out_refuses_without_the_general_role(self):
        write_content(self.content, clusters=["software", "creative_public", "engineering"])
        code, out = self.cli("--out", self.out_path())
        self.assertEqual(code, 1)
        self.assertIn("management-trainee", out)
        self.assertFalse(os.path.exists(self.out_path()))

    def test_out_refuses_unreviewed_content(self):
        write_content(self.content, reviewed=None)
        code, out = self.cli("--out", self.out_path())
        self.assertEqual(code, 1)
        self.assertIn("reviewed_on", out)

    def test_out_writes_parseable_blocks(self):
        write_content(self.content, clusters=["software", "business", "creative_public",
                                              "engineering", "rmg"])
        code, out = self.cli("--out", self.out_path())
        self.assertEqual(code, 0, out)
        self.assertIn("pharmaceutical-quality-analyst", out)  # warned as missing
        with open(self.out_path(), encoding="utf-8") as f:
            sql = f.read()
        statements = [line for line in sql.splitlines()
                      if line.strip() and not line.startswith("--")]
        self.assertEqual(statements[0], "set local tack.seeding = 'on';")
        self.assertTrue(sql.startswith("-- Generated by supabase/seed/interview_bank/build.py."))
        blocks = {m.group(1): json.loads(m.group(2))
                  for m in re.finditer(r"\$(\w+)\$(.*?)\$\1\$", sql, re.S)}
        self.assertEqual(sorted(blocks), sorted(build.TAGS))
        roles = {r["slug"]: r for r in blocks["roles"]}
        self.assertEqual(len(roles), 36)
        self.assertEqual(sorted(roles["civil-site-engineer"]),
                         ["cluster", "field", "field_default", "slug", "sort_order",
                          "summary", "title"])
        self.assertTrue(roles["civil-site-engineer"]["field_default"])
        pool = blocks["pool"]
        self.assertEqual(len(pool), 36 * 15 + 24)
        self.assertEqual(len({q["id"] for q in pool}), len(pool))
        self.assertEqual(sum(1 for q in pool if q["role"] is None), 24)
        bnbc = [q for q in pool if "National Building Code" in q["question"]][0]
        self.assertEqual(bnbc["source_url"], "https://hbri.gov.bd/")
        self.assertEqual(len(blocks["sets"]), 36 * 9)
        self.assertTrue(all(len(s["questions"]) == 5 for s in blocks["sets"]))
        self.assertEqual(blocks["packs"], [{"slug": k, "about": v}
                                           for k, v in build.companies.ABOUT.items()])
        self.assertIn({"alias": "sqa", "role": "qa-engineer"}, blocks["aliases"])
        self.assertIn({"path": "bim-modeller", "role": "civil-site-engineer"}, blocks["paths"])
        # The thresholds 0098 checks itself against are written in.
        self.assertIn("v_n <> 36", sql)
        self.assertTrue(sql.rstrip().endswith("end $$;"))

    def _generated(self):
        write_content(self.content, clusters=["software", "business", "creative_public",
                                              "engineering"])
        self.assertEqual(self.cli("--out", self.out_path())[0], 0)
        with open(self.out_path(), encoding="utf-8") as f:
            return f.read()

    def test_a_run_outside_a_transaction_fails_before_writing(self):
        # set local does nothing outside a transaction, and the seed guard
        # would then skip every seed set without a word.
        sql = self._generated()
        body = "\n".join(line for line in sql.splitlines() if not line.startswith("--"))
        guard = body.index("do $$")
        self.assertLess(body.index("set local tack.seeding = 'on';"), guard)
        for write in ("create temp table", "insert into", "update public.", "delete from"):
            self.assertLess(guard, body.index(write), write)
        block = body[guard:body.index("end $$;", guard)]
        self.assertIn("current_setting('tack.seeding', true)", block)
        self.assertIn("<> 'on'", block)
        self.assertIn("raise exception", block)

    def test_role_sort_order_follows_the_field_list(self):
        write_content(self.content, clusters=["software", "business", "creative_public",
                                              "engineering"])
        self.assertEqual(self.cli("--out", self.out_path())[0], 0)
        with open(self.out_path(), encoding="utf-8") as f:
            sql = f.read()
        roles = json.loads(re.search(r"\$roles\$(.*?)\$roles\$", sql, re.S).group(1))
        order = {r["slug"]: r["sort_order"] for r in roles}
        # computer-science is line 2 of career_fields.txt; its default leads.
        self.assertEqual(order["software-engineer"], 200)
        self.assertGreater(order["backend-developer"], 200)
        self.assertLess(order["backend-developer"], order["frontend-developer"])
        self.assertEqual(order["management-trainee"], 600)

    def test_verify_reports_drift_after_a_one_word_change(self):
        write_content(self.content, clusters=["software", "business", "creative_public",
                                              "engineering"])
        self.assertEqual(self.cli("--out", self.out_path())[0], 0)
        code, out = self.cli("--verify")
        self.assertEqual(code, 0, out)
        path = os.path.join(self.content, "roles_engineering.py")
        with open(path, encoding="utf-8") as f:
            text = f.read()
        with open(path, "w", encoding="utf-8") as f:
            f.write(text.replace("Keep the load off", "Keep the loads off"))
        code, out = self.cli("--verify")
        self.assertEqual(code, 1)
        self.assertIn("drift", out)

    def test_verify_reads_the_newest_generated_file(self):
        write_content(self.content, clusters=["software", "business", "creative_public",
                                              "engineering"])
        self.assertEqual(self.cli("--out", self.out_path())[0], 0)
        with open(self.out_path("0099_interview_pool_refresh.sql"), "w") as f:
            f.write("-- stale\n")
        code, out = self.cli("--verify")
        self.assertEqual(code, 1)
        self.assertIn("0099_interview_pool_refresh.sql", out)

    def test_build_is_deterministic(self):
        write_content(self.content, clusters=["software", "business", "creative_public",
                                              "engineering"])
        self.assertEqual(self.cli("--out", self.out_path("0098_interview_pool_a.sql"))[0], 0)
        self.assertEqual(self.cli("--out", self.out_path("0098_interview_pool_b.sql"))[0], 0)
        with open(self.out_path("0098_interview_pool_a.sql"), encoding="utf-8") as a, \
                open(self.out_path("0098_interview_pool_b.sql"), encoding="utf-8") as b:
            self.assertEqual(a.read(), b.read())


if __name__ == "__main__":
    unittest.main()
