"""English verb inflection — expands base verbs into all surface forms.

Regular rules plus an irregular table. Used to grow the lexicon so that
"registered", "knew", "running" all resolve to their vocabulary ID.
"""

VOWELS = "aeiou"

# base -> (3rd person singular, past, past participle, gerund)
IRREGULAR = {
    "be": ("is", "was", "been", "being"),
    "have": ("has", "had", "had", "having"),
    "do": ("does", "did", "done", "doing"),
    "go": ("goes", "went", "gone", "going"),
    "know": ("knows", "knew", "known", "knowing"),
    "think": ("thinks", "thought", "thought", "thinking"),
    "see": ("sees", "saw", "seen", "seeing"),
    "give": ("gives", "gave", "given", "giving"),
    "take": ("takes", "took", "taken", "taking"),
    "make": ("makes", "made", "made", "making"),
    "get": ("gets", "got", "gotten", "getting"),
    "send": ("sends", "sent", "sent", "sending"),
    "buy": ("buys", "bought", "bought", "buying"),
    "sell": ("sells", "sold", "sold", "selling"),
    "pay": ("pays", "paid", "paid", "paying"),
    "teach": ("teaches", "taught", "taught", "teaching"),
    "learn": ("learns", "learnt", "learned", "learning"),
    "read": ("reads", "read", "read", "reading"),
    "write": ("writes", "wrote", "written", "writing"),
    "speak": ("speaks", "spoke", "spoken", "speaking"),
    "hear": ("hears", "heard", "heard", "hearing"),
    "tell": ("tells", "told", "told", "telling"),
    "say": ("says", "said", "said", "saying"),
    "run": ("runs", "ran", "run", "running"),
    "sit": ("sits", "sat", "sat", "sitting"),
    "stand": ("stands", "stood", "stood", "standing"),
    "sleep": ("sleeps", "slept", "slept", "sleeping"),
    "wake": ("wakes", "woke", "woken", "waking"),
    "eat": ("eats", "ate", "eaten", "eating"),
    "drink": ("drinks", "drank", "drunk", "drinking"),
    "wear": ("wears", "wore", "worn", "wearing"),
    "sing": ("sings", "sang", "sung", "singing"),
    "draw": ("draws", "drew", "drawn", "drawing"),
    "drive": ("drives", "drove", "driven", "driving"),
    "fly": ("flies", "flew", "flown", "flying"),
    "swim": ("swims", "swam", "swum", "swimming"),
    "throw": ("throws", "threw", "thrown", "throwing"),
    "catch": ("catches", "caught", "caught", "catching"),
    "hold": ("holds", "held", "held", "holding"),
    "cut": ("cuts", "cut", "cut", "cutting"),
    "put": ("puts", "put", "put", "putting"),
    "bring": ("brings", "brought", "brought", "bringing"),
    "lend": ("lends", "lent", "lent", "lending"),
    "meet": ("meets", "met", "met", "meeting"),
    "fight": ("fights", "fought", "fought", "fighting"),
    "win": ("wins", "won", "won", "winning"),
    "lose": ("loses", "lost", "lost", "losing"),
    "find": ("finds", "found", "found", "finding"),
    "feel": ("feels", "felt", "felt", "feeling"),
    "forget": ("forgets", "forgot", "forgotten", "forgetting"),
    "understand": ("understands", "understood", "understood", "understanding"),
    "mean": ("means", "meant", "meant", "meaning"),
    "cost": ("costs", "cost", "cost", "costing"),
    "leave": ("leaves", "left", "left", "leaving"),
    "begin": ("begins", "began", "begun", "beginning"),
    "break": ("breaks", "broke", "broken", "breaking"),
    "build": ("builds", "built", "built", "building"),
    "fall": ("falls", "fell", "fallen", "falling"),
    "rise": ("rises", "rose", "risen", "rising"),
    "grow": ("grows", "grew", "grown", "growing"),
    "show": ("shows", "showed", "shown", "showing"),
    "steal": ("steals", "stole", "stolen", "stealing"),
    "stop": ("stops", "stopped", "stopped", "stopping"),
    "plan": ("plans", "planned", "planned", "planning"),
}


def third_singular(verb: str) -> str:
    if verb in IRREGULAR:
        return IRREGULAR[verb][0]
    if verb.endswith(("s", "x", "z", "ch", "sh", "o")):
        return verb + "es"
    if verb.endswith("y") and len(verb) > 1 and verb[-2] not in VOWELS:
        return verb[:-1] + "ies"
    return verb + "s"


def past(verb: str) -> str:
    if verb in IRREGULAR:
        return IRREGULAR[verb][1]
    return _ed(verb)


def past_participle(verb: str) -> str:
    if verb in IRREGULAR:
        return IRREGULAR[verb][2]
    return _ed(verb)


def gerund(verb: str) -> str:
    if verb in IRREGULAR:
        return IRREGULAR[verb][3]
    if verb.endswith("ie"):
        return verb[:-2] + "ying"
    if verb.endswith("e") and not verb.endswith("ee"):
        return verb[:-1] + "ing"
    if _cvc(verb):
        return verb + verb[-1] + "ing"
    return verb + "ing"


def _ed(verb: str) -> str:
    if verb.endswith("e"):
        return verb + "d"
    if verb.endswith("y") and len(verb) > 1 and verb[-2] not in VOWELS:
        return verb[:-1] + "ied"
    if _cvc(verb):
        return verb + verb[-1] + "ed"
    return verb + "ed"


def _cvc(verb: str) -> bool:
    """Short consonant-vowel-consonant verbs double the final consonant."""
    if len(verb) > 4 or len(verb) < 3:
        return False
    c = verb[-1]
    return (
        c not in VOWELS + "wxy"
        and verb[-2] in VOWELS
        and verb[-3] not in VOWELS
    )


def all_forms(verb: str) -> list[str]:
    """Every inflected surface form of a verb, base included, deduplicated."""
    if " " in verb:  # multi-word: inflect only the first word
        head, rest = verb.split(" ", 1)
        return [f"{form} {rest}" for form in all_forms(head)]
    forms = [verb, third_singular(verb), past(verb), past_participle(verb), gerund(verb)]
    seen: list[str] = []
    for f in forms:
        if f not in seen:
            seen.append(f)
    return seen
