# Missing-frame checker. Companion to gui_batch_render.py.
# Point BASE anywhere (render root, version folder, pass folder) -- it walks
# recursively, and every folder containing .####.exr files is checked against
# the range. Prints only folders with gaps, as "relative\path: 1090,1095-1100".
# The printed spec pastes straight into gui_batch_render.py's FRAMES
# (use MODE = "add" to fill holes in an existing version).
# Pure Python: runs in Katana's Python tab, mayapy, or anywhere.

import os, re

BASE   = r"T:\jobs\tsgb\shot\e103\e103_011_010\e103_011_010_0020\lgt\lgt\renderTest"
FRAMES = "1090-1100"        # '1238-1325', '1240', or '1238-1240,1250,1300-1302'

def parseFrames(spec):
    frames = set()
    for part in str(spec).replace(" ", "").split(","):
        if "-" in part:
            a, b = part.split("-")
            frames.update(range(int(a), int(b) + 1))
        elif part:
            frames.add(int(part))
    return frames

def condense(frames):
    """[1,2,3,7,9,10] -> '1-3,7,9-10'"""
    out, start, prev = [], frames[0], frames[0]
    for f in frames[1:] + [None]:
        if f != (prev + 1 if prev is not None else None):
            out.append(str(start) if start == prev else "%d-%d" % (start, prev))
            start = f
        prev = f
    return ",".join(out)

def checkFrames(base, spec):
    wanted = parseFrames(spec)
    pat = re.compile(r"\.(\d+)\.exr$", re.IGNORECASE)
    for root, dirs, files in os.walk(base):
        found = set(int(m.group(1)) for m in (pat.search(f) for f in files) if m)
        if not found:
            continue
        missing = sorted(wanted - found)
        if missing:
            print("%s: %s" % (os.path.relpath(root, base), condense(missing)))

checkFrames(BASE, FRAMES)
