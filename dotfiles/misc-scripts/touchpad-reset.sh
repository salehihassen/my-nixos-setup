#!/usr/bin/env bash
# Recover the J2 ELAN trackpad when gestures require an extra finger:
# one finger does nothing, two move the pointer, and three scroll.
# Rebinding the HID driver recreates the trackpad's libinput device in Niri.
# Usage: sudo bash /etc/nixos/dotfiles/misc-scripts/touchpad-reset.sh
set -euo pipefail

driver=/sys/bus/hid/drivers/hid-multitouch
expected_name='ELAN07E4:00 04F3:32F4'
detached=false

if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
    printf 'Usage: sudo bash %q\n' "${BASH_SOURCE[0]}"
    printf 'Reconnect the J2 ELAN trackpad driver to recover normal finger gestures.\n'
    exit 0
fi
if (( $# != 0 )); then
    printf 'Usage: sudo bash %q\n' "${BASH_SOURCE[0]}" >&2
    exit 2
fi

if (( EUID != 0 )); then
    printf 'Run this script with: sudo bash %q\n' "${BASH_SOURCE[0]}" >&2
    exit 1
fi

# The final HID instance number can change after rebooting or reconnecting.
# Match the trackpad's identity and driver instead of hardcoding that number.
matches=()
for candidate in /sys/bus/hid/devices/0018:04F3:32F4.*; do
    [[ -r "$candidate/uevent" ]] || continue
    device_name=
    while IFS='=' read -r key value; do
        if [[ "$key" == HID_NAME ]]; then
            device_name=$value
        fi
    done < "$candidate/uevent"
    if [[ "$device_name" == "$expected_name" &&
          "$(readlink -f "$candidate/driver")" == "$driver" ]]; then
        matches+=("${candidate##*/}")
    fi
done
if (( ${#matches[@]} != 1 )); then
    printf 'Expected exactly one matching ELAN trackpad; found %s. Stopping.\n' "${#matches[@]}" >&2
    exit 1
fi
device=${matches[0]}

restore_if_needed() {
    if [[ "$detached" == true ]]; then
        printf '\nReattaching the trackpad driver...\n' >&2
        printf '%s\n' "$device" > "$driver/bind" || {
            printf 'Reattach failed. Retry with:\n' >&2
            printf '  printf "%%s\\n" "%s" | sudo tee "%s/bind"\n' "$device" "$driver" >&2
        }
    fi
}
trap restore_if_needed EXIT
trap 'exit 130' INT TERM

printf 'This will reconnect only the ELAN trackpad to its driver.\n'
printf '\n>>> LIFT ALL FINGERS off the trackpad now.\n'
for remaining in 3 2 1; do
    printf '    Reset starts in %s...\n' "$remaining"
    sleep 1
done

printf '\n>>> Disconnecting the trackpad driver...\n'
detached=true
printf '%s\n' "$device" > "$driver/unbind"
sleep 1

printf '>>> Reconnecting the trackpad driver...\n'
printf '%s\n' "$device" > "$driver/bind"
detached=false
udevadm settle --timeout=10
sleep 1

printf '\nTrackpad detected as:\n'
found=false
for name_file in /sys/class/input/event*/device/name; do
    [[ -r "$name_file" ]] || continue
    IFS= read -r input_name < "$name_file" || continue
    if [[ "$input_name" == "$expected_name Touchpad" ]]; then
        event_dir=${name_file%/device/name}
        printf '    /dev/input/%s: %s\n' "${event_dir##*/}" "$input_name"
        found=true
    fi
done
if [[ "$found" != true ]]; then
    printf 'The driver reattached, but the touchpad input device was not found.\n' >&2
    exit 1
fi

printf '\n>>> TRY ONE FINGER NOW: does it move the pointer?\n'
printf '>>> THEN TRY TWO FINGERS: do they scroll a webpage?\n'
printf '\nReset complete. No persistent settings were changed.\n'
