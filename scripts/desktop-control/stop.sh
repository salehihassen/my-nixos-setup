#!/usr/bin/env bash
set -eu

systemctl --user stop desktop-control.service

# A stop during a drag or chord must not leave the virtual device held down.
if command -v ydotool >/dev/null 2>&1; then
  ydotool click 0x80 0x81 0x82 >/dev/null 2>&1 || true
  ydotool key 29:0 42:0 56:0 125:0 >/dev/null 2>&1 || true
fi

if command -v notify-send >/dev/null 2>&1; then
  notify-send "AI desktop control stopped" "Restart explicitly: systemctl --user start desktop-control.service"
fi
