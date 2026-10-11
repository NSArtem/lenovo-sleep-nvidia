#!/usr/bin/env bash
# Black screen after resume: suspends once the same way odvptest.sh did (systemctl suspend + RTC wake after 25 s)
# and records the panel / backlight / kwin output state before and after resume.
# Run as root:  sudo bash ~/resume-screen-test.sh            (nvidia-powerd stays as it is)
#               sudo bash ~/resume-screen-test.sh nopowerd   (stops nvidia-powerd for the test, starts it again after)
# If the screen stays black: wait ~60 s for the samples, then press Alt+SysRq+S (sync), wait a few seconds and hold
# power. A short power-key press only opens KDE's (invisible) logout screen.
set -u
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
U=artem
OUT=/home/$U/resume-test-$(date +%m%d-%H%M%S)${1:+-$1}.log
BL=/sys/class/backlight/nvidia_0
export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus WAYLAND_DISPLAY=wayland-0

snap(){
  echo "== $1  $(date +%T.%N)"
  echo "backlight nvidia_0: brightness=$(cat $BL/brightness) actual=$(cat $BL/actual_brightness) bl_power=$(cat $BL/bl_power)"
  for c in /sys/class/drm/card*-eDP-*; do echo "${c##*/}: status=$(cat $c/status) enabled=$(cat $c/enabled) dpms=$(cat $c/dpms)"; done
  echo "lid: $(awk '{print $2}' /proc/acpi/button/lid/LID0/state)  profile: $(cat /sys/class/platform-profile/platform-profile-0/profile)  powerd: $(systemctl is-active nvidia-powerd)"
  echo "gpu: $(nvidia-smi --query-gpu=display_active,display_mode,pstate,power.draw --format=csv,noheader 2>&1)"
  sudo -E -u $U kscreen-doctor -o 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'Output:|enabled|disabled|connected|Modes:' | sed 's/^/  kscreen: /'
}

exec > >(tee "$OUT") 2>&1
[ "${1:-}" = nopowerd ] && { systemctl stop nvidia-powerd; trap 'systemctl start nvidia-powerd' EXIT; }
T0=$(date +%s)
snap "before suspend"
n=$(cat /sys/power/suspend_stats/success)
rtcwake -m no -s 25 >/dev/null
systemctl suspend
for i in $(seq 1 120); do [ "$(cat /sys/power/suspend_stats/success)" != "$n" ] && break; sleep 0.5; done
echo "== resumed (suspend_stats success $n -> $(cat /sys/power/suspend_stats/success))"
for s in 1 3 6 10 20 40; do sleep $(( s - ${prev:-0} )); prev=$s; snap "resume +${s}s"; done
echo "== kernel since suspend"
journalctl -k --since "@$T0" --no-pager -o short-precise | grep -vE 'smpboot|CPU[0-9]+ is up|Booting Node|PMU|\.\.\. ' | tail -60
chown $U "$OUT"
journalctl --sync; sync
echo "log: $OUT"
