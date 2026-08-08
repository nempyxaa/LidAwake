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
case "$L" in
  de)
    N_OFF_T="lid-awake"; N_OFF_B="Deckel schließen versetzt den Mac wie gewohnt in den Ruhezustand."
    N_AC_T="lid-awake"; N_AC_B="Der Mac läuft mit geschlossenem Deckel weiter (am Netz)."
    N_LOW_T="lid-awake"; N_LOW_B="Akku zu niedrig, Wachhalten abgelehnt, Netzteil anschliessen."
    N_BAT_T="lid-awake"; N_BAT_B="Mac bleibt mit geschlossenem Deckel im Akkubetrieb wach, Stromsparmodus an. Endet bei Deckel auf, wenig Akku oder Netz."
    N_FAIL_T="lid-awake"; N_FAIL_B="Konnte Wachhalten nicht aktivieren: pmset braucht die passwortlose sudo-Regel (siehe README). Nichts geaendert." ;;
  fr)
    N_OFF_T="lid-awake"; N_OFF_B="Fermer le capot met le Mac en veille comme d'habitude."
    N_AC_T="lid-awake"; N_AC_B="Le Mac continue capot ferme (sur secteur)."
    N_LOW_T="lid-awake"; N_LOW_B="Batterie trop basse, maintien refuse, branchez l'alimentation."
    N_BAT_T="lid-awake"; N_BAT_B="Le Mac reste actif capot ferme sur batterie, mode economie d'energie active. Fin si capot ouvert, batterie faible ou secteur."
    N_FAIL_T="lid-awake"; N_FAIL_B="Activation impossible: pmset requiert la regle sudo sans mot de passe (voir README). Rien change." ;;
  es)
    N_OFF_T="lid-awake"; N_OFF_B="Cerrar la tapa pone el Mac en reposo como siempre."
    N_AC_T="lid-awake"; N_AC_B="El Mac sigue con la tapa cerrada (con corriente)."
    N_LOW_T="lid-awake"; N_LOW_B="Bateria muy baja, se rechazo, conecta la corriente."
    N_BAT_T="lid-awake"; N_BAT_B="El Mac sigue activo con la tapa cerrada en bateria, modo de bajo consumo activado. Termina al abrir, bateria baja o corriente."
    N_FAIL_T="lid-awake"; N_FAIL_B="No se pudo activar: pmset necesita la regla sudo sin contrasena (ver README). Nada cambio." ;;
  ru)
    N_OFF_T="lid-awake"; N_OFF_B="Крышка теперь усыпляет Mac как обычно."
    N_AC_T="lid-awake"; N_AC_B="Mac продолжит работать с закрытой крышкой (на питании)."
    N_LOW_T="lid-awake"; N_LOW_B="Батарея слишком низкая, оверрайд не включён, подключи питание."
    N_BAT_T="lid-awake"; N_BAT_B="Mac не уснёт с закрытой крышкой на батарее, включён режим энергосбережения. Снимется само: открытие крышки, низкий заряд, или питание."
    N_FAIL_T="lid-awake"; N_FAIL_B="Не удалось включить: pmset нужен беспарольный sudo (см. README). Ничего не изменилось." ;;
  *)
    N_OFF_T="lid-awake"; N_OFF_B="Closing the lid sleeps the Mac as usual."
    N_AC_T="lid-awake"; N_AC_B="Mac keeps running with the lid closed (on AC)."
    N_LOW_T="lid-awake"; N_LOW_B="Battery too low, override refused, connect power."
    N_BAT_T="lid-awake"; N_BAT_B="Mac stays awake with the lid closed on battery, Low Power Mode on. Reverts on lid open, low battery, or power."
    N_FAIL_T="lid-awake"; N_FAIL_B="Could not enable keep-awake: pmset needs the passwordless-sudo step (see README). Nothing changed." ;;
esac

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
