#!/bin/bash
# SwiftBar plugin v4 (07.08.2026): lid behavior status + one-click control.
# v4: SF Symbol template icons (Apple-style monochrome), Low Power Mode coupling on battery
# override (min heat), strings localized from OS language (ru/en, fallback en).
FLAG=$(pmset -g | awk '/SleepDisabled/ {print $2}')
BATOK=0
[ -f "$HOME/.lid-governor/state/lid-battery-override" ] && BATOK=1
if pmset -g ps | head -1 | grep -q "AC Power"; then AC=1; else AC=0; fi
PCT=$(pmset -g batt | grep -o "[0-9]*%" | tr -d '%' | head -1)
LPM=$(pmset -g | awk '/lowpowermode/ {print $2}')
CONFIG="$HOME/.lid-governor/state/config"
[ -f "$CONFIG" ] && . "$CONFIG"
THERMAL_GUARD=${THERMAL_GUARD:-1}
BATTERY_FLOOR=${BATTERY_FLOOR:-20}
NOTIFY_OFF="$HOME/.lid-governor/state/notify-off"

L=$(defaults read -g AppleLocale 2>/dev/null | cut -c1-2)
if [ "$L" = "ru" ]; then
  T_CLOSED_BAT="Крышка закрыта: работает НА БАТАРЕЕ (оверрайд)"
  T_AUTOREVERT="Снимется сам: крышка открыта / <20% / питание"
  T_CLOSED_ON="Крышка закрыта: Mac продолжает работать"
  T_CLOSED_DEF="Крышка закрыта: Mac заснёт (дефолт)"
  T_PWR_AC="Питание: сеть"
  T_PWR_BAT="Питание: батарея"
  T_LPM_ON="Низкое энергопотребление: вкл (мин. нагрев)"
  T_DEFAULT="Вернуть дефолт (крышка усыпляет)"
  T_SLEEPNOW_DEF="Усыпить сейчас (и вернуть дефолт)"
  T_NIGHT_AC="Включить ночной режим (на питании)"
  T_BAT_OVR="Работать с закрытой крышкой НА БАТАРЕЕ (временно, мин. нагрев; не даст при <25%)"
  T_SLEEPNOW="Усыпить сейчас"
  T_NOTIF_ON="Уведомления вкл, выключить"
  T_THERM_ON="Тепловая защита: вкл"
  T_THERM_OFF="Тепловая защита: выкл"
  T_BFLOOR="Мин. заряд для оверрайда"
  T_NOTIF_OFF="Уведомления выкл, включить"
else
  T_CLOSED_BAT="Lid closed: keeps running ON BATTERY (override)"
  T_AUTOREVERT="Auto-reverts: lid opened / <20% / power connected"
  T_CLOSED_ON="Lid closed: Mac keeps running"
  T_CLOSED_DEF="Lid closed: Mac sleeps (default)"
  T_PWR_AC="Power: AC"
  T_PWR_BAT="Power: battery"
  T_LPM_ON="Low Power Mode: on (min heat)"
  T_DEFAULT="Back to default (lid sleeps the Mac)"
  T_SLEEPNOW_DEF="Sleep now (and restore default)"
  T_NIGHT_AC="Enable night mode (on AC)"
  T_BAT_OVR="Keep running with lid closed ON BATTERY (temporary, min heat; refused below 25%)"
  T_SLEEPNOW="Sleep now"
  T_NOTIF_ON="Notifications on, mute"
  T_THERM_ON="Thermal auto-sleep: on"
  T_THERM_OFF="Thermal auto-sleep: off"
  T_BFLOOR="Battery floor for override"
  T_NOTIF_OFF="Notifications off, unmute"
fi

if [ "$FLAG" = "1" ] && [ "$BATOK" = "1" ]; then
  echo "| sfimage=moon.circle.fill"
elif [ "$FLAG" = "1" ] && [ "$AC" = "1" ]; then
  echo "| sfimage=moon.fill"
elif [ "$FLAG" = "1" ]; then
  echo "| sfimage=exclamationmark.triangle.fill"
else
  echo "| sfimage=moon.zzz.fill"
fi
echo "---"
if [ "$FLAG" = "1" ]; then
  if [ "$BATOK" = "1" ]; then
    echo "$T_CLOSED_BAT | color=orange"
    echo "$T_AUTOREVERT | color=gray"
    [ "$LPM" = "1" ] && echo "$T_LPM_ON | color=gray"
  else
    echo "$T_CLOSED_ON | color=green"
  fi
else
  echo "$T_CLOSED_DEF | color=gray"
fi
if [ "$AC" = "1" ]; then
  echo "$T_PWR_AC ✓"
else
  echo "$T_PWR_BAT ${PCT}%"
fi
echo "---"
if [ "$FLAG" = "1" ]; then
  echo "$T_DEFAULT | sfimage=moon.zzz bash=$HOME/.lid-governor/lid-toggle.sh terminal=false refresh=true"
  echo "$T_SLEEPNOW_DEF | sfimage=powersleep bash=/bin/bash param1=-c param2='rm -f $HOME/.lid-governor/state/lid-battery-override; sudo -n pmset -b lowpowermode 0; sudo -n pmset -a disablesleep 0; sudo -n pmset sleepnow' terminal=false refresh=true"
else
  if [ "$AC" = "1" ]; then
    echo "$T_NIGHT_AC | sfimage=moon.fill bash=$HOME/.lid-governor/lid-toggle.sh terminal=false refresh=true"
  else
    echo "$T_BAT_OVR | sfimage=moon.circle.fill bash=$HOME/.lid-governor/lid-toggle.sh terminal=false refresh=true"
  fi
  echo "$T_SLEEPNOW | sfimage=powersleep bash=/bin/bash param1=-c param2='sudo -n pmset sleepnow' terminal=false"
fi
echo "---"
if [ -f "$NOTIFY_OFF" ]; then
  echo "$T_NOTIF_OFF | sfimage=bell.slash.fill bash=/bin/bash param1=-c param2='rm -f \"$HOME/.lid-governor/state/notify-off\"' terminal=false refresh=true"
else
  echo "$T_NOTIF_ON | sfimage=bell.fill bash=/bin/bash param1=-c param2='mkdir -p \"$HOME/.lid-governor/state\"; touch \"$HOME/.lid-governor/state/notify-off\"' terminal=false refresh=true"
fi
if [ "$THERMAL_GUARD" = "1" ]; then
  echo "$T_THERM_ON | sfimage=thermometer.medium bash=$HOME/.lid-governor/lid-settings.sh param1=$CONFIG param2=THERMAL_GUARD param3=toggle terminal=false refresh=true"
else
  echo "$T_THERM_OFF | sfimage=thermometer.low bash=$HOME/.lid-governor/lid-settings.sh param1=$CONFIG param2=THERMAL_GUARD param3=toggle terminal=false refresh=true"
fi
echo "$T_BFLOOR: ${BATTERY_FLOOR}% | sfimage=battery.25 bash=$HOME/.lid-governor/lid-settings.sh param1=$CONFIG param2=BATTERY_FLOOR param3=cycle terminal=false refresh=true"
