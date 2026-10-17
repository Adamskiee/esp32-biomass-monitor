#!/usr/bin/env bash
set -euo pipefail

app_dir=$(cd "$(dirname "$0")/.." && pwd)
source_icon="$app_dir/assets/branding/ecoburn-icon.png"

if command -v magick >/dev/null; then
  image_command=magick
elif command -v convert >/dev/null; then
  image_command=convert
else
  echo "Install ImageMagick to regenerate launcher icons." >&2
  exit 1
fi

for density_size in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density=${density_size%:*}
  size=${density_size#*:}
  "$image_command" "$source_icon" -resize "${size}x${size}" -alpha off \
    "$app_dir/android/app/src/main/res/mipmap-$density/ic_launcher.png"
done

for icon in "$app_dir/ios/Runner/Assets.xcassets/AppIcon.appiconset/"*.png; do
  filename=${icon##*/}
  dimensions=${filename#Icon-App-}
  points=${dimensions%%x*}
  scale=${dimensions##*@}
  scale=${scale%x.png}
  size=$(awk -v points="$points" -v scale="$scale" 'BEGIN { print points * scale }')
  "$image_command" "$source_icon" -resize "${size}x${size}" -alpha off "$icon"
done
