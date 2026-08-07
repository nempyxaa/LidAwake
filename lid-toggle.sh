#!/bin/bash
# Menu-bar toggle v4 (07.08.2026): AC toggles night mode; on BATTERY arms a temporary keep-awake
# override that now ALSO enables Low Power Mode (min heat, Piotr 06-07.08). Self-reverts as before.
# Strings localized from OS language (ru/en, fallback en).
FLAG=$(pmset -g | awk '/SleepDisabled/ {print $2}')
MARK="$HOME/.lid-governor/state/lid-manual-off"
BATOK="$HOME/.lid-governor/state/lid-battery-override"

L=$(defaults read -g AppleLocale 2>/dev/null | cut -c1-2)
if [ "$L" = "ru" ]; then
  N_OFF_T="💤 Ночной режим выключен"; N_OFF_B="Крышка теперь усыпляет Mac как обычно."
  N_AC_T="🌙 Ночной режим включён"; N_AC_B="Mac продолжит работать с закрытой крышкой (на питании)."
  N_LOW_T="⚠️ Не включаю"; N_LOW_B="Батарея <25%, оверрайд не даю, подключи питание."
  N_BAT_T="🔋🌙 Батарейный оверрайд"; N_BAT_B="ВРЕМЕННО: Mac не уснёт с закрытой крышкой НА БАТАРЕЕ, включён режим низкого энергопотребления (мин. нагрев). Снимется само: открытие крышки, <20%, или питание."
else
  N_OFF_T="💤 Night mode off"; N_OFF_B="Closing the lid sleeps the Mac as usual."
  N_AC_T="🌙 Night mode on"; N_AC_B="Mac keeps running with the lid closed (on AC)."
  N_LOW_T="⚠️ Refused"; N_LOW_B="Battery below 25%, override refused, connect power."
  N_BAT_T="🔋🌙 Battery override"; N_BAT_B="TEMPORARY: Mac stays awake with the lid closed ON BATTERY, Low Power Mode enabled (min heat). Auto-reverts: lid opened, <20%, or power connected."
fi

if [ "$FLAG" = "1" ]; then
  rm -f "$BATOK"
  touch "$MARK"
  sudo -n pmset -b lowpowermode 0
  sudo -n pmset -a disablesleep 0
  osascript -e "display notification \"$N_OFF_B\" with title \"$N_OFF_T\"" 2>/dev/null
else
  if pmset -g ps | head -1 | grep -q "AC Power"; then
    rm -f "$MARK"
    sudo -n pmset -a disablesleep 1
    osascript -e "display notification \"$N_AC_B\" with title \"$N_AC_T\"" 2>/dev/null
  else
    PCT=$(pmset -g batt | grep -o "[0-9]*%" | tr -d '%' | head -1)
    if [ -n "$PCT" ] && [ "$PCT" -lt 25 ]; then
      osascript -e "display notification \"$N_LOW_B\" with title \"$N_LOW_T\"" 2>/dev/null
    else
      touch "$BATOK"
      sudo -n pmset -a disablesleep 1
      sudo -n pmset -b lowpowermode 1
      osascript -e "display notification \"$N_BAT_B\" with title \"$N_BAT_T\"" 2>/dev/null
    fi
  fi
fi
