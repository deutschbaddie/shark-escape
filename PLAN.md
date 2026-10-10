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
  shows up later (offers after 10 min, raids after 10 min).
- **Playtest every phase** with 2+ players on a phone before moving on.

## Phase 0: stop the bleeding
- [x] Save protection (session locking)
- [x] Hide Robux offers for the first 10 minutes
- [x] Bug sweep of everything since worlds (review running) and fixes
- [x] Performance pass for cheap phones: "Fewer details" (Settings, on for
      phones) keeps studs on top faces only. Owner: keep StreamingEnabled on
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
- [x] Prize aggro: grabbing a Legendary or Mythic sets its shark on you
      (replaced the Legendary reel minigame: too hard on phones)
- [x] Stealing too deep: every zone shark on the way home comes for you
- [x] Day / night (night = everyone hunted, luckier; dawn resets)

## Phase 2: make players matter to each other (1-2 weeks)
- [x] Chum / Send Shark (cut in update 0: bonk does that job)
- [x] Raids: time at their tank while they're at sea; they rush home to stop it
- [x] Raid spin: a strip of their creatures rolls to the one you take, each
      card showing its chance (Mythic possible, rarely)
- [x] Raid loot walk: carry it home in forced slow mode; anyone can bonk it
      loose on the way
- [x] Obvious raid safety: a shield shimmers over your tank while you're on
      the beach; signs say "Owner is home: safe from raids" / "Can be raided
      while you're out"; one heads-up when you leave / come home
- [x] Tank Lock (Robux product): no raids for 30 min (needs a product id)
- [x] Server-wide announcements for Mythic catches only (Legendary ones
      were too much chatter)
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
      dodges, rings, night catches; cash each, Luck Potion for all 3)
- [x] Speed feel past the cap (wider FOV, stronger lines, wind)
- [x] Onboarding teaches night + grudges in one line each (no new steps)
- [x] Analytics: raids (start / defended / stolen / loot home / lost),
      close calls, Mythic catches, Megalodon Hour joins
- [ ] Rename + thumbnail around the shark and raids (owner)
- [ ] 10-15 short clips: close calls, bonks, raids (owner)
- [ ] Small ad test, read the funnels, fix the biggest drop, then scale (owner)

## Phase 5: fun pass (the hook)
**Grab creatures, and the more you carry, the more fins follow you.
Make it back to the sand for a big payout.**
- [x] Fins follow your haul (replaced the shared hunger bar, which was hard
      to read): what you carry draws fins that circle you; a big haul makes
      them close in and one charges
- [x] Visible haul: the net's catches trail behind you in bubbles
- [x] Haul bonus: the dock pays cash for a trip at once, x1.25 per extra
      creature (up to x3), counting up over your tank. Nets hold more
      (Bare Hands 2 ... Mega Net 12)
- [x] The escape: hit the sand with your shark right behind you, it snaps
      at the waterline (slow-mo, splash wall) and you get +speed
- [x] Bites spill your haul as bubbles anyone can grab for 40 s
- [x] First 2 minutes: first grab in 15 s, a scripted first chase you
      always escape, the Rubber Duck in ~90 s
- [x] Fewer buttons at the start (3), the rest appear when they matter
- [x] Cut / merge: no Lucky Storm, no ring chains, chests wash up at dawn,
      raids after the first evolve
- [x] Zone unlock is a physical moment (buoys light up, water shifts)
- [x] Playtest checklist (below)

## Phase 6: players are the content (front-page audit)
- [x] Noodle Bonk: bonk riders to knock their loot loose, bonk sharks to
      daze them. At sea only; new players protected; procedural swing
- [x] Top Bonkers board
- [x] A server event every 15 min: Golden Tide, Feeding Frenzy, Bubble Rain
- [x] Your best creature floats huge over your dock
- [x] Invite a friend: you both get a Rare
- [x] Noodle upgrades (coins) + Golden Noodle (pass: needs its id)
- [x] Quests and analytics for all of it
- [ ] Trading (once sessions hold 20+ minutes)
- [ ] Playtest the bonk with real kids: funny or mean? Tune immune / cooldown

## Update 0 (one sea)
- [x] Evolve: one sea of 15 biomes; the first evolve at 3K speed, each
      evolve opens the next biome past Deep Blue (Candy Bay merged in)
- [x] Mythic rarity: 15 creatures with their own bodies and auras
- [x] Candy rides: 5 late-game rides as the cash sink from hour 3
- [x] Megalodon boss in zone 4 with a real aimed charge
- [x] System audit: purchases, saving, sharks, bonk, rewards, UI, perf

### Playtest checklist (3-5 people, phones, 15 minutes, watch, don't help)
- [ ] First grab within 15 s of spawning?
- [ ] Did anyone yell or laugh in the first 2 minutes (the practice chase,
      the snap at the waterline)?
- [ ] Rubber Duck bought within ~90 s?
- [ ] Ask after 5 min: "what's the game?" Can they say it in one sentence
      (grab, carry, don't get eaten)?
- [ ] Do they go for a second creature before heading home (the haul)?
      Do they notice the fins gathering before grabbing more?
- [ ] Did a spilled haul cause a scramble?
- [ ] Did anyone say "one more trip"?
- [ ] Anything they tapped that did nothing, or asked "what's this"? Write
      it down: that's the next fix.
- [ ] After: Analytics custom events Escaped / Haul / CloseCall, and the
      onboarding funnel. Fix the biggest drop first.

## Needs from the owner
- Product id for the **Small Cash Pack** (MoneyPack1): the id sent was the Cash Pack's
- Zone icons for the deep and candy biomes
- Test the boss with `/boss` (and the whole event with `/event`) on a live server
- Sound ids: thunder, chest open, boss roar
- Badge ids if you want badges
