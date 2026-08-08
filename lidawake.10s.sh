#!/bin/bash
# SwiftBar plugin v5 (08.08.2026): menu redesigned per multi-model UX panel.
# Sentence case, verbs for actions, checkmark for toggle state, three zones, battery-floor submenu.
DIR="$HOME/.lid-awake"; STATE="$HOME/.lid-awake/state"; CFG="$HOME/.lid-awake/state/config"; TOGGLE="$HOME/.lid-awake/lid-toggle.sh"; SETTINGS="$HOME/.lid-awake/lid-settings.sh"
BATOVR="$STATE/lid-battery-override"; NOTIFY_OFF="$STATE/notify-off"
FLAG=$(pmset -g | awk '/SleepDisabled/ {print $2}')
[ -f "$BATOVR" ] && BATOK=1 || BATOK=0
pmset -g ps | head -1 | grep -q "AC Power" && AC=1 || AC=0
PCT=$(pmset -g batt | grep -o "[0-9]*%" | tr -d '%' | head -1)
[ -f "$CFG" ] && . "$CFG"
THERMAL_GUARD=${THERMAL_GUARD:-1}; BATTERY_FLOOR=${BATTERY_FLOOR:-20}; REFUSE=$((BATTERY_FLOOR+5))
[ -f "$NOTIFY_OFF" ] && NOTIF=0 || NOTIF=1
L=$(defaults read -g AppleLocale 2>/dev/null | cut -c1-2)
case "$L" in
  de)
    S_SLEEPS="Deckel zu: Ruhezustand"; S_AWAKE="Deckel zu: bleibt wach"
    S_BATTERY="Akku:"; S_POWER_AC="Strom: Netz"
    S_REVERTS="Endet bei: Deckel auf, unter ${BATTERY_FLOOR}%, oder am Netz"
    A_KEEP="Mit geschlossenem Deckel wach halten"; A_TURNOFF="Wachhalten ausschalten"; A_SLEEP="Jetzt in den Ruhezustand"
    CAP_BAT="Vorübergehend, endet unter ${BATTERY_FLOOR}%"; CAP_AC="Am Netz, kein Akkulimit"
    SET="Einstellungen"; SET_NOTIF="Mitteilungen anzeigen"; SET_THERM="Bei Hitze automatisch schlafen"; SET_FLOOR="Akku-Mindeststand" ;;
  fr)
    S_SLEEPS="Capot fermé : veille"; S_AWAKE="Capot fermé : reste actif"
    S_BATTERY="Batterie :"; S_POWER_AC="Alim. : secteur"
    S_REVERTS="Fin si : capot ouvert, sous ${BATTERY_FLOOR}%, ou secteur"
    A_KEEP="Rester actif capot fermé"; A_TURNOFF="Désactiver le maintien actif"; A_SLEEP="Mettre en veille"
    CAP_BAT="Temporaire, fin sous ${BATTERY_FLOOR}%"; CAP_AC="Sur secteur, sans limite de batterie"
    SET="Réglages"; SET_NOTIF="Afficher les notifications"; SET_THERM="Veille auto en cas de surchauffe"; SET_FLOOR="Seuil de batterie" ;;
  es)
    S_SLEEPS="Tapa cerrada: en reposo"; S_AWAKE="Tapa cerrada: sigue activo"
    S_BATTERY="Batería:"; S_POWER_AC="Corriente: red"
    S_REVERTS="Termina si: abres la tapa, bajo ${BATTERY_FLOOR}%, o al enchufar"
    A_KEEP="Mantener activo con la tapa cerrada"; A_TURNOFF="Desactivar mantener activo"; A_SLEEP="Poner en reposo"
    CAP_BAT="Temporal, termina bajo ${BATTERY_FLOOR}%"; CAP_AC="Con corriente, sin límite de batería"
    SET="Ajustes"; SET_NOTIF="Mostrar notificaciones"; SET_THERM="Reposo automático si se calienta"; SET_FLOOR="Umbral de batería" ;;
  ru)
    S_SLEEPS="Крышка закрыта: сон"; S_AWAKE="Крышка закрыта: не спит"
    S_BATTERY="Батарея:"; S_POWER_AC="Питание: сеть"
    S_REVERTS="Вернётся: открыл крышку, ниже ${BATTERY_FLOOR}%, или зарядка"
    A_KEEP="Не спать с закрытой крышкой"; A_TURNOFF="Выключить «не спать»"; A_SLEEP="Уснуть сейчас"
    CAP_BAT="Временно, вернётся ниже ${BATTERY_FLOOR}%"; CAP_AC="На зарядке, без лимита батареи"
    SET="Настройки"; SET_NOTIF="Показывать уведомления"; SET_THERM="Засыпать при перегреве"; SET_FLOOR="Порог батареи" ;;
  *)
    S_SLEEPS="Lid closed: sleeps"; S_AWAKE="Lid closed: staying awake"
    S_BATTERY="Battery:"; S_POWER_AC="Power: AC"
    S_REVERTS="Reverts on: lid open, under ${BATTERY_FLOOR}%, plugged in"
    A_KEEP="Keep awake with lid closed"; A_TURNOFF="Turn off keep-awake"; A_SLEEP="Sleep now"
    CAP_BAT="Temporary, reverts under ${BATTERY_FLOOR}%"; CAP_AC="On AC, no battery limit"
    SET="Settings"; SET_NOTIF="Show notifications"; SET_THERM="Auto-sleep when hot"; SET_FLOOR="Battery floor" ;;
esac
# appearance-aware colors (single hex per mode; comma pairs don't parse on all SwiftBar builds)
DARK=0; [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = "Dark" ] && DARK=1
if [ "$DARK" = 1 ]; then C_HEAD="#ffffff"; C_SEC="#98989d"; else C_HEAD="#1d1d1f"; C_SEC="#6e6e73"; fi
BOLD="font=.AppleSystemUIFontBold"
# menu-bar icon
if [ "$BATOK" = 1 ]; then echo "| sfimage=moon.circle.fill"
elif [ "$FLAG" = 1 ]; then echo "| sfimage=moon.fill"
else echo "| sfimage=moon.zzz.fill"; fi
echo "---"
# ZONE 1 status (disabled = non-clickable, non-highlighting; explicit color = readable, not macOS-dimmed)
if [ "$BATOK" = 1 ]; then echo "$S_AWAKE | sfimage=moon.circle.fill color=#ff9500 $BOLD size=15 bash=/usr/bin/true terminal=false refresh=false"
elif [ "$FLAG" = 1 ]; then echo "$S_AWAKE | sfimage=moon.fill color=$C_HEAD $BOLD size=15 bash=/usr/bin/true terminal=false refresh=false"
else echo "$S_SLEEPS | sfimage=moon.zzz.fill color=$C_HEAD $BOLD size=15 bash=/usr/bin/true terminal=false refresh=false"; fi
if [ "$AC" = 1 ]; then echo "$S_POWER_AC | color=$C_SEC size=12 bash=/usr/bin/true terminal=false refresh=false"; else echo "$S_BATTERY ${PCT}% | color=$C_SEC size=12 bash=/usr/bin/true terminal=false refresh=false"; fi
[ "$BATOK" = 1 ] && echo "$S_REVERTS | color=$C_SEC size=11 bash=/usr/bin/true terminal=false refresh=false"
echo "---"
# ZONE 2 actions
if [ "$FLAG" = 1 ]; then
  echo "$A_TURNOFF | sfimage=moon.zzz.fill bash=$TOGGLE terminal=false refresh=true"
else
  echo "$A_KEEP | sfimage=moon.circle.fill bash=$TOGGLE terminal=false refresh=true"
  [ "$AC" = 1 ] && echo "$CAP_AC | color=$C_SEC size=11 bash=/usr/bin/true terminal=false refresh=false" || echo "$CAP_BAT | color=$C_SEC size=11 bash=/usr/bin/true terminal=false refresh=false"
fi
echo "$A_SLEEP | sfimage=powersleep bash=/bin/bash param1=-c param2='sudo -n pmset sleepnow' terminal=false"
echo "---"
# ZONE 3 settings submenu
echo "$SET | sfimage=gearshape"
[ "$NOTIF" = 1 ] && NM="✓ " || NM=""
echo "--${NM}$SET_NOTIF | bash=$SETTINGS param1=$CFG param2=NOTIFY param3=toggle terminal=false refresh=true"
[ "$THERMAL_GUARD" = 1 ] && TM="✓ " || TM=""
echo "--${TM}$SET_THERM | bash=$SETTINGS param1=$CFG param2=THERMAL_GUARD param3=toggle terminal=false refresh=true"
echo "--$SET_FLOOR: ${BATTERY_FLOOR}% | sfimage=battery.25"
for v in 10 15 20 25 30; do
  [ "$BATTERY_FLOOR" = "$v" ] && lbl="${v}%  ✓" || lbl="${v}%"
  echo "----$lbl | bash=$SETTINGS param1=$CFG param2=BATTERY_FLOOR param3=set param4=$v terminal=false refresh=true"
done
