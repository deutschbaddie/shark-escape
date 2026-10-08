"""Upload the original sound files to Roblox in one go and write each new id
into Config.SoundFiles (src/shared/Config.luau). Files are uploaded exactly as
they are; every edit happens in the game (Config.SoundSlots).

    python3 tools/audio/upload.py --key YOUR_API_KEY --group 902411651 --dir ~/Downloads
    python3 tools/audio/upload.py --key YOUR_API_KEY --user YOUR_USER_ID --dir ~/Downloads

Upload as whoever owns the game (the group, or you): Roblox only lets a game
play audio its owner uploaded. The API key comes from Creator Dashboard ->
Open Cloud -> API Keys: add the "Assets" API with Read + Write (and, for
--group, create it as / for the group). Only the Python standard library.

  --dry-run    show what would be uploaded, upload nothing
  --only a,b   just these files (names as in Config.SoundFiles)
Files that already have an id are skipped, and Config.luau is saved after
every upload, so it's safe to run again after an error or a quota limit
(10 audio uploads a month without ID verification, 100 with it).
"""
import argparse, glob, json, os, re, sys, time, urllib.error, urllib.request, uuid

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.path.join(HERE, "..", "..", "src", "shared", "Config.luau")
API = os.environ.get("ROBLOX_API_BASE", "https://apis.roblox.com")
TYPES = {".wav": "audio/wav", ".flac": "audio/flac", ".ogg": "audio/ogg", ".mp3": "audio/mpeg"}
LINE = re.compile(r'^(\s*\["(?P<name>[^"]+)"\]\s*=\s*")(?P<id>[^"]*)(",.*)$')


def sound_files(text):
    """name -> id for every entry in the Config.SoundFiles table"""
    start = text.index("Config.SoundFiles = {")
    end = text.index("\n}", start)
    out = {}
    for line in text[start:end].splitlines():
        m = LINE.match(line)
        if m:
            out[m["name"]] = m["id"]
    return out


def write_id(name, asset_id):
    text = open(CONFIG, encoding="utf-8").read()
    start = text.index("Config.SoundFiles = {")
    end = text.index("\n}", start)
    lines = text[start:end].splitlines()
    for i, line in enumerate(lines):
        m = LINE.match(line)
        if m and m["name"] == name:
            lines[i] = f'{m.group(1)}rbxassetid://{asset_id}{m.group(4)}'
    text = text[:start] + "\n".join(lines) + text[end:]
    open(CONFIG, "w", encoding="utf-8").write(text)


def request(method, url, key, body=None, ctype=None):
    req = urllib.request.Request(url, data=body, method=method, headers={"x-api-key": key})
    if ctype:
        req.add_header("Content-Type", ctype)
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.loads(r.read() or b"{}")
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "replace")[:400]
            if e.code == 429 or e.code >= 500:
                wait = 2 ** attempt * 2
                print(f"    {e.code}, retrying in {wait}s")
                time.sleep(wait)
                continue
            raise RuntimeError(f"HTTP {e.code}: {detail}") from None
    raise RuntimeError("gave up after retries")


def upload(path, name, key, creator):
    meta = {
        "assetType": "Audio",
        "displayName": name[:50],
        "description": "Sound for +1 Speed to Escape the Shark",
        "creationContext": {"creator": creator},
    }
    boundary = uuid.uuid4().hex
    data = open(path, "rb").read()
    ctype = TYPES[os.path.splitext(path)[1].lower()]
    body = (
        f'--{boundary}\r\nContent-Disposition: form-data; name="request"\r\n\r\n{json.dumps(meta)}\r\n'
        f'--{boundary}\r\nContent-Disposition: form-data; name="fileContent"; filename="{os.path.basename(path)}"\r\n'
        f"Content-Type: {ctype}\r\n\r\n"
    ).encode() + data + f"\r\n--{boundary}--\r\n".encode()
    op = request("POST", f"{API}/assets/v1/assets", key, body, f"multipart/form-data; boundary={boundary}")
    op_id = op.get("operationId") or op.get("path", "").split("/")[-1]
    for _ in range(60):
        if op.get("done"):
            break
        time.sleep(2)
        op = request("GET", f"{API}/assets/v1/operations/{op_id}", key)
    if not op.get("done"):
        raise RuntimeError(f"still processing after 2 minutes (operation {op_id}); run again later")
    resp = op.get("response") or {}
    if "assetId" not in resp:
        raise RuntimeError(f"no asset id: {json.dumps(op)[:400]}")
    return resp["assetId"], (resp.get("moderationResult") or {}).get("moderationState", "")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--key", default=os.environ.get("ROBLOX_API_KEY"))
    who = ap.add_mutually_exclusive_group()
    who.add_argument("--group")
    who.add_argument("--user")
    ap.add_argument("--dir", required=True, help="folder with the sound files (searched recursively)")
    ap.add_argument("--only", default="")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    if not a.dry_run and not (a.key and (a.group or a.user)):
        ap.error("needs --key and --group or --user (or --dry-run)")
    creator = {"groupId": str(a.group)} if a.group else {"userId": str(a.user)}
    files = sound_files(open(CONFIG, encoding="utf-8").read())
    only = {x.strip() for x in a.only.split(",") if x.strip()}
    root = os.path.expanduser(a.dir)
    todo, missing = [], []
    for name, current in files.items():
        if current or (only and name not in only):
            continue
        found = [p for p in glob.glob(os.path.join(root, "**", glob.escape(name) + ".*"), recursive=True)
                 if os.path.splitext(p)[1].lower() in TYPES]
        (todo.append((name, found[0])) if found else missing.append(name))
    print(f"{len(todo)} to upload, {sum(1 for v in files.values() if v)} already have ids, {len(missing)} not found in {root}")
    for name in missing:
        print("  not found:", name)
    for name, path in todo:
        size = os.path.getsize(path) / 1e6
        if a.dry_run:
            print(f"  would upload {os.path.basename(path)} ({size:.1f} MB)")
            continue
        if size > 20:
            print(f"  SKIP {name}: {size:.1f} MB is over Roblox's 20 MB limit")
            continue
        print(f"  uploading {os.path.basename(path)} ({size:.1f} MB)...")
        try:
            asset_id, state = upload(path, name, a.key, creator)
        except RuntimeError as e:
            print(f"    FAILED: {e}")
            if "quota" in str(e).lower() or "limit" in str(e).lower():
                print("    (upload limit reached: run again when it resets)")
                break
            continue
        write_id(name, asset_id)
        print(f"    rbxassetid://{asset_id}  {state}")
    left = [n for n, v in sound_files(open(CONFIG, encoding="utf-8").read()).items() if not v]
    print(f"done; {len(left)} files still without an id")


if __name__ == "__main__":
    sys.exit(main())
