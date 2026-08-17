#!/bin/bash
# Enables or disables the Raspberry Pi status LEDs (ACT/green and PWR/red).
#
# Usage:
#   set_status_leds.sh 1       # disable (turn off) the status LEDs
#   set_status_leds.sh 0       # enable (restore) the status LEDs
#   set_status_leds.sh apply   # re-apply the persisted state (used at boot)
#
# Runs as root through the server action / flag mechanism, since writing to
# /sys/class/leds requires root privileges. The desired state is persisted so
# it survives reboots.

STATE_FILE="${BM_DIR:-$(dirname "$(dirname "$(dirname "$(readlink -f "$0")")")")}/control/.status_leds_disabled"

ACTION="$1"
case "$ACTION" in
  1)
    echo 1 > "$STATE_FILE"
    DISABLE=1
    ;;
  0)
    echo 0 > "$STATE_FILE"
    DISABLE=0
    ;;
  apply)
    DISABLE=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
    ;;
  *)
    echo "Invalid argument: '$ACTION' (expected 0, 1 or apply)" 1>&2
    exit 1
    ;;
esac

apply_led() {
    local dir="$1"
    local default_trigger="$2"
    [[ -d "$dir" ]] || return 0
    if [[ "$DISABLE" = "1" ]]; then
        echo none > "$dir/trigger" 2>/dev/null || true
        echo 0 > "$dir/brightness" 2>/dev/null || true
    else
        echo "$default_trigger" > "$dir/trigger" 2>/dev/null || true
        echo 1 > "$dir/brightness" 2>/dev/null || true
    fi
}

# Cover both the legacy (led0/led1) and newer (ACT/PWR) sysfs naming schemes.
# The default triggers restore the usual behaviour: ACT blinks on SD activity
# and PWR stays lit.
apply_led /sys/class/leds/led0 mmc0
apply_led /sys/class/leds/ACT mmc0
apply_led /sys/class/leds/led1 default-on
apply_led /sys/class/leds/PWR default-on

exit 0
