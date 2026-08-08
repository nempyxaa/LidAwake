#!/bin/bash
# lid-settings.sh CONFIG_PATH KEY ACTION — persist an adjustable setting.
# Keys: THERMAL_GUARD (toggle 1/0), BATTERY_FLOOR (cycle 25→20→15→10→25).
CONFIG="$1"; KEY="$2"; ACTION="$3"; VAL="$4"
mkdir -p "$(dirname "$CONFIG")"; touch "$CONFIG"
. "$CONFIG" 2>/dev/null
set_kv(){ grep -v "^$1=" "$CONFIG" 2>/dev/null > "$CONFIG.tmp"; mv "$CONFIG.tmp" "$CONFIG"; echo "$1=$2" >> "$CONFIG"; }
case "$KEY:$ACTION" in
  NOTIFY:toggle)        NF="$(dirname "$CONFIG")/notify-off"; [ -f "$NF" ] && rm -f "$NF" || touch "$NF" ;;
  THERMAL_GUARD:toggle) [ "${THERMAL_GUARD:-1}" = "1" ] && set_kv THERMAL_GUARD 0 || set_kv THERMAL_GUARD 1 ;;
  BATTERY_FLOOR:cycle)  cur=${BATTERY_FLOOR:-20}; case "$cur" in 25) n=20;; 20) n=15;; 15) n=10;; *) n=25;; esac; set_kv BATTERY_FLOOR "$n" ;;
  BATTERY_FLOOR:set)    set_kv BATTERY_FLOOR "$4" ;;
esac
