# Per resume in the given boots (journalctl offsets): sleep mode, lid-triggered or not, "Unexpected lid state" line,
# KWin "Applying output configuration failed!", power key soon after, and what followed. Usage: python3 resume-summary.py $(seq -40 0)
import subprocess, sys, datetime as dt, re
def lines(b):
    out = subprocess.run(["journalctl","-b",b,"-o","short-unix","--no-pager","-q"],capture_output=True,text=True).stdout
    for l in out.splitlines():
        try: t,rest=l.split(" ",1); yield float(t),rest
        except: pass
for b in sys.argv[1:]:
    L=list(lines(b))
    if not L: continue
    end=L[-1][0]
    exits=[t for t,r in L if "PM: suspend exit" in r]
    entries=[(t,r) for t,r in L if "PM: suspend entry" in r]
    for ex in exits:
        ent=max([e for e in entries if e[0]<ex], default=(None,""))
        trig="?"
        for t,r in L:
            if ent[0] and ent[0]-30<t<ent[0]:
                if "Lid closed" in r: trig="lid"
        win=[r for t,r in L if ex-5<t<ex+90]
        lidbug="Unexpected lid state" in " ".join(r for t,r in L if ex-3<t<ex)
        outfail=any("Applying output configuration failed" in r for r in win)
        nxt=min([e[0] for e in entries if e[0]>ex], default=None)
        pk=[t for t,r in L if "Power key pressed" in r and ex<t<(nxt or end+1)]
        after = (nxt or end)-ex
        print(f"boot {b:>4} exit {dt.datetime.fromtimestamp(ex):%m-%d %H:%M:%S} mode={ent[1].split('entry ')[-1]:<9} trig={trig:<3} lidFWbug={lidbug!s:<5} kwinOutFail={outfail!s:<5} powerkey={'Y' if pk else '-'} then={'next-suspend' if nxt else 'BOOT-END'} after {after/60:.1f} min")
