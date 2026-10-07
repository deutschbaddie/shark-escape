# +1 Speed to Escape the Shark

Rojo project. Untested in Studio so far.

## Run
1. `rojo serve` in this folder, then connect from the Rojo plugin in Studio.
2. Game Settings: Avatar = R15 (the surf pose needs R15). Lighting.Technology = Future.
3. Turn on Studio API access to DataStores if you want saves to work in Studio.

## Sharks (rigged, hand-built)
- `python3 tools/shark_gen.py` writes `assets/sharks/Shark*.glb` (6 variants, 9 bones each).
- Preview: open `tools/preview.html` through a local server (`python3 -m http.server 8765 --directory tools`).
- In Studio: Import 3D on each .glb, then move the models into `ReplicatedStorage/Assets/Sharks`,
  named `SharkBaby`, `SharkHammerhead`, `SharkTiger`, `SharkGreatWhite`, `SharkMecha`, `SharkMegalodon`.
- Until they're imported, the game uses a part-built fallback shark.

## Before publishing
- Create the gamepasses and dev products and put their ids in `src/shared/Config.luau` (0 means "Soon").
- Choose sounds from the Creator Store and put their ids in `Config.Sounds`. Record every asset id in ASSETS.md.

## Onboarding
`src/client/Onboarding.luau` walks new players through 5 steps with a 3D guide beam:
grab a bubble -> bring it to your dock -> collect coins on the pad -> shark drill
(a harmless, slower client-only shark chases you back to sand/island) -> buy the Rubber Duck.
Progress is saved as `profile.tut`; finishing it ends the new-player shark grace early.

## Not done yet
- Playtest and balance pass.
