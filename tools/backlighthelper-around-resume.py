# Per resume in the given boots: whether powerdevil's backlight helper was started before the sleep / after resume.
# Usage: python3 backlighthelper-around-resume.py $(seq -40 0)
import subprocess, sys, datetime as dt
for b in sys.argv[1:]:
    out=subprocess.run(["journalctl","-b",b,"-o","short-unix","--no-pager","-q"],capture_output=True,text=True).stdout
    L=[]
    for l in out.splitlines():
        try: t,r=l.split(" ",1); L.append((float(t),r))
        except: pass
    if not L: continue
    end=L[-1][0]
    ent=[t for t,r in L if "PM: suspend entry" in r]
    for ex in [t for t,r in L if "PM: suspend exit" in r]:
        e=max([x for x in ent if x<ex])
        pre=[t for t,r in L if "backlighthelper" in r and "Started" in r and e-600<t<e]
        post=[t for t,r in L if "backlighthelper" in r and "Started" in r and ex-3<t<ex+60]
        nxt=min([x for x in ent if x>ex], default=None)
        after=((nxt or end)-ex)/60
        pk=any("Power key" in r for t,r in L if ex<t<ex+600)
        print(f"{b:>4} {dt.datetime.fromtimestamp(ex):%m-%d %H:%M:%S} helper_before_sleep={'Y' if pre else '-'} helper_after_resume={'Y' if post else '-'} next={'suspend' if nxt else 'END'} after={after:.1f}m powerkey<10m={'Y' if pk else '-'}")
