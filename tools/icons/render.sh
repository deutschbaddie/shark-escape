#!/usr/bin/env bash
# Renders the icon sheets and store art with headless Chromium (transparent
# background), then copies the finals into assets/.
set -e
cd "$(dirname "$0")"
python3 make_icons.py
python3 make_store_art.py
CHROME=${CHROME:-/opt/pw-browsers/chromium}
for f in build/*.html; do
  out="${f%.html}.png"
  case "$f" in
    *store_thumb*) W=1920; H=1080 ;;
    *store_icon*) W=512; H=512 ;;
    *) W=1024; H=1024 ;;
  esac
  "$CHROME" --headless=new --no-sandbox --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --default-background-color=00000000 --window-size=$W,$((H + 300)) --screenshot="$PWD/$out" "file://$PWD/$f" >/dev/null 2>&1
  python3 -c "from PIL import Image; im=Image.open('$out'); im.crop((0,0,$W,$H)).save('$out')"
  echo "rendered $out"
done
mkdir -p ../../assets/icons ../../assets/store
cp build/sheet_a.png ../../assets/icons/IconsA.png
cp build/sheet_b.png ../../assets/icons/IconsB.png
cp build/store_icon.png ../../assets/store/GameIcon.png
cp build/store_thumb.png ../../assets/store/Thumbnail.png
