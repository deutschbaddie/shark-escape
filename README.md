# +1 Speed to Escape the Shark

Rojo project. Untested in Studio so far.

## Run in Studio
Pick one:
- **Sync into your place (recommended):** run `rojo serve` in this folder, open your place in Studio,
  then click Connect in the Rojo plugin. Your imported sharks in `ReplicatedStorage/Assets` stay put.
  Rojo replaces the `Shared`, `Server` and `Client` folders with this repo's version.
- **Fresh place:** `rojo build -o SharkEscape.rbxlx` and open the file. It starts from an empty
  baseplate; the server builds the whole map when you press Play.

Then: Game Settings > Avatar = R15 (the surf pose needs R15), and turn on Studio access to API
services if you want saves to work in Studio.

## Sharks (rigged, hand-built)
- `python3 tools/shark_gen.py` writes `assets/sharks/Shark*.glb` (6 variants, 9 bones each).
- Preview: open `tools/preview.html` through a local server (`python3 -m http.server 8765 --directory tools`).
- In Studio: Import 3D on each .glb, then move the models into `ReplicatedStorage/Assets/Sharks`,
  named `SharkBaby`, `SharkHammerhead`, `SharkTiger`, `SharkGreatWhite`, `SharkMecha`, `SharkMegalodon`.
- Until they're imported, the game uses a part-built fallback shark.

## Before publishing
- Create the gamepasses and dev products and put their ids in `src/shared/Config.luau` (0 means "Soon").
- Choose sounds from the Creator Store and put their ids in `Config.Sounds`. Record every asset id in ASSETS.md.

## Look
- Studded simulator style: checkered stud walls with a grass topper down both sides of the ocean
  lane, a studded grass plaza, small shop huts (step on the glowing pad to open them), a FASTEST
  leaderboard board, blocky studded islands. Signs are sized in studs so they shrink with distance.
- UI kit (`src/client/UI.luau`): studded gradient buttons with thick outlines, dark windows with a
  studded header and red X, red "!" badges. Studs are drawn procedurally; for a crisper look upload
  `assets/textures/studs.png` as a decal and put its id in `Config.Images.Studs`.

## Features
- Onboarding (`Onboarding.luau`): grab a bubble -> dock -> collect pad -> practice shark -> first ride.
- Creature Index (`Index.luau`): 6 zones x 5 rarities, ??? silhouettes, one-time rewards, CLAIM ALL.
- Welcome Back (`Hub.luau`): the tank earns 50% while you're offline (max 6h), claim on join.
- Shark timer, zone title pop-ups, distance meter, offer banner (only once the shop unlocks).

## Not done yet
- Playtest and balance pass.
- Sounds and Robux ids in `Config.luau` (empty / 0 = hidden).
