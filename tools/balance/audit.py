"""Onboarding + progression audit: simulated players on the real numbers from
src/shared/Config.luau (rides, zones, rarities, sizes, tank slots, index
rewards, shark hunts every 80s, frenzy luck, offline earnings).

Two player profiles:
  ideal    - a great fit for the game (9-14, plays simulators, engaged,
             follows the arrow, hides or dodges sensibly)
  typical  - an average kid arriving from an ad (slower, wanders, AFKs a bit,
             gets eaten more)

It's a model, not playtest data. Use it to compare changes and to spot walls,
then replace the guesses with real analytics after launch.

    python3 tools/balance/audit.py          # prints the tables
    python3 tools/balance/audit.py --json   # machine-readable
"""
import json, math, random, statistics, sys

ZONES = [  # id, gate, length, value
    ("Lagoon", 0, 260, 1), ("Coral Reef", 100, 400, 5), ("Kelp Forest", 500, 560, 25),
    ("Shipwreck Bay", 1000, 720, 120), ("Deep Blue", 5000, 1000, 600), ("The Abyss", 25000, 1400, 3000),
]
RIDES = [(0, 1), (30, 2), (500, 3), (2500, 4), (10000, 5), (40000, 7), (160000, 9), (600000, 12),
         (2400000, 16), (9000000, 22), (35000000, 30), (130000000, 40)]
RIDE_NAMES = ["Pool Noodle", "Rubber Duck", "Inner Tube", "Boogie Board", "Surfboard", "Bathtub",
              "Banana Boat", "Jet Ski", "Speedboat", "Dolphin", "Giant Donut", "Rocket Surfboard"]
RAR = [("Common", 60, 1, 1), ("Uncommon", 25, 2.5, 2), ("Rare", 10, 6, 3), ("Epic", 4, 25, 4), ("Legendary", 1, 120, 5)]
SLOT_PRICES = [400, 2000, 8000, 30000, 120000, 500000, 2000000, 8000000]
LUCK, FRENZY_LUCK = 0.05, 0.30
REBIRTH = 25000
CYCLE, FIRST, WARN, HUNT = 80, 70, 5, 22
OFFLINE_RATE, OFFLINE_HOURS = 0.1, 8

PROFILES = {
    "ideal": dict(eff=1.35, idle=0.08, hide=0.55, eaten=0.10, first_catch=25, drill=22, drill_fail=0.15,
                  ride_walk=10, hunt_index=0.4),
    "typical": dict(eff=1.8, idle=0.22, hide=0.5, eaten=0.25, first_catch=50, drill=35, drill_fail=0.4,
                    ride_walk=18, hunt_index=0.2),
}


def real_speed(s):
    return min(16 + 9 * max(s, 0) ** (1 / 3), 320)


def zstart(i):
    return sum(z[2] for z in ZONES[:i])


def roll_size(rng):
    x = rng.random()
    if x < 0.008:
        return rng.uniform(2.0, 3.0)
    if x < 0.05:
        return rng.uniform(1.4, 1.9)
    return 0.75 + (rng.random() + rng.random()) / 2 * 0.55


def roll(rng, luck):
    r = rng.uniform(0, 100)
    i = 0
    for i, (_, w, _, _) in enumerate(RAR):
        r -= w
        if r <= 0:
            break
    if i < 4 and rng.random() < luck:
        i += 1
    return i


def index_reward(zi, ri):
    z, r = ZONES[zi], RAR[ri]
    return math.floor(5 * z[3] * r[2] ** 0.7), math.floor((5 + z[1] * 0.02) * r[3])


def in_hunt(t):
    """seconds of hunt left if t is inside a hunt (warning counts: you hide then)"""
    if t < FIRST:
        return 0
    k = (t - FIRST) % CYCLE
    return (WARN + HUNT - k) if k < WARN + HUNT else 0


def simulate(profile, seed, minutes, sessions=None):
    """sessions: list of (play_minutes, gap_hours) for returning players"""
    P = PROFILES[profile]
    rng = random.Random(seed)
    t = 0.0  # played seconds
    speed, coins, ride = 0.0, 0.0, 0
    rebirths = 0
    tank, slots, stored = [], 4, 0
    index, grabs = set(), 0
    ev = {}

    def mark(k):
        ev.setdefault(k, t)

    def income():
        return sum(tank)

    # ---------------- onboarding (guided, sharks off: 150s grace)
    t += P["first_catch"]
    speed += t  # +1/s on the noodle
    grabs += 1
    ri = 0
    tank.append(1 * 1.0)
    index.add((0, 0))
    c, s = index_reward(0, 0)
    coins += c
    speed += s
    mark("1. first catch")
    t += 12  # bring it home
    mark("2. in the tank")
    t += 6  # step on the pad
    coins += income() * 18
    mark("3. first cash")
    drill = P["drill"] * (2 if rng.random() < P["drill_fail"] else 1)
    t += drill
    mark("4. shark drill")
    # save up for the Duck by looping (counted in the main loop)

    session_ends = []
    if sessions:
        acc = 0
        for play, gap in sessions:
            acc += play * 60
            session_ends.append((acc, gap))
    end = sum(p for p, _ in sessions) * 60 if sessions else minutes * 60

    while t < end:
        # returning players: offline earnings between sessions
        while session_ends and t >= session_ends[0][0]:
            _, gap = session_ends.pop(0)
            coins += income() * OFFLINE_RATE * min(gap, OFFLINE_HOURS) * 3600
            mark("came back (offline cash)")
        zi = max(i for i, z in enumerate(ZONES) if speed >= z[1])
        if rebirths > 0 and rng.random() < P.get("hunt_index", 0.35):
            missing = [i for i in range(zi + 1) if any((i, r) not in index for r in range(5))]
            if missing:
                zi = rng.choice(missing)
        z = ZONES[zi]
        dist = 30 + (60 if zi == 0 else zstart(zi) + 60)
        trip = (2 * dist / real_speed(speed) + 4 + 3) * P["eff"]  # +grab/deposit +pad walk
        trip /= (1 - P["idle"])
        luck = LUCK
        eaten = False
        left = in_hunt(t + trip / 2) if t > 150 else 0
        if left:
            if rng.random() < P["hide"]:
                trip += left * 0.7  # wait it out on an island / the sand
            else:
                luck += FRENZY_LUCK  # stays out for the luckier grabs
                if rng.random() < P["eaten"]:
                    eaten = True
                    trip += 4
        speed += RIDES[ride][1] * (1.5 ** rebirths) * trip
        coins += income() * trip
        t += trip
        if eaten:
            mark("first time eaten")
            continue
        grabs += 1
        ri = roll(rng, luck)
        if grabs == 5 and ri < 2:
            ri = 2
        if grabs == 30 and ri < 3 and not any(r >= 3 for (_, r) in index):
            ri = 3
        if ri >= 2:
            mark("first Rare")
        if ri >= 3:
            mark("first Epic")
        if ri >= 4:
            mark("first Legendary")
        v = z[3] * RAR[ri][2] * math.sqrt(roll_size(rng))
        if len(tank) < slots:
            tank.append(v)
        else:
            w = min(tank)
            if v > w:
                tank[tank.index(w)] = v
            stored += 1
        if (zi, ri) not in index:
            index.add((zi, ri))
            c, s = index_reward(zi, ri)
            coins += c
            speed += s
            if len(index) == 30:
                mark("full Index (30/30)")
        while ride + 1 < len(RIDES) and coins >= RIDES[ride + 1][0]:
            coins -= RIDES[ride + 1][0]
            ride += 1
            t += P["ride_walk"]
            mark(f"ride {ride + 1:2d}: {RIDE_NAMES[ride]}")
            if ride == 1:
                mark("5. onboarding done (Duck)")
        bought = slots - 4
        if bought < len(SLOT_PRICES) and coins >= SLOT_PRICES[bought] * 1.5:
            coins -= SLOT_PRICES[bought]
            slots += 1
            mark(f"tank slot {slots}")
        for i, zz in enumerate(ZONES):
            if speed >= zz[1] and i > 0:
                mark(f"zone: {zz[0]}")
        if speed >= REBIRTH and ride == len(RIDES) - 1:
            mark("rebirth ready" if rebirths == 0 else f"rebirth {rebirths + 1} ready")
            if rebirths < 5:
                rebirths += 1
                mark(f"rebirth {rebirths}")
                speed, coins, ride = 0.0, 0.0, 0
        # Index hunting: once you've seen the Abyss, some trips go back to
        # older zones for the Legendaries you're missing
        if len(index) >= 15:
            mark(f"Index half (15/30)")
    return ev


def fmt(sec):
    if sec >= 3600:
        return f"{sec / 3600:.1f} h"
    return f"{int(sec // 60)}:{int(sec % 60):02d}"


def table(profile, minutes=600, n=300, sessions=None):
    runs = [simulate(profile, s, minutes, sessions) for s in range(n)]
    keys = sorted({k for r in runs for k in r}, key=lambda k: statistics.median(r[k] for r in runs if k in r))
    rows = []
    for k in keys:
        vals = sorted(r[k] for r in runs if k in r)
        q = lambda p: vals[min(len(vals) - 1, int(p * len(vals)))]
        rows.append({"milestone": k, "median": statistics.median(vals), "p10": q(0.1), "p90": q(0.9), "share": len(vals) / n})
    return rows


if __name__ == "__main__":
    out = {}
    for prof in ("ideal", "typical"):
        out[prof] = table(prof)
    # returning player: 3 days, 25 min a day
    out["ideal_3days"] = table("ideal", sessions=[(25, 20), (25, 20), (25, 20)])
    if "--json" in sys.argv:
        print(json.dumps(out))
    else:
        for name, rows in out.items():
            print(f"\n== {name}")
            print(f"{'milestone':34} {'median':>8} {'p10':>8} {'p90':>8}  reached")
            for r in rows:
                print(f"{r['milestone']:34} {fmt(r['median']):>8} {fmt(r['p10']):>8} {fmt(r['p90']):>8}  {r['share'] * 100:5.0f}%")
