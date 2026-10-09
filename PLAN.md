# The plan

The game's promise is in its name: escape the shark. Everything below
serves that, in this order. `[x]` = built (not yet playtested), `[ ]` = to do.

## Rules we stick to
- **The shark is the game.** Every system should make the sea scarier or the
  escape better. If a feature doesn't, it waits.
- **No shouty center words.** No slanted / bouncing "WORD!" popups anywhere.
  Moments are plain notifications (top banners, toasts), or a unique
  physical effect (the shark jaws, the red edge glow). Never a big tilted word.
- **New players see 3 things first:** ride, catch, shark. Everything else
  shows up later (offers after 10 min, raids/chum after 10 min).
- **Playtest every phase** with 2+ players on a phone before moving on.

## Phase 0: stop the bleeding
- [x] Save protection (session locking)
- [x] Hide Robux offers for the first 10 minutes
- [x] Bug sweep of everything since worlds (review running) and fixes
- [ ] Performance pass for cheap phones (stud textures, World 2 detail)
- [x] Remove every shouty center word (Notify.word / takeover / Fx.bigWord)

## Phase 1: make the shark the game (1 week)
- [x] **No boundaries.** No gate walls: ride as far as you dare. Each zone has
      a *recommended speed*; below it, that zone's shark hunts you the whole
      time you're there (day or night). You can go; you just won't make it back.
- [x] Chase loop: deeper = worth more (each zone x5) and meaner sharks (aggro)
- [x] Deeper = the grudge chance grows with depth too
- [x] Ride-over grabs (Common to Rare)
- [x] Grabbing makes noise: the zone's shark may come for you (grudge)
- [x] Close call reward (+speed)
- [x] Near-miss slow-mo feel (blur, desaturate, FOV punch, heartbeat)
- [x] Legendary reel: grabbing a Legendary starts a timing minigame while
      its shark charges; miss and it slips away
- [x] Day / night (night = everyone hunted, luckier; dawn resets)

## Phase 2: make players matter to each other (1-2 weeks)
- [x] Chum: throw at a nearby rider, their shark comes for them (cooldown)
- [x] A Shark Shield blocks chum (and is used up)
- [x] Raids: 35 s at their tank while they're at sea; they rush home to stop it
- [x] Tank Lock (Robux product): no raids for 30 min (needs a product id)
- [x] Server-wide announcements for Legendary / Huge catches
- [x] A light beam over the catcher's dock for a minute

## Phase 3: reasons to come back at set times (ongoing)
- [x] Megalodon Hour every Saturday 3 PM ET + plaza countdown board
- [x] Make it x3 luck and add the **boss Megalodon** the whole server fights
      with harpoons; everyone who hit it gets a Legendary
- [x] Limited catches: a weekly limited mutation (Spooky, Toxic, Molten,
      Frozen, Galaxy, rotating every Monday) only catchable during its week,
      shown on the plaza board
- [x] Codes: a new code at every like milestone ("New code at 1K likes" on the
      board and the codes card). Owner: add the code + raise `Config.LikeGoal`

## Phase 4: added
- [x] Daily quests (3 a day from a pool of 7: Rares, bring home, close calls,
      dodges, rings, night catches, chum; cash each, Luck Potion for all 3)
- [x] Speed feel past the cap (wider FOV, stronger lines, wind)
- [x] Onboarding teaches night + grudges in one line each (no new steps)
- [x] Analytics: log chum, raids (start / defended / stolen), close calls,
      Megalodon Hour joins, Legendary reel success rate
- [ ] Rename + thumbnail around the shark, chum and raids (owner)
- [ ] 10-15 short clips: close calls, chum betrayals, raids (owner)
- [ ] Small ad test, read the funnels, fix the biggest drop, then scale (owner)

## Needs from the owner
- Product id for **Tank Lock** (and MoneyPack1, still missing)
- Zone icons for the 3 new Shark Beach zones and the 6 Candy Bay zones
- Test the boss with `/boss` (and the whole event with `/event`) on a live server
- Sound ids: thunder, portal whoosh, chest open, boss roar, reel click
- Badge ids if you want badges
