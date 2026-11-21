"""Round-7 data = round 6 + restraint: plain sentences that open with words that are sometimes retraction cues
(wait/sorry/no/okay/basically/actually...) and must be kept verbatim; exact copying of titles, acronyms and
unusual words inside lists; in-list item replacement ("actually make that a dozen X"). -> data7/"""
import random
import make_data as v4
import make_data5 as d5
import make_data6 as d6
from make_data import example, cap

random.seed(77)

KEEP_PLAIN = [
    "Wait for the green light before you cross.", "Wait outside, the dog gets excited.", "Wait until Friday to send it.",
    "Wait, are you serious?", "Wait a second, I think I left the stove on.", "Sorry I'm late, traffic was awful.",
    "Sorry, the printer is out of toner.", "Sorry for the mess in the kitchen.", "Sorry, I can't make it this weekend.",
    "Sorry to bother you on a Sunday.", "No, the parade is on Saturday.", "No thanks, I already ate.", "No problem, happy to help.",
    "Okay, the van is packed.", "Okay, that makes sense.", "Okay, I'll call the landlord tomorrow.", "Basically, the budget ran out.",
    "Basically, the update fixed everything.", "Actually, the café on Elm is better.", "Actually, I've never been to Chicago.",
    "Honestly, the sequel was better.", "Anyway, the kids loved it.", "Also, the gate code is 4471.", "Never again will I fly overnight.",
    "Nevermind is my favorite Nirvana album.", "Scratch that itch and it only gets worse.", "I mean what I said yesterday.",
    "Hold on to your receipt.", "Hang on to the spare key for me.", "Let me think about it overnight.", "Go back to sleep, it's early.",
    "Start over from the second chorus.", "Our backlog keeps getting longer.", "The neighbors keep complaining about the noise.",
    "My inbox keeps filling up.", "The price keeps going up every year.", "She keeps forgetting her charger.",
    "Correction tape works better than whiteout.", "The first draft is always the hardest.", "Then the band walked off stage.",
    "Next time, bring an umbrella.", "Like I mentioned, the lease ends in May.", "I forgot how much I love this song.",
    "Where was the concert last year?", "What's the word for that in Spanish?", "Bring your own chair if you can.",
    "Pack light, the cabin is small.", "We had tacos, nachos, and churros at the fair.", "Do you want red, white, or rosé?",
    "The DJ played Dancing Queen twice.", "We rented two PAs and four XLRs.", "The SM7B sounds great on podcasts.",
    "Our first dance was to Can't Help Falling in Love.", "The QL5 needs a firmware update.", "Grab two DIs from the closet.",
]
TITLES = ["Hey Jude", "Moon River", "Valerie", "Dreams", "Let It Be", "Superstition", "September Rain", "Fly Me to the Moon",
          "Jolene", "Wonderwall", "Africa", "Yellow", "Crazy in Love", "Stand by Me", "The Way You Look Tonight"]
def gen_titles():
    t = random.sample(TITLES, 3)
    label = random.choice(["Setlist for the party", "Songs for the ceremony", "Playlist for the drive", "Encore options"])
    style = random.random()
    if style < 0.5:
        inp = f"{label}. Opener is {t[0]}. Then {t[1]}. Closer is {t[2]}."
    else:
        inp = f"{label}, {t[0]}, {t[1]}, and {t[2]}."
    return inp, f"{label}:\n" + ("\n".join(f"{i + 1}. {x}" for i, x in enumerate(t)) if style < 0.5 else "\n".join("- " + x for x in t))

ACRO = [("two SM58s", "three DIs", "an XLR snake"), ("a 4K monitor", "two HDMI cables", "a USB-C hub"), ("the PA", "two IEMs", "a DI"),
        ("an SSD", "the NAS", "two CAT6 cables"), ("a TRS cable", "the MIDI keyboard", "two LEDs"), ("an iPad", "the AirPods", "a MacBook")]
def gen_acronyms():
    items = list(random.choice(ACRO)); random.shuffle(items)
    label = random.choice(["Gear for Friday", "Order list", "Bring to the studio", "Pack for the tour"])
    return f"{label}: {items[0]}, {items[1]}, and {items[2]}.", f"{label}:\n" + "\n".join("- " + cap(x) for x in items)

REPL = [("eggs", "a dozen eggs"), ("bread", "two loaves of bread"), ("chips", "the big bag of chips"), ("wine", "two bottles of wine"),
        ("tape", "a roll of duct tape"), ("rice", "a bag of jasmine rice"), ("napkins", "the cloth napkins"), ("ice", "two bags of ice")]
OTHERS = ["butter", "salsa", "cheese", "plates", "apples", "soda", "cups", "lemons", "candles", "foil"]
def gen_list_replace():
    a, b = random.choice(REPL); o1, o2 = random.sample(OTHERS, 2)
    label = random.choice(["Shopping list", "Groceries", "Party list", "Store run"])
    cue = random.choice(["actually make that", "no, make that", "wait, make it", "actually"])
    if random.random() < 0.5:
        return f"{label}, {o1}, {a}, {cue} {b}, and {o2}.", f"{label}:\n- {cap(o1)}\n- {cap(b)}\n- {cap(o2)}"
    return f"{label}, {a}, {cue} {b}, {o1}, and {o2}.", f"{label}:\n- {cap(b)}\n- {cap(o1)}\n- {cap(o2)}"

GENS7 = [(gen_titles, 50), (gen_acronyms, 50), (gen_list_replace, 70)]

if __name__ == "__main__":
    rows = d5.build5()
    for g, n in d6.GENS6 + GENS7:
        for _ in range(n): rows.append(example(*g()))
    rows += [example(p, p) for p in KEEP_PLAIN] * 2
    d5.write(rows, "data7")
