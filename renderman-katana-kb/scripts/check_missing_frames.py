# Missing-frame checker. Companion to gui_batch_render.py.
# Walks BASE recursively; any folder containing .####.exr files is checked
# against FRAMES. Prints one line per folder that has gaps:
#     v001\L020_INT_bg_data\primary: 1090-1093,1095
# The printed spec pastes straight into gui_batch_render.py's FRAMES
# (use MODE = "add" to fill holes in an existing version).
# Folders with no EXRs are ignored; folders with no gaps print nothing.
# Pure Python: runs in Katana's Python tab or anywhere.

import os, re

# Path to scan (render root, version folder, or pass folder -- any level works)
BASE   = r"T:\jobs\tsgb\shot\e103\e103_011_010\e103_011_010_0020\lgt\lgt\renderTest"
# Expected frames: '1090-1100', '1240', or mixed '1238-1240,1250,1300-1302'
FRAMES = "1090-1100"

def parseFrames(spec):
    """Expand a frame spec string into a set of ints.
    '1090-1092,1095' -> {1090, 1091, 1092, 1095}"""
    frames = set()
    for part in str(spec).replace(" ", "").split(","):   # tolerate spaces
        if "-" in part:
            a, b = part.split("-")
            frames.update(range(int(a), int(b) + 1))     # inclusive range
        elif part:
            frames.add(int(part))                        # single frame
    return frames

def condense(frames):
    """Opposite of parseFrames: sorted list of ints -> compact spec string.
    [1,2,3,7,9,10] -> '1-3,7,9-10'"""
    out, start, prev = [], frames[0], frames[0]
    # walk the list; None sentinel flushes the final run
    for f in frames[1:] + [None]:
        if f != (prev + 1 if prev is not None else None):    # run broken
            out.append(str(start) if start == prev else "%d-%d" % (start, prev))
            start = f                                        # begin new run
        prev = f
    return ",".join(out)

def checkFrames(base, spec):
    wanted = parseFrames(spec)
    # frame number = digits between the last '.' and '.exr'  (name.1094.exr)
    pat = re.compile(r"\.(\d+)\.exr$", re.IGNORECASE)
    for root, dirs, files in os.walk(base):              # recursive descent
        # collect every frame number present in this folder
        found = set(int(m.group(1)) for m in (pat.search(f) for f in files) if m)
        if not found:
            continue                                     # no EXRs -> not an output folder
        missing = sorted(wanted - found)
        if missing:
            # label with the path relative to BASE so output stays readable
            print("%s: %s" % (os.path.relpath(root, base), condense(missing)))

checkFrames(BASE, FRAMES)
