"""Pacing sim for a typical (non-paying) player, using the numbers in
src/shared/Config.luau. A rough model, not a promise: tune by playtesting.

Model: the player loops dock -> best unlocked zone -> grab -> dock, collects
the pad every trip, buys the next ride as soon as it can (walk to the Ride
Shop costs a few seconds), claims Index rewards, buys tank slots when cheap,
and loses ~15% of time to shark attacks (hiding on islands).
"""
import math, random, statistics

ZONES = [  # id, gate, length, value
    ("Lagoon", 0, 260, 1), ("Reef", 100, 400, 5), ("Kelp", 500, 560, 25),
    ("Shipwreck", 1000, 720, 120), ("Deep", 5000, 1000, 600), ("Abyss", 25000, 1400, 3000),
]
RIDES = [(0, 1), (25, 2), (85, 3), (300, 4), (1000, 5), (3300, 7), (11000, 9), (38000, 12),
         (130000, 16), (450000, 22), (1500000, 30), (5000000, 40)]
RAR = [("Common", 60, 1, 1), ("Uncommon", 25, 3, 2), ("Rare", 10, 10, 3), ("Epic", 4, 40, 4), ("Legendary", 1, 200, 5)]
SLOT_PRICES = [250, 1000, 4000, 15000, 60000, 250000, 1000000, 4000000]
LUCK = 0.05
REBIRTH = 25000


def real_speed(s):
    return min(16 + 9 * max(s, 0) ** (1 / 3), 320)


def zstart(i):
    return sum(z[2] for z in ZONES[:i])


def roll(rng):
    r = rng.uniform(0, 100)
    for i, (name, w, mult, idx) in enumerate(RAR):
        r -= w
        if r <= 0:
            break
    if i < 4 and rng.random() < LUCK:
        i += 1
    return i


def index_reward(zv, ri):
    mult, idx = RAR[ri][2], RAR[ri][3]
    gate = next(z[1] for z in ZONES if z[3] == zv)
    return math.floor(20 * zv * mult ** 0.75), math.floor((5 + gate * 0.02) * idx)


def run(seed, minutes=40):
    rng = random.Random(seed)
    t, speed, coins, gain_i = 0.0, 0.0, 0.0, 0
    tank, slots, grabs = [], 4, 0
    index = set()
    events = {}

    def mark(k):
        events.setdefault(k, t)

    while t < minutes * 60:
        zi = max(i for i, z in enumerate(ZONES) if speed >= z[1])
        z = ZONES[zi]
        # go a bit into the zone (lagoon bubbles are close to shore)
        dist = 30 + (60 if zi == 0 else zstart(zi) + 50)
        trip = (2 * dist / real_speed(speed) + 5) / 0.85  # 15% lost to sharks
        income = sum(tank)
        speed += RIDES[gain_i][1] * trip
        coins += income * trip
        t += trip
        grabs += 1
        ri = roll(rng)
        if grabs == 3 and ri < 2:
            ri = 2
        if ri >= 2:
            mark("first Rare")
        if ri >= 3:
            mark("first Epic")
        v = z[3] * RAR[ri][2]
        if len(tank) < slots:
            tank.append(v)
        else:
            w = min(tank)
            if v > w:
                coins += w * 20
                tank[tank.index(w)] = v
            else:
                coins += v * 20
        if (zi, ri) not in index:
            index.add((zi, ri))
            c, s = index_reward(z[3], ri)
            coins += c
            speed += s
        # spend: next ride first, then a slot if it's cheap relative to coins
        while gain_i + 1 < len(RIDES) and coins >= RIDES[gain_i + 1][0]:
            coins -= RIDES[gain_i + 1][0]
            gain_i += 1
            t += 6  # walk to the Ride Shop
            mark(f"ride {gain_i + 1}")
            if gain_i == 1:
                mark("first upgrade (Duck)")
        bought = slots - 4
        if bought < len(SLOT_PRICES) and coins >= SLOT_PRICES[bought] * 1.5:
            coins -= SLOT_PRICES[bought]
            slots += 1
        for i, zz in enumerate(ZONES):
            if speed >= zz[1] and i > 0:
                mark(f"unlock {zz[0]} ({zz[1]})")
        if speed >= REBIRTH:
            mark("rebirth ready")
    return events


def fmt(sec):
    return f"{int(sec // 60)}:{int(sec % 60):02d}"


if __name__ == "__main__":
    runs = [run(s) for s in range(200)]
    keys = sorted({k for r in runs for k in r}, key=lambda k: statistics.median(r[k] for r in runs if k in r))
    print(f"{'milestone':28} {'median':>7} {'p10':>7} {'p90':>7}  reached")
    for k in keys:
        vals = sorted(r[k] for r in runs if k in r)
        p = lambda q: vals[min(len(vals) - 1, int(q * len(vals)))]
        print(f"{k:28} {fmt(statistics.median(vals)):>7} {fmt(p(0.1)):>7} {fmt(p(0.9)):>7}  {len(vals)}/200")
