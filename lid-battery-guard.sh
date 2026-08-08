#!/bin/bash
# lid-awake v3 (Piotr 03.08 18:19): AC -> night mode auto-ON (unless manually declined this session).
# BATTERY -> default SLEEP on lid close, but the menu-bar toggle may arm a TEMPORARY battery override
# (marker file). The override self-reverts: lid reopen, battery <20%, or power state change.

CONFIG="$HOME/.lid-awake/state/config"
[ -f "$CONFIG" ] && . "$CONFIG"
THERMAL_GUARD=${THERMAL_GUARD:-1}
BATTERY_FLOOR=${BATTERY_FLOOR:-20}
L=$(defaults read -g AppleLocale 2>/dev/null | cut -c1-2)
case "$L" in
  de)
    G_OPEN_T="lid-awake"; G_OPEN_B="Deckel offen: Akku-Uebersteuerung beendet, Standard-Ruhezustand wieder aktiv."
    G_AC_T="lid-awake"; G_AC_B="Am Netz: Nachtmodus automatisch an. Zum Ausschalten den Mond anklicken."
    G_LOW_T="lid-awake"; G_LOW_B="Akku unter ${BATTERY_FLOOR}%: Uebersteuerung beendet, Mac schlaeft bei geschlossenem Deckel."
    G_HOT_T="lid-awake"; G_HOT_PREFIX="Ruhezustand wegen Ueberhitzung um"
    G_BAT_T="lid-awake"; G_BAT_B="Im Akkubetrieb: Nachtmodus aus, Deckel schliessen versetzt in den Ruhezustand."
    G_FAIL_T="lid-awake"; G_FAIL_B="Konnte nicht aktivieren: pmset braucht die passwortlose sudo-Regel (siehe README). Nichts geaendert." ;;
  fr)
    G_OPEN_T="lid-awake"; G_OPEN_B="Capot ouvert: derogation batterie terminee, veille par defaut retablie."
    G_AC_T="lid-awake"; G_AC_B="Sur secteur: mode nuit active automatiquement. Cliquez la lune pour desactiver."
    G_LOW_T="lid-awake"; G_LOW_B="Batterie sous ${BATTERY_FLOOR}%: derogation terminee, le Mac se met en veille capot ferme."
    G_HOT_T="lid-awake"; G_HOT_PREFIX="Mise en veille pour surchauffe a"
    G_BAT_T="lid-awake"; G_BAT_B="Sur batterie: mode nuit desactive, fermer le capot met en veille."
    G_FAIL_T="lid-awake"; G_FAIL_B="Activation impossible: pmset requiert la regle sudo sans mot de passe (voir README). Rien change." ;;
  es)
    G_OPEN_T="lid-awake"; G_OPEN_B="Tapa abierta: anulacion en bateria terminada, reposo por defecto restaurado."
    G_AC_T="lid-awake"; G_AC_B="Con corriente: modo noche activado automaticamente. Haz clic en la luna para desactivar."
    G_LOW_T="lid-awake"; G_LOW_B="Bateria bajo ${BATTERY_FLOOR}%: anulacion terminada, el Mac entra en reposo con la tapa cerrada."
    G_HOT_T="lid-awake"; G_HOT_PREFIX="En reposo por sobrecalentamiento a las"
    G_BAT_T="lid-awake"; G_BAT_B="En bateria: modo noche desactivado, cerrar la tapa pone en reposo."
    G_FAIL_T="lid-awake"; G_FAIL_B="No se pudo activar: pmset necesita la regla sudo sin contrasena (ver README). Nada cambio." ;;
  ru)
    G_OPEN_T="lid-awake"; G_OPEN_B="Крышка открыта: батарейный оверрайд снят, дефолт снова сон."
    G_AC_T="lid-awake"; G_AC_B="На питании: ночной режим включён автоматически. Выключить - клик по луне."
    G_LOW_T="lid-awake"; G_LOW_B="Батарея ниже ${BATTERY_FLOOR}%: оверрайд снят, Mac уснёт с крышкой."
    G_HOT_T="lid-awake"; G_HOT_PREFIX="Ушёл в сон из-за перегрева в"
    G_BAT_T="lid-awake"; G_BAT_B="На батарее: ночной режим выключен, крышка усыпляет как обычно."
    G_FAIL_T="lid-awake"; G_FAIL_B="Не удалось включить: pmset нужен беспарольный sudo (см. README). Ничего не изменилось." ;;
  *)
    G_OPEN_T="lid-awake"; G_OPEN_B="Lid opened: battery override cleared, default sleep restored."
    G_AC_T="lid-awake"; G_AC_B="On AC: night mode enabled automatically. Click the moon to disable."
    G_LOW_T="lid-awake"; G_LOW_B="Battery below ${BATTERY_FLOOR}%: override revoked, Mac will sleep with the lid closed."
    G_HOT_T="lid-awake"; G_HOT_PREFIX="Went to sleep due to overheating at"
    G_BAT_T="lid-awake"; G_BAT_B="On battery: night mode off, the lid sleeps the Mac as usual."
    G_FAIL_T="lid-awake"; G_FAIL_B="Could not enable keep-awake: pmset needs the passwordless-sudo step (see README). Nothing changed." ;;
esac
NOTIFY_OFF="$HOME/.lid-awake/state/notify-off"
notify(){ [ -f "$NOTIFY_OFF" ] && return 0; osascript -e "display notification \"$1\" with title \"$2\"" 2>/dev/null; }
revert_verified(){ # C9 symmetry: arming verifies, so must reverting. Re-read after disablesleep 0.
  sudo -n pmset -a disablesleep 0
  if [ "$(pmset -g | awk '/SleepDisabled/ {print $2}')" = "1" ]; then
    echo "$(date '+%F %T') REVERT-VERIFY FAILED (SleepDisabled still 1)" >> "$LOG"
    return 1
  fi
}
FLAG=$(pmset -g | awk '/SleepDisabled/ {print $2}')
MARK="$HOME/.lid-awake/state/lid-manual-off"          # user declined auto-ON while on AC (session-scoped)
BATOK="$HOME/.lid-awake/state/lid-battery-override"   # user armed keep-awake on battery (one lid-session)
CLAM_LAST="$HOME/.lid-awake/state/lid-clamshell-last"
LOG="$HOME/.lid-awake/state/lid-guard.log"

# markers die at boot - defaults always resume after a power cycle
BOOT=$(sysctl -n kern.boottime | awk -F"sec = |," "{print \$2}")
for f in "$MARK" "$BATOK"; do
  if [ -f "$f" ] && [ -n "$BOOT" ] && [ "$(stat -f %m "$f")" -lt "$BOOT" ]; then
    [ "$f" = "$BATOK" ] && sudo -n pmset -b lowpowermode 0
    rm -f "$f"
  fi
done

# reconcile: BATOK marker with the pmset flag OFF is stale state (external pmset call, crash) -> clear it
if [ -f "$BATOK" ] && [ "$FLAG" != "1" ]; then
  sudo -n pmset -b lowpowermode 0; rm -f "$BATOK"
  echo "$(date '+%F %T') stale-BATOK cleared (flag was off)" >> "$LOG"
fi

CLAM=$(ioreg -r -k AppleClamshellState -d 1 2>/dev/null | awk '/AppleClamshellState/ {print ($NF=="Yes")?"closed":"open"}' | head -1)
PREV=$(cat "$CLAM_LAST" 2>/dev/null)
echo "$CLAM" > "$CLAM_LAST"

# Piotr 04.08: EVERY exception lives exactly one lid cycle. A sleep gap (missed ticks) or an
# observed closed->open transition both mean the cycle completed -> clear ALL exception markers.
TICK_TS="$HOME/.lid-awake/state/lid-last-tick"
NOWS=$(date +%s)
LASTS=$(cat "$TICK_TS" 2>/dev/null || echo "$NOWS")
echo "$NOWS" > "$TICK_TS"
if [ $((NOWS - LASTS)) -gt 420 ] && { [ -f "$MARK" ] || [ -f "$BATOK" ]; }; then
  [ -f "$BATOK" ] && sudo -n pmset -b lowpowermode 0
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
  revert_verified
  sudo -n pmset -b lowpowermode 0
  notify "$G_OPEN_B" "$G_OPEN_T"
  echo "$(date '+%F %T') battery-override auto-revert (lid opened)" >> "$LOG"
fi

if pmset -g ps | head -1 | grep -q "AC Power"; then
  if [ -f "$BATOK" ]; then sudo -n pmset -b lowpowermode 0; fi
  rm -f "$BATOK"   # AC logic owns the flag now
  if [ "$FLAG" != "1" ] && [ ! -f "$MARK" ]; then
    sudo -n pmset -a disablesleep 1
    if [ "$(pmset -g | awk '/SleepDisabled/ {print $2}')" = "1" ]; then
      notify "$G_AC_B" "$G_AC_T"; echo "$(date '+%F %T') auto-ON (AC)" >> "$LOG"
    else
      notify "$G_FAIL_B" "$G_FAIL_T"; echo "$(date '+%F %T') auto-ON FAILED (pmset)" >> "$LOG"
    fi
  fi
else
  # Piotr 04.08 final spec: the AC manual-off exception survives power changes - it dies ONLY on
  # lid-open or reboot. (The battery override still dies on power change, handled above.)
  if [ "$FLAG" = "1" ]; then
    if [ -f "$BATOK" ]; then
      # honored override - but never below 20% battery
      # thermal safety (universal, Intel + Apple Silicon): read macOS thermal pressure via the
      # bundled thermalstate helper (NSProcessInfo.thermalState: 0 nominal 1 fair 2 serious 3 critical).
      # At "serious" or worse, sleep the closed-on-battery machine so it cools.
      TS=$( "$HOME/.lid-awake/thermalstate" 2>/dev/null )
      case "$TS" in ''|*[!0-9]*) TS=0 ;; esac   # unreadable -> treat as nominal (helper missing); thermal guard simply no-ops, never false-sleeps
      if [ "$THERMAL_GUARD" = "1" ] && [ "$CLAM" = "closed" ] && [ "$TS" -ge 2 ]; then
        rm -f "$BATOK"
        revert_verified
        sudo -n pmset -b lowpowermode 0
        WHEN=$(date "+%-I:%M%p on %A, %-d %b" | sed 's/AM/am/; s/PM/pm/')
        MSG="$G_HOT_PREFIX $WHEN"
        notify "$MSG" "$G_HOT_T"
        echo "$MSG" >> "$HOME/.lid-awake/state/thermal-history.txt"
        echo "$(date '+%F %T') thermal force-sleep (thermalState=$TS)" >> "$LOG"
        sudo -n pmset sleepnow
        exit 0
      fi
      PCT=$(pmset -g batt | grep -o "[0-9]*%" | tr -d '%' | head -1)
      if [ -z "$PCT" ] || [ "$PCT" -lt "$BATTERY_FLOOR" ]; then
        rm -f "$BATOK"
        revert_verified
        sudo -n pmset -b lowpowermode 0
        notify "$G_LOW_B" "$G_LOW_T"
        echo "$(date '+%F %T') battery-override revoked (<${BATTERY_FLOOR}%)" >> "$LOG"
      fi
    else
      revert_verified
      notify "$G_BAT_B" "$G_BAT_T"
      echo "$(date '+%F %T') auto-OFF (battery, no override)" >> "$LOG"
    fi
  fi
fi
