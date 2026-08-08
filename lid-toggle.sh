#!/bin/bash
# Menu-bar toggle v4 (07.08.2026): AC toggles night mode; on BATTERY arms a temporary keep-awake
# override that now ALSO enables Low Power Mode (min heat, Piotr 06-07.08). Self-reverts as before.
# Strings localized from OS language (ru/en, fallback en).
NOTIFY_OFF="$HOME/.lid-awake/state/notify-off"
notify(){ [ -f "$NOTIFY_OFF" ] && return 0; osascript -e "display notification \"$1\" with title \"$2\"" 2>/dev/null; }
FLAG=$(pmset -g | awk '/SleepDisabled/ {print $2}')
CONFIG="$HOME/.lid-awake/state/config"
[ -f "$CONFIG" ] && . "$CONFIG"
THERMAL_GUARD=${THERMAL_GUARD:-1}
BATTERY_FLOOR=${BATTERY_FLOOR:-20}
MARK="$HOME/.lid-awake/state/lid-manual-off"
BATOK="$HOME/.lid-awake/state/lid-battery-override"

L=$(defaults read -g AppleLocale 2>/dev/null | cut -c1-2)
if [ "$L" = "ru" ]; then
  N_OFF_T="💤 Ночной режим выключен"; N_OFF_B="Крышка теперь усыпляет Mac как обычно."
  N_AC_T="🌙 Ночной режим включён"; N_AC_B="Mac продолжит работать с закрытой крышкой (на питании)."
  N_LOW_T="⚠️ Не включаю"; N_LOW_B="Батарея <25%, оверрайд не даю, подключи питание."
  N_BAT_T="🔋🌙 Батарейный оверрайд"; N_BAT_B="ВРЕМЕННО: Mac не уснёт с закрытой крышкой НА БАТАРЕЕ, включён режим низкого энергопотребления (мин. нагрев). Снимется само: открытие крышки, <20%, или питание."; N_FAIL_T="⚠️ lid-awake"; N_FAIL_B="Не удалось включить: pmset нужен беспарольный sudo (см. README). Ничего не изменилось."
else
  N_OFF_T="💤 Night mode off"; N_OFF_B="Closing the lid sleeps the Mac as usual."
  N_AC_T="🌙 Night mode on"; N_AC_B="Mac keeps running with the lid closed (on AC)."
  N_LOW_T="⚠️ Refused"; N_LOW_B="Battery below 25%, override refused, connect power."
  N_BAT_T="🔋🌙 Battery override"; N_BAT_B="TEMPORARY: Mac stays awake with the lid closed ON BATTERY, Low Power Mode enabled (min heat). Auto-reverts: lid opened, <20%, or power connected."; N_FAIL_T="⚠️ lid-awake"; N_FAIL_B="Could not enable keep-awake: pmset needs the passwordless-sudo step (see README). Nothing changed."
fi

if [ "$FLAG" = "1" ]; then
  rm -f "$BATOK"
  touch "$MARK"
  sudo -n pmset -b lowpowermode 0
  sudo -n pmset -a disablesleep 0
  notify "$N_OFF_B" "$N_OFF_T"
else
  if pmset -g ps | head -1 | grep -q "AC Power"; then
    rm -f "$MARK"
    sudo -n pmset -a disablesleep 1
    if [ "$(pmset -g | awk '/SleepDisabled/ {print $2}')" = "1" ]; then
      notify "$N_AC_B" "$N_AC_T"
    else
      notify "$N_FAIL_B" "$N_FAIL_T"
    fi
  else
    PCT=$(pmset -g batt | grep -o "[0-9]*%" | tr -d '%' | head -1)
    if [ -z "$PCT" ] || [ "$PCT" -lt $((BATTERY_FLOOR+5)) ]; then
      notify "$N_LOW_B" "$N_LOW_T"
    else
      sudo -n pmset -a disablesleep 1
      if [ "$(pmset -g | awk '/SleepDisabled/ {print $2}')" = "1" ]; then
        touch "$BATOK"; sudo -n pmset -b lowpowermode 1; notify "$N_BAT_B" "$N_BAT_T"
      else
        notify "$N_FAIL_B" "$N_FAIL_T"
      fi
    fi
  fi
fi
