"""Check the in-game sound setup (src/shared/Config.luau):
every slot's file is listed in Config.SoundFiles, layers / every / fallback
point at real slots, Config.RideSound loops exist, and (given the folder of
the original files) every from/to/loop fits inside its file.

    python3 tools/audio/check.py path/to/luau [folder-with-the-sound-files]

Needs ffprobe for the length check. Prints which files still need an id.
"""
import glob, json, os, re, subprocess, sys, tempfile

HERE = os.path.dirname(__file__)
SRC = os.path.join(HERE, "..", "..", "src", "shared")
LUAU = sys.argv[1] if len(sys.argv) > 1 else "luau"
RAW = sys.argv[2] if len(sys.argv) > 2 else None

mock = open(os.path.join(HERE, "..", "preview", "mock.luau")).read()
cfg = re.sub(r"^export type", "type", open(os.path.join(SRC, "Config.luau")).read(), flags=re.M)
dump = r'''
local function enc(v)
	local t = typeof(v)
	if t == "string" then return string.format("%q", v)
	elseif t == "number" or t == "boolean" then return tostring(v)
	elseif t == "table" then
		local parts, isArr = {}, #v > 0
		if isArr then for _, x in v do table.insert(parts, enc(x)) end return "[" .. table.concat(parts, ",") .. "]" end
		for k, x in v do table.insert(parts, string.format("%q", tostring(k)) .. ":" .. enc(x)) end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end
print(enc({ files = Config.SoundFiles, slots = Config.SoundSlots, rides = Config.RideSound, sounds = Config.Sounds }))
'''
harness = mock + "\nlocal Config = (function()\nlocal script={Parent={}}\n" + cfg.replace("require(", "(function() return {} end)(") + "\nend)()\n" + dump
with tempfile.TemporaryDirectory() as tmp:
    path = os.path.join(tmp, "audio_check.luau")
    open(path, "w").write(harness)
    out = subprocess.run([LUAU, path], capture_output=True, text=True)
if out.returncode != 0:
    print(out.stderr[-2000:])
    sys.exit(1)
data = json.loads(out.stdout.strip().splitlines()[-1].replace("\\\n", "\\n"))
files, slots, rides = data["files"], data["slots"], data["rides"]
problems = []
for name, s in slots.items():
    if s["file"] not in files:
        problems.append(f"{name}: file {s['file']} is not in Config.SoundFiles")
    for ref in (s.get("layers") or []) + ([s["every"][0]] if s.get("every") else []) + ([s["fallback"]] if s.get("fallback") else []):
        if ref not in slots and ref not in data["sounds"]:
            problems.append(f"{name}: refers to unknown sound {ref}")
for ride, spec in rides.items():
    if spec[0] not in slots:
        problems.append(f"ride {ride}: loop {spec[0]} is not a slot")
lengths = {}
if RAW:
    for f in files:
        found = glob.glob(os.path.join(RAW, f + ".*"))
        if not found:
            problems.append(f"file {f} not found in {RAW}")
            continue
        p = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", found[0]], capture_output=True, text=True)
        lengths[f] = float(p.stdout.strip())
    for name, s in slots.items():
        L = lengths.get(s["file"])
        if L is None:
            continue
        for key in ("from", "to"):
            if key in s and not (0 <= s[key] <= L + 1e-3):
                problems.append(f"{name}: {key}={s[key]} is outside the file (0..{L:.2f})")
        if "loop" in s and not (0 <= s["loop"][0] < s["loop"][1] <= L + 1e-3):
            problems.append(f"{name}: loop {s['loop']} is outside the file (0..{L:.2f})")
used = {s["file"] for s in slots.values()}
for f in files:
    if f not in used:
        problems.append(f"file {f} isn't used by any slot")
missing = [f for f, v in files.items() if not v]
print(f"{len(slots)} sounds from {len(files)} files" + (f", lengths checked against {RAW}" if RAW else ""))
print("problems:" if problems else "no problems", *problems, sep="\n  ")
print(f"{len(missing)} files still need a Roblox id" + (":" if missing else ""), *missing, sep="\n  ")
