# Read !!LoadStopwatch measurement runs from SavedVariables, newest last.
# Usage: py -3 _read_stopwatch.py [N]   (N = only the last N runs)
import io
import sys

PATH = (r"C:\Program Files (x86)\World of Warcraft\_anniversary_"
        r"\WTF\Account\1107979492#1\SavedVariables\!!LoadStopwatch.lua")

runs = []
try:
    for line in io.open(PATH, encoding="utf-8"):
        s = line.strip()
        # run summary strings all start with the ISO date: "2026-...
        if s.startswith('"20'):
            runs.append(s.rstrip(",").strip('"').replace('\\"', '"'))
except FileNotFoundError:
    print("No stopwatch SavedVariables yet:", PATH)
    sys.exit(1)

n = int(sys.argv[1]) if len(sys.argv) > 1 else len(runs)
if not runs:
    print("No runs recorded yet.")
for r in runs[-n:]:
    print(r)
