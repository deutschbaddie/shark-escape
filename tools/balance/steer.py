"""Ride steering check: runs the real Ride.steer (src/client/Ride.luau) in the
Luau CLI and compares it with the old controller: U-turns at full speed,
turning around from a stop (reverse + J-turn), a tap of reverse, and a
90-degree carve.

    python3 tools/balance/steer.py path/to/luau
"""
import os, re, subprocess, sys

SCENARIOS = r"""
-- old controller (before this change) for comparison
local function oldSteer(st, input, v, feel, top, dt)
	local m = math.min(input.Magnitude, 1)
	if m > 0.05 then st.heading = turnToward(st.heading, yawOf(input), feel.turn * dt) end
	local h = st.heading
	local fwd = Vector3.new(-math.sin(h), 0, -math.cos(h))
	local side = Vector3.new(math.cos(h), 0, -math.sin(h))
	local vf, vs = v:Dot(fwd), v:Dot(side)
	local align = m > 0.05 and math.clamp(input.Unit:Dot(fwd) * 0.5 + 0.5, 0, 1) or 0
	local target = top * m * align
	local rate = (target > vf) and (top / feel.accel) or (top / feel.coast)
	vf = approach(vf, target, rate * dt)
	vs *= math.exp(-feel.grip * dt)
	return fwd * vf + side * vs
end

local DT = 1 / 60
local function run(kind, rideId, top, v0, inputFn, T)
	local feel = Config.RideFeel[rideId]
	local st = { heading = 0, whip = false, launch = 0, reverse = 0 }
	local v = Vector3.new(0, 0, -v0)
	local p = Vector3.zero
	local t = 0
	local out = { minZ = 0, maxX = 0, t90 = nil, back = 0 }
	while t < T do
		local input, mv = inputFn(t)
		if kind == "new" then
			v = (Ride.steer(st, input, mv, v, feel, top, DT))
		else
			v = oldSteer(st, input, v, feel, top, DT)
		end
		p += v * DT
		t += DT
		out.minZ = math.min(out.minZ, p.Z)
		out.maxX = math.max(out.maxX, math.abs(p.X))
		if not out.t90 and v.Z > top * 0.9 then out.t90 = t end
		out.back = math.max(out.back, p.Z)
	end
	out.p = p
	return out
end
local back = function() return Vector3.new(0, 0, 1), Vector3.new(0, 0, 1) end
local right = function() return Vector3.new(1, 0, 0), Vector3.new(1, 0, 0) end
print("U-TURN at full speed (press back): time to 90% speed the other way | how far it overshoots | how wide")
for _, top in { 40, 200 } do
	for _, id in { "Noodle", "Bathtub", "Banana", "JetSki", "Dolphin", "Rocket" } do
		local o = run("old", id, top, top, back, 6)
		local n = run("new", id, top, top, back, 6)
		print(string.format("  top %3d %-8s old: %5s s, overshoot %5.1f, wide %5.1f   new: %5s s, overshoot %5.1f, wide %5.1f", top, id,
			o.t90 and string.format("%.2f", o.t90) or ">6", -o.minZ, o.maxX, n.t90 and string.format("%.2f", n.t90) or ">6", -n.minZ, n.maxX))
	end
end
print("FROM A STOP (hold back): reverse then J-turn")
for _, top in { 40, 200 } do
	for _, id in { "Bathtub", "JetSki", "Dolphin" } do
		local o = run("old", id, top, 0, back, 6)
		local n = run("new", id, top, 0, back, 6)
		print(string.format("  top %3d %-8s old: 90%% at %5s s   new: 90%% at %5s s (backs up %.1f studs before the swing)", top, id,
			o.t90 and string.format("%.2f", o.t90) or ">6", n.t90 and string.format("%.2f", n.t90) or ">6", run("new", id, top, 0, back, 0.4).back))
	end
end
print("TAP back 0.25 s from a stop (reverse gear)")
for _, id in { "Bathtub", "JetSki" } do
	local n = run("new", id, 40, 0, function(t) if t < 0.25 then return back() end return Vector3.zero, nil end, 2)
	print(string.format("  %-8s moved back %.1f studs, sideways %.1f", id, n.p.Z, math.abs(n.p.X)))
end
print("90-degree turn at full speed: how far forward before it's heading right")
for _, top in { 200 } do
	for _, id in { "Bathtub", "Banana", "JetSki" } do
		local o = run("old", id, top, top, right, 3)
		local n = run("new", id, top, top, right, 3)
		print(string.format("  %-8s old: forward %.1f   new: forward %.1f", id, -o.minZ, -n.minZ))
	end
end

"""

HERE = os.path.dirname(__file__)
SRC = os.path.join(HERE, "..", "..", "src")
LUAU = sys.argv[1] if len(sys.argv) > 1 else "luau"

mock = open(os.path.join(HERE, "..", "preview", "mock.luau")).read()
cfg = re.sub(r"^export type", "type", open(os.path.join(SRC, "shared", "Config.luau")).read(), flags=re.M)
ride = re.sub(r"^export type", "type", open(os.path.join(SRC, "client", "Ride.luau")).read(), flags=re.M)
consts = ride[ride.index("-- steering tuning"):ride.index("local steerState")]
helpers = ride[ride.index("local function yawOf"):ride.index("-" * 65 + " animation on/off")]
helpers = helpers.replace("feel: Config.RideFeel", "feel: any")
harness = (mock + "\nlocal Config = (function()\nlocal script={Parent={}}\n" + cfg.replace("require(", "(function() return {} end)(")
           + "\nend)()\nlocal Ride = {}\n" + consts + "\n" + helpers + SCENARIOS)
path = os.path.join(HERE, "steer_harness.luau")
open(path, "w").write(harness)
out = subprocess.run([LUAU, path], capture_output=True, text=True)
os.remove(path)
print(out.stdout, out.stderr)
