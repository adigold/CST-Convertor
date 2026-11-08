#!/bin/bash
# Convert Logic .cst channel strip settings into .patch bundles.
# Keeps the folder structure. Never changes or deletes the original .cst files.
#
# Usage:
#   ./convert-cst-to-patch.sh                     converts everything with the defaults below
#   ./convert-cst-to-patch.sh SOURCE DEST [LIMIT]
#     SOURCE  folder with your .cst files
#     DEST    folder where the .patch files go
#     LIMIT   optional, convert only the first N files (for testing)

SRC="${1:-$HOME/Music/Audio Music Apps/Channel Strip Settings/Instrument}"
DST="${2:-$HOME/Music/Audio Music Apps/Patches/Instrument}"
LIMIT="${3:-0}"

SRC="${SRC%/}"; DST="${DST%/}"
[ -d "$SRC" ] || { echo "Source folder not found: $SRC"; exit 1; }
SRC="$(cd "$SRC" && pwd)"
mkdir -p "$DST"
DST="$(cd "$DST" && pwd)"
# skip the destination folder if it sits inside the source folder
SKIP_DST=""; case "$DST/" in "$SRC/"*) SKIP_DST="$DST";; esac

xml_escape() { local s="$1"; s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; printf '%s' "$s"; }
new_uuid() {
  if command -v uuidgen >/dev/null; then uuidgen | tr a-z A-Z
  else cat /proc/sys/kernel/random/uuid | tr a-z A-Z; fi
}

send() { printf '\t\t\t\t<dict>\n\t\t\t\t\t<key>sendIsMuted</key>\n\t\t\t\t\t<false/>\n\t\t\t\t\t<key>sendMode</key>\n\t\t\t\t\t<integer>%s</integer>\n\t\t\t\t\t<key>sendOutputIndex</key>\n\t\t\t\t\t<integer>%s</integer>\n\t\t\t\t\t<key>sendVolume</key>\n\t\t\t\t\t<real>0.0</real>\n\t\t\t\t</dict>\n' "$1" "$2"; }

write_plist() { # $1=file $2=name $3=category
  local name cat; name=$(xml_escape "$2"); cat=$(xml_escape "$3")
  {
  cat <<P1
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>VersionPatches</key>
	<integer>40014</integer>
	<key>channels</key>
	<array>
		<dict>
			<key>Channel_chaStrCategory</key>
			<string>$cat</string>
			<key>Channel_inputIndex_1</key>
			<integer>-1</integer>
			<key>Channel_inputIsBus</key>
			<false/>
			<key>Channel_instID</key>
			<integer>88</integer>
			<key>Channel_isMuted</key>
			<false/>
			<key>Channel_isSolo</key>
			<false/>
			<key>Channel_name</key>
			<string>$name</string>
			<key>Channel_outputIndex</key>
			<integer>0</integer>
			<key>Channel_outputIsBus</key>
			<false/>
			<key>Channel_outputIsStereo</key>
			<true/>
			<key>Channel_receiveChannel</key>
			<integer>-1</integer>
			<key>Channel_sends</key>
			<array>
P1
  send 1 0; send 1 1; for i in 2 3 4 5 6 7; do send 2 $i; done
  cat <<P2
				<dict/>
			</array>
			<key>Channel_seqColorIndex</key>
			<integer>21</integer>
			<key>Channel_userDidModifySmartControls</key>
			<true/>
			<key>Filename</key>
			<string>#Root.cst</string>
			<key>Root</key>
			<true/>
			<key>Track_icon</key>
			<integer>4505</integer>
			<key>UUID</key>
			<string>$(new_uuid)</string>
		</dict>
	</array>
</dict>
</plist>
P2
  } > "$1"
  command -v plutil >/dev/null && plutil -convert binary1 "$1"
}

done_n=0; skip_n=0
while IFS= read -r -d '' cst; do
  rel="${cst#$SRC/}"
  file="${rel##*/}"; base="${file%.cst}"
  if [ "$file" = "$rel" ]; then dir=""; else dir="${rel%/*}"; fi
  name="${base%"${base##*[![:space:]]}"}"                    # trim trailing spaces
  if [ -z "$dir" ]; then outdir="$DST"; cat=""; else outdir="$DST/$dir"; cat="${dir##*/}"; fi
  patch="$outdir/$name.patch"
  if [ -e "$patch" ]; then echo "SKIP (exists): $rel"; skip_n=$((skip_n+1)); continue; fi
  mkdir -p "$patch"
  cp -p -- "$cst" "$patch/#Root.cst"
  write_plist "$patch/data.plist" "$name" "$cat"
  echo "OK: $rel"
  done_n=$((done_n+1))
  [ "$LIMIT" -gt 0 ] && [ "$done_n" -ge "$LIMIT" ] && break
done < <(find "$SRC" -mindepth 1 \( -path "${SKIP_DST:-/nonexistent}" -o -name "*.logicx" -o -name "*.patch" \) -prune -o -type f -name "*.cst" -print0 | sort -z)

echo
echo "Done. Converted: $done_n   Skipped: $skip_n"
echo "Patches are in: $DST"
