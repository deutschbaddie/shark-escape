"""Run the real Creatures.luau (with mock.luau stand-ins) in the Luau CLI and
dump every block of every species as text for render.py."""
import os, re, subprocess, sys
ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "src", "shared")
LUAU = sys.argv[1] if len(sys.argv) > 1 else "luau"

def module(name):
    src = open(os.path.join(ROOT, name + ".luau")).read()
    src = re.sub(r"^export type", "type", src, flags=re.M)
    return f"MODULES.{name} = function()\nlocal script = {{ Parent = SHARED }}\n{src}\nend\n"

harness = open(os.path.join(os.path.dirname(__file__), "mock.luau")).read()
harness += """
MODULES = {}
local LOADED = {}
SHARED = setmetatable({}, { __index = function(_, k) return "mod:" .. k end })
local realRequire = require
function require(x)
	local name = x:sub(5)
	if LOADED[name] == nil then LOADED[name] = MODULES[name]() end
	return LOADED[name]
end
"""
for m in ("Config", "Build", "Creatures"):
    harness += module(m)
# optional: ZONES=Lagoon,Reef RARITIES=Mythic T=0.7 (pose every animated bit
# the way Animals.luau does at that time, to check nothing comes loose)
want_z = [z for z in os.environ.get("ZONES", "").split(",") if z]
want_r = [r for r in os.environ.get("RARITIES", "").split(",") if r]
anim = open(os.path.join(ROOT, "..", "client", "Animals.luau")).read()
moves = anim[anim.index("local A = CFrame.Angles"):anim.index("\n}\n", anim.index("local MOVES")) + 3]
moves = re.sub(r"local MOVES: [^=]*=", "local MOVES =", moves)
harness += moves
harness += f"""
local WANTZ = {{ {", ".join(repr(z) for z in want_z)} }}
local WANTR = {{ {", ".join(repr(r) for r in want_r)} }}
local T = {os.environ.get("T", "nil")}
"""
harness += """
local Config = require("mod:Config")
local Creatures = require("mod:Creatures")
for _, zone in Config.Zones do
	for _, r in Config.Rarities do
		if (#WANTZ > 0 and not table.find(WANTZ, zone.id)) or (#WANTR > 0 and not table.find(WANTR, r.id)) then
			continue
		end
		local m = Creatures.build(r.id, nil, 1, zone.id)
		if T then
			for _, p in m:GetDescendants() do
				local kind, rest = p:GetAttribute("Anim"), p:GetAttribute("Rest")
				local move = kind and MOVES[kind]
				if move and rest then
					local hinge = p:GetAttribute("Hinge") or Vector3.new(0, 0, 0)
					p.CFrame = CFrame.new(hinge) * move(T, p:GetAttribute("Side") or 1, p:GetAttribute("Phase") or 0) * CFrame.new(-hinge) * (rest.Rotation + rest.Position)
				elseif kind and not move then
					error("no move for " .. kind)
				end
			end
		end
		print("C", zone.id, r.id, m.Name)
		for _, p in m:GetDescendants() do
			if p.ClassName == "Part" and p.Transparency < 1 then
				local c, s, col = p.CFrame, p.Size, p.Color
				local r = c.r
				print("B", c.p.X, c.p.Y, c.p.Z, s.X, s.Y, s.Z, r[1][1], r[1][2], r[1][3], r[2][1], r[2][2], r[2][3], r[3][1], r[3][2], r[3][3],
					col.R, col.G, col.B, p.Transparency, p.Material.Name)
			end
		end
	end
end
"""
path = os.path.join(os.path.dirname(__file__), "build_harness.luau")
open(path, "w").write(harness)
out = subprocess.run([LUAU, path], capture_output=True, text=True)
if out.returncode != 0:
    print(out.stdout[-2000:], out.stderr[-3000:])
    sys.exit(1)
open(os.path.join(os.path.dirname(__file__), "creatures.txt"), "w").write(out.stdout)
print("dumped", out.stdout.count("\nC ") + out.stdout.startswith("C "), "creatures")
