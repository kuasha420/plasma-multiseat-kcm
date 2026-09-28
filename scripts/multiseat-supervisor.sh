#!/bin/bash
# Multiseat Supervisor Daemon for Plasma Login Manager
# Part of Plasma Multiseat Manager (kcm_multiseat)
#
# Symmetrically monitors systemd-logind seats and activates the Plasma greeter
# on waiting seats as soon as another seat logs in, resolving the singleton
# systemd --user (plasmalogin UID 959) session constraint in plasma-login-manager.

set -uo pipefail
trap "exit 0" SIGTERM SIGINT

log() {
    logger -t multiseat-supervisor "$*"
}

log "Starting Multiseat Supervisor Daemon..."

check_and_activate_seat() {
    local target_seat="$1"
    local other_seat="$2"
    local dm_seat_path="$3"

    # Check if other_seat has an active user session (non-greeter, regular user)
    if loginctl list-sessions --no-legend 2>/dev/null | grep -w "$other_seat" | grep -v "plasmalogin" | grep -q "user"; then
        # Other seat is actively logged in!
        # Check if target_seat already has an active user session
        if ! loginctl list-sessions --no-legend 2>/dev/null | grep -w "$target_seat" | grep -v "plasmalogin" | grep -q "user"; then
            # target_seat is NOT logged in. Check if it already has a healthy greeter running
            local has_working_greeter=0
            if loginctl list-sessions --no-legend 2>/dev/null | grep -w "$target_seat" | grep -q "greeter"; then
                if pgrep -f "/usr/lib/plasma-login-greeter" >/dev/null 2>&1; then
                    has_working_greeter=1
                fi
            fi

            if [ "$has_working_greeter" -eq 0 ]; then
                log "$other_seat is active; $target_seat needs a greeter. Activating $target_seat..."
                local stale_sessions
                stale_sessions=$(loginctl list-sessions --no-legend 2>/dev/null | grep -w "$target_seat" | grep "plasmalogin" | awk '{print $1}' || true)
                for sess in $stale_sessions; do
                    log "Terminating stale session $sess on $target_seat..."
                    loginctl terminate-session "$sess" 2>/dev/null || true
                    sleep 0.5
                done
                /usr/bin/qdbus6 --system org.freedesktop.DisplayManager "$dm_seat_path" org.freedesktop.DisplayManager.Seat.SwitchToGreeter 2>/dev/null || true
                log "SwitchToGreeter signal sent for $target_seat."
                sleep 4
            fi
        fi
    fi
}

while true; do
    # Bidirectional: check both directions
    check_and_activate_seat "seat1" "seat0" "/org/freedesktop/DisplayManager/Seat1"
    check_and_activate_seat "seat0" "seat1" "/org/freedesktop/DisplayManager/Seat0"
    sleep 2
done
