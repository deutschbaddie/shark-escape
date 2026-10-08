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
harness += """
local Config = require("mod:Config")
local Creatures = require("mod:Creatures")
for _, zone in Config.Zones do
	for _, r in Config.Rarities do
		local m = Creatures.build(r.id, nil, 1, zone.id)
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
