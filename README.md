# Black internal screen after S3 resume — Lenovo 83F0, NVIDIA dGPU mode

After resume from suspend, the laptop sometimes comes back with the internal panel dark. The system itself is alive:
the Plasma session, KWin and the lock screen run, Wi-Fi reconnects, scripts keep logging. The only way out has been a
power-off. Investigated 2026-10-11.

**Current conclusion:** the problem only happens with the BIOS graphics mode set to **dGPU only** (panel driven by the
NVIDIA GPU). With **both GPUs enabled** (hybrid, panel on the Intel iGPU) resume has been reliable. Inside dGPU mode
the trigger is not found; it is flaky (about half of the resumes failed on 2026-10-11, while 6/6 were fine on
2026-10-07…10-10 with the same software, see H7). Workaround in use: hybrid mode.

## System

| | |
|---|---|
| Laptop | Lenovo 83F0, Core Ultra 7 255HX, RTX 5070 Laptop |
| OS | NixOS 26.11 (generation 26.11.20261010.6510408), kernel 7.2.9 |
| NVIDIA | open kernel module 615.71.09, `nvidia-drm` modeset, `NVreg_PreserveVideoMemoryAllocations=2`, `NVreg_UseKernelSuspendNotifiers=1`, `DynamicPowerManagement=3`; no `nvidia-suspend/resume` units (kernel notifiers are used instead) |
| Desktop | KDE Plasma 6.7.5, KWin Wayland, SDDM |
| Sleep | `/sys/power/mem_sleep` = `s2idle [deep]` → S3 |
| Panel | 2560x1600@165 eDP |
| powerdevil | `[AC][SuspendAndShutdown] LidAction=0, AutoSuspendAction=0` — on AC, closing the lid does **not** suspend |

How to tell the BIOS mode from the kernel log (`tools/boot-modes.sh` does this):

| | dGPU only | hybrid |
|---|---|---|
| fb0 | `fbcon: nvidia-drmdrmfb (fb0) is primary device` | `i915 …: [drm] fb0: i915drmfb frame buffer device` |
| i915 | `failed to retrieve link info, disabling eDP` | drives eDP |
| panel connector | `card2-eDP-1` (NVIDIA) | `card1-eDP-1` (i915) |
| backlight | `nvidia_0` | `intel_backlight` |
| boot VGA | `0000:02:00.0` (NVIDIA) | `0000:00:02.0` (iGPU) |

## Resumes on 2026-10-11

Outcome legend: **bad** = user saw a black panel; **bad?** = boot ended in a hard power-off shortly after resume
(no `Journal stopped`), most likely black panel but not confirmed; **ok** = the session was used afterwards or the
boot was shut down cleanly. Journal excerpts for each line are in `logs/`.

| Resume | Boot | Mode | nvidia-powerd | Trigger | Outcome | Evidence |
|---|---|---|---|---|---|---|
| 16:26:43 | -15 | dGPU | on | Plasma menu (suspended 15:44) | **bad** | power key 16:27:40, then hard off |
| 22:04:27 | -11 | dGPU | on | `systemctl suspend` from `odvptest.sh` part E, RTC wake | **bad** | the test kept logging 30 s after resume; hard off 22:05:43 |
| 22:13:32 | -10 | dGPU | **off** (test stopped it) | `resume-screen-test.sh nopowerd` | unknown | userspace state normal in `results/…nopowerd.log`; power key 22:14:46, then hard off |
| 22:26:08 | -8 | dGPU | off | Plasma menu | ok | clean shutdown 22:30 |
| 22:32:51 | -7 | dGPU | off | Plasma menu | ok | unlocked 22:34:44 |
| 22:38:03 | -7 | dGPU | **off** | Plasma menu | **bad?** | hard off 19 s after resume |
| 22:55:01 | -5 | dGPU | on | lid close | **bad?** | lid closed/opened twice (trying to wake the panel), hard off |
| 22:58:49 | -3 | dGPU | on | Plasma menu | **bad?** | log ends 3 s after resume |
| 23:00:46 | -2 | hybrid | on | Plasma menu | ok | clean shutdown |
| 23:04:09 | -1 | hybrid | on | Plasma menu | ok | clean shutdown |
| 23:06:46 | 0 | hybrid | on | Plasma menu | ok | session used |
| 23:12:48 | 0 | hybrid | on | Plasma menu | ok | session used |

Earlier history (from `tools/boot-modes.sh`):

- **Hybrid mode until 2026-10-06 15:43**: ~20 resumes, all fine except 2026-10-01 11:46, which was a different failure
  (KWin died at resume: `The Wayland connection broke. Did the Wayland compositor die?`, `Stopped KDE Wayland Compositor`).
- **dGPU mode from 2026-10-06 15:44**. Before 2026-10-11 there was one boot with resumes (2026-10-07 18:02 – 10-10 21:26,
  generation 26.11.20261006.151fa4e, nvidia-powerd not running): **6/6 resumes fine** (10-09 21:56, 23:48, 23:49, 23:49
  (s2idle), 10-10 02:40, 09:08), three of them lid-triggered, several long sleeps.
- **2026-10-11, dGPU mode**: ≥2 confirmed + 3 probable failures out of 9 (table above).

`nix store diff-closures` between the good dGPU generation (151fa4e, 10-06) and the bad one (6510408, 10-10): kernel 7.2.9,
NVIDIA 615.71.09, KWin/Plasma 6.7.5, Mesa unchanged. Display-relevant changes are only **xwayland 24.1.13 → 24.1.14** and
the new **nvidia-powerd** unit; the rest is KDE Gear 26.08.1 → 26.08.2 apps, Firefox, Telegram etc.

Related, not a resume: boot -12 (`logs/lid-close-no-suspend-boot-12.log`). On AC the lid was closed 19:11–21:57
without suspend (`LidAction=0`). The journal ends at `Lid opened` 21:57:04 and the machine was rebooted ~1.5 min
later, possibly also a dark panel; up to ~30 s of journal is lost on a hard power-off, so this is not certain.

## What a bad resume looks like

- Kernel resume completes normally: `PM: suspend exit`, `systemd-sleep: System returned from sleep operation 'suspend'`.
- No NVRM/Xid errors, no nvidia-modeset errors at or after resume.
- powerdevil sees DRM change events on card2 and a hotplug event for `card2-eDP-1` (connector 1221), same as in good resumes.
- `kscreenlocker_greet` starts its PAM conversation (the greeter is up), NetworkManager reconnects, user services keep running.
- In 16:26 (and 22:32/22:38/22:55/22:58) KWin logs `Applying output configuration failed!` right after resume; in 22:04 it does not.
- During `resume-screen-test.sh nopowerd` (22:13, outcome unknown) userspace saw a fully normal state for 40 s:
  `nvidia_0` brightness 100/100, `bl_power=0`, `card2-eDP-1` connected/enabled/`dpms=On`, KScreen eDP-1 enabled at
  2560x1600@165, GPU P4/P5 ~8–18 W.

## Hypotheses

### Confirmed

- **H1. Tied to the BIOS dGPU-only mode.** Hybrid: 4/4 resumes fine on 2026-10-11 and the user reports it as reliable.
  dGPU only: ≥2 confirmed and 3 probable failures out of 9 on the same day. Consistent with the external reports
  below, where the only working workaround is leaving dGPU mode.

### Refuted or not discriminating

- **nvidia-powerd / Dynamic Boost** (first suspect, because it started running on 2026-10-11, the day the failures began).
  Refuted as a necessary cause: 22:38 failed with nvidia-powerd stopped for the whole boot. It may still change the
  odds; not enough samples.
- **Platform profile / MMIO PL experiments** (custom/max-power, `odvptest.sh`). Not necessary: the later failures (22:38, 22:55, 22:58)
  happened outside the test scripts, after reboots. Lasting firmware state from them is H7.
- **`ACPI: button: [Firmware Bug]: Unexpected lid state reported by firmware`** — present in good and bad resumes of
  10-11, in both modes (but see H7: absent on 10-07…10-10).
- **`spd5118 …: failed to resume async: error -6`, `xHC error in resume, USBSTS 0x401, Reinit`** — every resume.
- **KWin `Applying output configuration failed!`** — appears in most bad resumes, but also in good ones (22:32) and
  several times per boot in hybrid mode where everything works.
- **powerdevil backlight helper not running after resume** — checked across ~27 resumes, no correlation.
- **Kernel / driver / KWin update** — the same kernel 7.2.9, NVIDIA 615.71.09 and KWin 6.7.5 resumed fine 6/6 in dGPU mode
  on 2026-10-07…10-10 (see the closure diff above).
- **Suspend trigger** — fails via Plasma menu, `systemctl suspend` and lid close alike.

### Open

- **H2. NVIDIA driver does not bring the eDP link / panel power back** after S3 in dGPU mode, while its DRM state
  says the output is on (backlight 100, dpms On). Fits the userspace snapshot and the absence of KWin errors in
  22:04. Same class as NVIDIA issues #1136 and #1180 (below). Would be confirmed if KWin-level recovery (H3 test)
  does nothing.
- **H3. KWin keeps a broken output after resume** (the `Applying output configuration failed!` path), as in NVIDIA
  issue #1378 (`Setting dpms mode failed!`, `Applying KScreen config failed!`; same failure with proprietary and open
  modules). Test: on a black screen, Ctrl+Alt+F2 and back, or over SSH
  `kscreen-doctor output.eDP-1.disable; kscreen-doctor output.eDP-1.enable`, or `kscreen-doctor --dpms off/on`.
  If the panel comes back, it is H3 (or the compositor-state variant in omarchy #13251).
- **H4. Lenovo SBIOS / ACPI interaction in dGPU mode.** Every boot logs
  `NVRM: … failed to get target temp from SBIOS` and `failed to get platform power mode from SBIOS`
  (`platform_request_handler_ctrl.c`), the same lines as the Lenovo LOQ report on the NVIDIA forum. In hybrid mode
  the panel is not on the NVIDIA path at all, so these would not matter for the display. Not tested.
- **H5. `NVreg_UseKernelSuspendNotifiers=1` path** (instead of `nvidia-suspend/resume.service` + `nvidia-sleep.sh`
  with the VT switch). Not tested. Note #1378 found `=1` made things worse on their system.
- **H6. S3 vs s2idle.** Only S3 (`deep`) was used. s2idle takes a different NVIDIA resume path; LOQ reporters fail
  on s2idle too, so low expectations. Not tested.
- **H7. Something changed on 2026-10-11 besides software.** dGPU mode was 6/6 fine on 10-07…10-10 and ~50% bad on
  10-11 with an almost identical software stack (xwayland 24.1.14 is the only display-side update). Candidates: firmware /
  EC state left by the power experiments of that day (Lenovo custom mode, MMIO PL writes, Dynamic Boost, see
  `../lenovo-83f0-dynamic-boost-power`), surviving warm reboots but maybe not a full power-off or BIOS mode change;
  or plain chance (6 samples, 1.6% probability of 6/6 at a 50% failure rate, so chance is unlikely). A hint that the
  firmware behaves differently since 10-11: `ACPI: button: [Firmware Bug]: Unexpected lid state reported by firmware`
  appears on **every** resume of 10-11 (both modes, good and bad) and on **none** of the six 10-07…10-10 resumes (it was
  also seen on some hybrid resumes in late September, so it is a marker, not the cause). Test: a few
  resumes in dGPU mode after a cold power-off with nvidia-powerd disabled and no profile changes.
- **H8. Lid state / sleep length.** On 10-11 most suspends were short (30 s – 40 min) with the lid open (menu,
  `systemctl`, RTC wake); on 10-07…10-10 several were lid-triggered and hours long. But 22:55 (lid-triggered) also
  failed and short lid-open sleeps on 10-09 23:48–23:49 were fine. Weak.
## Reports from others

- NVIDIA forum, **Lenovo LOQ 15ARP9, RTX 4060, dGPU only, open module 610.43.03, KDE Wayland**: black screen after
  resume, hard reboot needed. Same `failed to get … from SBIOS` lines. Another user (Legion **17IRX10**) reports the
  same on 8+ distros; the only workaround is switching the BIOS out of discrete-GPU mode. No NVIDIA reply, unresolved.
  https://forums.developer.nvidia.com/t/suspend-failure-black-screen-on-lenovo-loq-ryzen-7435hs-rtx-4060-with-open-kernel-module-610-43-03/377642
- NVIDIA/open-gpu-kernel-modules **#1136**: Lenovo LOQ, RTX 4070 Mobile, Wayland/Niri, nvidia-open 595.71.05 —
  displays stay black after resume, VT switch does not help, reproduces when suspending from a plain TTY.
  https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1136
- NVIDIA/open-gpu-kernel-modules **#1180**: RTX 5070 (Ti) Laptop and others — internal eDP black in dGPU mode at
  boot (KMS handoff) with 610.43.02/610.57.04, good on 595.x, reported fixed in **615.71.09** (the version used here).
  Shows the dGPU→eDP bring-up path regressed recently; ours is the resume variant.
  https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1180
- NVIDIA/open-gpu-kernel-modules **#1378**: RTX 3070 desktop, KWin Wayland, 595.x — after S3, KWin permanently loses
  its output, intermittent, no NVRM/Xid. Same with proprietary module; reporter thinks the trigger is outside the
  kernel module. Recovers by logout/session restart.
  https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1378
- omarchy **#13251**: Lenovo LOQ 15ARP9, dGPU only, s2idle — panel dark after resume while the compositor (Hyprland)
  reports DPMS on; forcing DPMS off/on is the workaround there.
  https://github.com/omacom/omarchy/issues/13251
- Generic NVIDIA resume black-screen threads (Artix, Mint, CachyOS, EndeavourOS) mostly predate kernel suspend
  notifiers and are fixed by `nvidia-sleep.sh` tweaks or `PreserveVideoMemoryAllocations`; not specific to MUX laptops.

## Next steps (only if dGPU-only mode is wanted again)

1. On the next black screen, before powering off: try Ctrl+Alt+F2 → Ctrl+Alt+F1, brightness keys, and over SSH the
   `kscreen-doctor` disable/enable above. This separates H2 from H3.
2. Save the journal before powering off. A short power-key press does **not** help: KDE (powerdevil) takes the key and
   opens its logout screen, which is invisible on a dark panel (16:26 and 22:14 both ended in a hard power-off after
   `Power key pressed short`). Either `systemctl poweroff` over SSH, or press Alt+SysRq+S (emergency sync, allowed by
   the current `kernel.sysrq` = 16), wait a few seconds, then hold power. A hard power-off without sync loses up to
   ~30 s of journal.
3. Run `sudo bash resume-screen-test.sh` several times with and without `nopowerd` and note for each run whether the
   panel lit; the log alone cannot tell (userspace state looks normal in bad resumes).
4. Try `nvidia.NVreg_UseKernelSuspendNotifiers=0` with the `nvidia-suspend/resume` units (H5), and `mem_sleep_default=s2idle` (H6).
5. If H2 holds, collect `nvidia-bug-report.sh` right after a bad resume (over SSH) and add it to the LOQ forum thread
   or a new open-gpu-kernel-modules issue.

## Files

- `resume-screen-test.sh` — suspend with RTC wake after 25 s; logs backlight, eDP sysfs state, lid, platform profile,
  KScreen outputs and `nvidia-smi` before and 1–40 s after resume. `sudo bash resume-screen-test.sh [nopowerd]`.
- `results/resume-test-1011-221300-nopowerd.log` — the one run so far (22:13, dGPU mode, nvidia-powerd stopped).
- `logs/resume-HHMMSS-bootN.log` — journal excerpts from the suspend request to 2 min after each resume on 2026-10-11
  (powerdevil udev spam filtered). `logs/lid-close-no-suspend-boot-12.log` — the lid-close-on-AC case.
  Boot offsets are relative to boot `9363782344b04779a0a986237328bccb` (2026-10-11 23:05:52).
- `tools/boot-modes.sh` — per boot: GPU mode, nvidia-powerd, resume times, how the boot ended.
- `tools/resume-summary.py` — per resume: trigger (lid or not), lid firmware-bug line, KWin output failure, what followed.
- `tools/backlighthelper-around-resume.py` — per resume: whether powerdevil's backlight helper ran (no correlation found).
  Both Python tools take boot offsets as arguments: `python3 tools/resume-summary.py $(seq -40 0)`.
