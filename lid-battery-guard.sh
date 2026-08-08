#!/bin/bash
# Lid governor v3 (Piotr 03.08 18:19): AC -> night mode auto-ON (unless manually declined this session).
# BATTERY -> default SLEEP on lid close, but the menu-bar toggle may arm a TEMPORARY battery override
# (marker file). The override self-reverts: lid reopen, battery <20%, or power state change.

L=$(defaults read -g AppleLocale 2>/dev/null | cut -c1-2)
if [ "$L" = "ru" ]; then
  G_OPEN_T="💤 Lid governor"; G_OPEN_B="Крышка открыта: батарейный оверрайд снят, дефолт снова сон."
  G_AC_T="🌙 Lid governor"; G_AC_B="На питании: ночной режим включён автоматически. Выключить - клик по луне."
  G_LOW_T="⚠️ Lid governor"; G_LOW_B="Батарея <20%: оверрайд снят принудительно, Mac уснёт с крышкой."; G_HOT_T="🌡️ Lid governor"; G_HOT_B="Перегрев на батарее: усыпляю Mac, чтобы не грелся. Записано в журнал."; G_BAT_T="💤 Lid governor"; G_BAT_B="На батарее: ночной режим выключен, крышка усыпляет как обычно."
else
  G_OPEN_T="💤 Lid governor"; G_OPEN_B="Lid opened: battery override cleared, default sleep restored."
  G_AC_T="🌙 Lid governor"; G_AC_B="On AC: night mode enabled automatically. Click the moon to disable."
  G_LOW_T="⚠️ Lid governor"; G_LOW_B="Battery below 20%: override revoked, Mac will sleep with the lid closed."; G_HOT_T="🌡️ Lid governor"; G_HOT_B="Overheating on battery: sleeping the Mac to cool it. Logged."; G_BAT_T="💤 Lid governor"; G_BAT_B="On battery: night mode off, the lid sleeps the Mac as usual."
fi
NOTIFY_OFF="$HOME/.lid-governor/state/notify-off"
notify(){ [ -f "$NOTIFY_OFF" ] && return 0; osascript -e "display notification \"$1\" with title \"$2\"" 2>/dev/null; }
FLAG=$(pmset -g | awk '/SleepDisabled/ {print $2}')
MARK="$HOME/.lid-governor/state/lid-manual-off"          # user declined auto-ON while on AC (session-scoped)
BATOK="$HOME/.lid-governor/state/lid-battery-override"   # user armed keep-awake on battery (one lid-session)
CLAM_LAST="$HOME/.lid-governor/state/lid-clamshell-last"
LOG="$HOME/.lid-governor/state/lid-guard.log"

# markers die at boot - defaults always resume after a power cycle
BOOT=$(sysctl -n kern.boottime | awk -F"sec = |," "{print \$2}")
for f in "$MARK" "$BATOK"; do
  [ -f "$f" ] && [ -n "$BOOT" ] && [ "$(stat -f %m "$f")" -lt "$BOOT" ] && rm -f "$f"
done

CLAM=$(ioreg -r -k AppleClamshellState -d 1 2>/dev/null | awk '/AppleClamshellState/ {print ($NF=="Yes")?"closed":"open"}' | head -1)
PREV=$(cat "$CLAM_LAST" 2>/dev/null)
echo "$CLAM" > "$CLAM_LAST"

# Piotr 04.08: EVERY exception lives exactly one lid cycle. A sleep gap (missed ticks) or an
# observed closed->open transition both mean the cycle completed -> clear ALL exception markers.
TICK_TS="$HOME/.lid-governor/state/lid-last-tick"
NOWS=$(date +%s)
LASTS=$(cat "$TICK_TS" 2>/dev/null || echo "$NOWS")
echo "$NOWS" > "$TICK_TS"
if [ $((NOWS - LASTS)) -gt 420 ] && { [ -f "$MARK" ] || [ -f "$BATOK" ]; }; then
  rm -f "$MARK" "$BATOK"
  echo "$(date '+%F %T') exceptions cleared (sleep gap = lid cycle completed)" >> "$LOG"
fi
if [ "$PREV" = "closed" ] && [ "$CLAM" = "open" ] && [ -f "$MARK" ]; then
  rm -f "$MARK"
  echo "$(date '+%F %T') manual-off cleared (lid cycle observed)" >> "$LOG"
fi

# battery-override self-revert: lid was closed and is now open -> the work session is over
if [ -f "$BATOK" ] && [ "$PREV" = "closed" ] && [ "$CLAM" = "open" ]; then
  rm -f "$BATOK"
  sudo -n pmset -a disablesleep 0
  sudo -n pmset -b lowpowermode 0
  notify "$G_OPEN_B" "$G_OPEN_T"
  echo "$(date '+%F %T') battery-override auto-revert (lid opened)" >> "$LOG"
fi

if pmset -g ps | head -1 | grep -q "AC Power"; then
  if [ -f "$BATOK" ]; then sudo -n pmset -b lowpowermode 0; fi
  rm -f "$BATOK"   # AC logic owns the flag now
  if [ "$FLAG" != "1" ] && [ ! -f "$MARK" ]; then
    sudo -n pmset -a disablesleep 1
    notify "$G_AC_B" "$G_AC_T"
    echo "$(date '+%F %T') auto-ON (AC)" >> "$LOG"
  fi
else
  # Piotr 04.08 final spec: the AC manual-off exception survives power changes - it dies ONLY on
  # lid-open or reboot. (The battery override still dies on power change, handled above.)
  if [ "$FLAG" = "1" ]; then
    if [ -f "$BATOK" ]; then
      # honored override - but never below 20% battery
      # thermal safety + learning log: macOS drops CPU_Speed_Limit below 100 when it throttles for
      # heat/power. While we keep a closed laptop awake on battery, sample it every tick; if it
      # throttles, force sleep so the machine cools. Record is at /Users/nempyxaa/.lid-governor/state/thermal-events.csv.
      TLOG="/Users/nempyxaa/.lid-governor/state/thermal-events.csv"
      [ -f "$TLOG" ] || echo "iso_time,battery_pct,cpu_speed_limit,action" > "$TLOG"
      SL=$(pmset -g therm 2>/dev/null | grep -oiE "CPU_Speed_Limit[ \t]*=[ \t]*[0-9]+" | grep -oE "[0-9]+$")
      SL=${SL:-100}
      BPCT=$(pmset -g batt | grep -o "[0-9]*%" | tr -d '%' | head -1)
      echo "$(date -u +%FT%TZ),${BPCT:-?},$SL,sample" >> "$TLOG"
      if [ "$SL" -lt 100 ]; then
        echo "$(date -u +%FT%TZ),${BPCT:-?},$SL,forced-sleep" >> "$TLOG"
        rm -f "$BATOK"
        sudo -n pmset -a disablesleep 0
        sudo -n pmset -b lowpowermode 0
        notify "$G_HOT_B" "$G_HOT_T"
        echo "$(date '+%F %T') thermal force-sleep (CPU_Speed_Limit=$SL, batt=${BPCT}%)" >> "$LOG"
        sudo -n pmset sleepnow
      fi
      PCT=$(pmset -g batt | grep -o "[0-9]*%" | tr -d '%' | head -1)
      if [ -n "$PCT" ] && [ "$PCT" -lt 20 ]; then
        rm -f "$BATOK"
        sudo -n pmset -a disablesleep 0
        sudo -n pmset -b lowpowermode 0
        notify "$G_LOW_B" "$G_LOW_T"
        echo "$(date '+%F %T') battery-override revoked (<20%)" >> "$LOG"
      fi
    else
      sudo -n pmset -a disablesleep 0
      notify "$G_BAT_B" "$G_BAT_T"
      echo "$(date '+%F %T') auto-OFF (battery, no override)" >> "$LOG"
    fi
  fi
fi
