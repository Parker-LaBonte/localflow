"""Round-6 data = round 5 + fixes for the conventions round-5 L still got wrong, and removal of two v4 templates that
contradicted the house style (comma after a kept "Also"; keeping a "The thing I wanted to say," lead-in after a detour).
-> data6/"""
import random
import make_data as v4
import make_data5 as d5
from make_data import example, cap

random.seed(66)

def gen_paragraph_fixed():   # v4 version dropped the comma after "Also" and produced "And, thanks"
    a = random.choice(["Great seeing you today.", "The demo is uploaded.", "Rehearsal went well.", "Payment went through.",
                       "The movers are booked.", "Your package shipped."])
    b, clean = random.choice([("also, um, can you send the photos", "Also, can you send the photos"),
                              ("also I'll, uh, call you later", "Also, I'll call you later"),
                              ("and, like, thanks again for the help", "And thanks again for the help"),
                              ("also, uh, did you get my text", "Also, did you get my text"),
                              ("anyway, um, talk soon", "Anyway, talk soon")])
    end = "?" if clean.split(",")[-1].strip().startswith(("can", "did")) else "."
    return f"{a}\n\n{cap(b)}{end}", f"{a}\n\n{clean}{end}"
v4.gen_paragraph = gen_paragraph_fixed

def gen_detour_fixed():      # the speaker's lead-in only survives when the rest grammatically continues it
    n = random.choice(v4.NAMES); p = random.choice(v4.PLACES); d = random.choice(v4.DAYS); t = random.choice(v4.TIMES)
    det = random.choice(["what was I saying, oh right,", "hold on, where was I, oh yeah,", "I forgot, oh yeah,",
                         "hang on, um, oh right,", "what was it, oh yeah,", "let me think, okay,"])
    return random.choice([
        (f"Hey {n}, I wanted to tell you that, {det} the shoot moved to {d}.", f"Hey {n}, I wanted to tell you that the shoot moved to {d}."),
        (f"Just a heads up that, {det} we're meeting at {p} instead.", f"Just a heads up that we're meeting at {p} instead."),
        (f"The thing I wanted to tell you, {det} the shoot moved to {d}.", f"The shoot moved to {d}."),
        (f"So what I wanted to say, {det} can you cover {d} at {t}?", f"Can you cover {d} at {t}?"),
        (f"I'm texting because, {det} I left my keys at {p}.", f"I'm texting because I left my keys at {p}."),
    ])
v4.gen_detour = gen_detour_fixed

ADJ_ONLY = [("king", "queen"), ("spicy", "mild"), ("early", "late"), ("red", "white"), ("cheap", "expensive"), ("first", "second"),
            ("decaf", "regular"), ("window", "aisle"), ("small", "large"), ("blue", "black"), ("short", "tall"), ("left", "right"),
            ("hot", "iced"), ("matte", "glossy"), ("basic", "premium"), ("upper", "lower")]
def gen_adj_only():           # correction swaps only the adjective; never invent a noun
    a, b = random.choice(ADJ_ONLY); v = random.choice(["Get", "Order", "I'll take", "Book", "Pick", "We want", "Grab", "Choose"])
    c = random.choice(d5.CUES); one = random.choice(["", "", " one"])
    end = "." if not v.startswith("We") else "."
    return f"{v} the {a}{one}, {c}, the {b}{one}{end}", f"{v} the {b}{one}{end}"

BUS = [("6:05", "6:35", "bus"), ("8:15", "8:45", "train"), ("noon", "1:00", "ferry"), ("early", "late", "shuttle"), ("7:20", "7:50", "flight")]
def gen_compound():           # after a correction is removed: no comma before "and" + verb (same subject); comma before a new clause
    a, b, veh = random.choice(BUS); c = random.choice(["uh, I mean", "no,", "sorry,", "wait,", "actually"])
    if random.random() < 0.5:
        tail = random.choice(["and call you when I land", "and grab a cab", "and walk from the station"])
        return f"I'll take the {a} {veh}, {c} the {b} {veh}, {tail}.", f"I'll take the {b} {veh} {tail}."
    tail = random.choice(["and I'll text you from the platform", "and Sam will pick me up", "and you can meet me there"])
    return f"I'm on the {a} {veh}, {c} the {b} {veh}, {tail}.", f"I'm on the {b} {veh}, {tail}."

def gen_keep_day():           # copy untouched details exactly (day, place) when only the time is corrected
    d = random.choice(v4.DAYS); t1, t2 = random.sample(v4.TIMES, 2); c = random.choice(["no", "wait", "sorry", "actually"])
    tail = random.choice(["and bring chairs", "and wear something warm", "so don't be late", "and bring your ID"])
    ev = random.choice(["The cookout", "Practice", "The meeting", "The dinner", "Pickup", "The recital"])
    return f"{ev} is {d} at {t1}, {c}, {t2}, {tail}.", f"{ev} is {d} at {t2}, {tail}."

def gen_lead_neverminds():
    lead = random.choice(["Okay, never mind,", "No wait, I meant to say", "Sorry, I meant to say", "Never mind that,", "Wait, no, I meant"])
    full = random.choice(["the bus leaves at 6", "I already paid the deposit", "the keys are in the car", "we're out of milk",
                          "the meeting moved to noon", "my flight got delayed", "the store opens at 10", "I sent the email"])
    return f"{lead} {full}.", cap(full) + "."

def gen_reported():           # don't add "that"; keep reported speech as spoken
    n = random.choice(d5.NAMES); f = random.choice(["uh,", "um,", "like,"])
    msg = random.choice(["doors open at 9", "the trailer is hitched", "dinner is on me", "the set starts late", "rehearsal is canceled"])
    v = random.choice(["Tell", "Let", "Remind"])
    if v == "Let": return f"Let {n} know, {f} {msg}.", f"Let {n} know {msg}."
    return f"{v} {n}, {f} {msg}.", f"{v} {n} {msg}."

def gen_retracted_clause():   # a trailing "wait, X is fine actually" removes X from the list
    label = random.choice(["Things to fix", "Notes for the edit", "Issues with the apartment", "Changes for the logo"])
    pts = random.sample(["the hum on channel three", "the chorus is muddy", "the font is too thin", "the sink leaks", "the colors are dull",
                         "the fade is too fast", "the door sticks", "the price is wrong"], 3)
    return (f"{label}. {cap(pts[0])}, um, {pts[1]}, and, wait, {pts[2]} is fine actually.",
            f"{label}:\n- {cap(pts[0])}\n- {cap(pts[1])}")

GENS6 = [(gen_adj_only, 90), (gen_compound, 60), (gen_keep_day, 60), (gen_lead_neverminds, 50), (gen_reported, 50), (gen_retracted_clause, 40)]

if __name__ == "__main__":
    rows = d5.build5()
    for g, n in GENS6:
        for _ in range(n): rows.append(example(*g()))
    d5.write(rows, "data6")
