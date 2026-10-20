#!/bin/zsh
# Measures T-Utilities CPU and memory per module configuration (see Docs/OPTIMIZATION.md).
#   Scripts/measure.sh                       # all configs, 20 s warm-up, 120 s window, installed app
#   APP=build/ReleaseDerivedData/Build/Products/Release/T-Utilities.app Scripts/measure.sh none clipboard
#   DURATION=300 WARMUP=30 OUT=build/measure-before.csv Scripts/measure.sh
# Each config: quit app → set `modules.enabled` → launch → warm up → measure → next.
# The user's preferences are exported first and restored at the end (also on Ctrl-C).
set -euo pipefail

APP=${APP:-/Applications/T-Utilities.app}
WARMUP=${WARMUP:-20}
DURATION=${DURATION:-120}
OUT=${OUT:-build/measure-$(date +%Y%m%d-%H%M%S).csv}
DOMAIN=com.taegyu.tutilities
ALL=(awake clipboard cable clock windows mouse)
CONFIGS=($@)
(( $#CONFIGS )) || CONFIGS=(none $ALL all)

[[ -d $APP ]] || { echo "app not found: $APP"; exit 1; }
mkdir -p ${OUT:h}
BACKUP=$(mktemp -t tutilities-prefs).plist
defaults export $DOMAIN $BACKUP

quit_app() {
  osascript -e "quit app id \"$DOMAIN\"" >/dev/null 2>&1 || true
  for _ in {1..50}; do pgrep -x T-Utilities >/dev/null || return 0; sleep 0.2; done
  echo "app did not quit" >&2; exit 1
}

restore() {
  quit_app
  defaults import $DOMAIN $BACKUP
  open "$APP"
  echo "restored preferences and relaunched"
}
trap restore EXIT

# "M:SS.ss" or "H:MM:SS" → seconds
cpu_seconds() { ps -o time= -p $1 | awk -F: '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; print s }' }
mb() { awk -v kb=$1 'BEGIN { printf "%.1f", kb / 1024 }' }

echo "config,modules,footprint_mb,footprint_peak_mb,rss_mb,cpu_avg_pct,cpu_seconds,duration_s,version" > $OUT
VERSION=$(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString)

for config in $CONFIGS; do
  case $config in
    none) mods=() ;;
    all) mods=($ALL) ;;
    *) mods=($config) ;;
  esac
  quit_app
  defaults write $DOMAIN modules.enabled -array $mods
  open -g "$APP"
  sleep $WARMUP
  pid=$(pgrep -x T-Utilities) || { echo "app not running for $config" >&2; exit 1; }

  start=$(cpu_seconds $pid)
  sleep $DURATION
  end=$(cpu_seconds $pid)

  fp=$(footprint -p $pid 2>/dev/null | awk '/phys_footprint:/ { v = $2; u = $3 } END { print v, u }')
  peak=$(footprint -p $pid 2>/dev/null | awk '/phys_footprint_peak:/ { v = $2; u = $3 } END { print v, u }')
  to_mb() { awk -v v=${1%% *} -v u=${1##* } 'BEGIN { if (u == "KB") v /= 1024; else if (u == "GB") v *= 1024; printf "%.1f", v }' }
  rss=$(mb $(ps -o rss= -p $pid))
  cpu=$(awk -v a=$start -v b=$end -v d=$DURATION 'BEGIN { printf "%.3f", (b - a) / d * 100 }')
  used=$(awk -v a=$start -v b=$end 'BEGIN { printf "%.2f", b - a }')

  row="$config,${(j:+:)mods},$(to_mb $fp),$(to_mb $peak),$rss,$cpu,$used,$DURATION,$VERSION"
  echo $row >> $OUT
  echo $row
done

echo "→ $OUT"
