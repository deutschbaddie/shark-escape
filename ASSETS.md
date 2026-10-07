# Assets

Every asset the game uses, with its id and source. Never add an id that hasn't been checked.

| What | Id | Source | Where it's used |
|---|---|---|---|
| Stud texture (image) | `rbxassetid://6927295847` | "Studs" by aetoreous, Creator Store decal 6927295857, public domain | `Config.Images.Studs`: UI panels and buttons, and stud textures on parts |
| Icon sheet A | _upload_ `assets/icons/IconsA.png` | Made for this game (`tools/icons/make_icons.py`) | `Config.Icons.SheetA` |
| Icon sheet B | _upload_ `assets/icons/IconsB.png` | Made for this game | `Config.Icons.SheetB` |
| Sharks ×6 | _import_ `assets/sharks/*.glb` | Made for this game (`tools/shark_gen.py`) | `ReplicatedStorage/Assets/Sharks` |
| Game icon / thumbnail | _upload_ `assets/store/*.png` | Made for this game (`tools/icons/make_store_art.py`) | Experience settings |
| Sounds | `rbxasset://sounds/impact_water.mp3`, `action_swim.mp3`, `impact_explosion_03.mp3`, `electronicpingshort.wav` | Built into the Roblox client | `Config.Sounds` |

Still to choose from the Creator Store (record the ids here): music, shark alarm, legendary jingle.
