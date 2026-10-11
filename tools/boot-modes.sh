#!/usr/bin/env bash
# One line per boot: BIOS GPU mode (from which driver owns fb0), whether nvidia-powerd ran, resume times,
# and how the boot ended ("Journal stopped" = clean shutdown; anything else = hard power-off or lost tail).
# Usage: bash tools/boot-modes.sh [first-boot-offset]   (default -12)
for b in $(seq "${1:--12}" 0); do
  k=$(journalctl -b "$b" -k --no-pager -q -o cat 2>/dev/null) || continue
  if grep -q 'i915drmfb frame buffer' <<<"$k"; then m=hybrid
  elif grep -q 'nvidia-drmdrmfb' <<<"$k"; then m=dGPU
  else m=?; fi
  pd=$(journalctl -b "$b" --no-pager -q | grep -c 'Started nvidia-powerd')
  ex=$(journalctl -b "$b" -k --no-pager -q -o short | grep 'PM: suspend exit' | awk '{print $3}' | tr '\n' ' ')
  end=$(journalctl -b "$b" --no-pager -q -o short | tail -1 | cut -c1-90)
  printf '%4s  mode=%-6s powerd=%s  resumes=[%s]\n      last: %s\n' "$b" "$m" "$pd" "${ex% }" "$end"
done
