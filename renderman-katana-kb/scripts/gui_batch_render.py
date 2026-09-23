# GUI batch render for Katana (no shell access required).
# Run from the Python tab or save as a user shelf item:
#   %USERPROFILE%\.katana\Shelves\Lighting\renderRange.py
#
# What it does, in order:
#   1. Cooks the render node's outputs and derives the render root
#      (everything before the \vXXX\ segment of the first output path).
#   2. Finds the highest existing vXXX on disk, uses the next one.
#   3. Writes that version to the render node's user.version parameter
#      (preserving "v002" vs "002" format). NOTE: if user.version is
#      expression-driven, setValue will not override it.
#   4. Creates the output folders (writers do NOT create their own dirs --
#      cryptomatte/stats outputs fail silently into nothing without them).
#   5. Disk-renders the frame range SERIALLY.
#
# Hard-won gotchas baked in:
#   - RenderManager.StartRender is ASYNCHRONOUS by default: a bare loop
#     fires renders on top of each other and only the last frame survives
#     (or renderboot.exe processes crash with 0xC0000005 fighting over the
#     session temp dir). settings.asynch = False makes each call block.
#     The UI freezes during each frame; prints show progress.
#   - RenderingSettings fields worth knowing (Katana 6.5): asynch,
#     allowWaitingForRenderCompletion, frame, frameRanges,
#     renderCompletionCB, interactiveOutputs.
#   - StartRender returns a list of dicts describing created outputs --
#     print it to verify frames land on the filer, not in C:/tmp.
#   - TriggerManualRender() is NOT a scriptable disk render (it repeats
#     the last render, for Manual-mode interactive rendering).

import os, re
from Katana import NodegraphAPI, RenderManager, FnGeolib, Nodes3DAPI

# ---------------- settings ----------------
NODE_NAME = "L020_INT_bg_data"     # render node (= pass folder name)
FOLDERS   = ["crypto_material", "crypto_object", "matteID", "primary", "tech", "stats"]
FRAMES    = "1049-1049"            # '1238-1325', '1240', or '1238-1240,1250,1300-1302'
MODE      = "up"                   # "up"  = next free vXXX, sets user.version
                                   # "add" = keep user.version as-is, write into the
                                   #         existing version (overwrite/fill frames)
# ------------------------------------------

def getRenderRoot(node):
    """Cook the node's first output path and split it at the version folder."""
    runtime = FnGeolib.GetRegisteredRuntimeInstance()
    txn = runtime.createTransaction()
    client = txn.createClient()
    txn.setClientOp(client, Nodes3DAPI.GetOp(txn, node))
    runtime.commit(txn)
    outs = client.cookLocation("/root").getAttrs().getChildByName("renderSettings.outputs")
    for i in range(outs.getNumberOfChildren()):
        loc = outs.getChildByName(outs.getChildName(i)).getChildByName("locationSettings.renderLocation")
        if loc is None:
            continue
        path = loc.getValue()
        m = re.search(r"[\\/]v\d+[\\/]", path)
        if m:
            return path[:m.start()]            # everything before \vXXX\
    return None

def makeVersionedFolders(renderRoot, passName, node, mode):
    vparam = node.getParameter("user.version")
    if vparam is None:
        print("no user.version parameter on", node.getName())
        return None
    old = str(vparam.getValue(0))

    if mode == "up":
        versions = [int(m.group(1)) for m in
                    (re.match(r"v(\d+)$", d) for d in os.listdir(renderRoot))
                    if m] if os.path.isdir(renderRoot) else []
        version = "v%03d" % (max(versions) + 1 if versions else 1)
        vparam.setValue(version, 0)                     # always vXXX format, e.g. v001
        print("user.version: %s -> %s" % (old, version))
    else:                                   # "add": render into the current version
        version = old if old.startswith("v") else "v" + old
        print("using existing version:", version)

    base = os.path.join(renderRoot, version, passName)
    for name in FOLDERS:
        os.makedirs(os.path.join(base, name), exist_ok=True)
        print("ensured:", os.path.join(base, name))
    return version

def renderRange(node, frameSpec):
    frames = []
    for part in str(frameSpec).replace(" ", "").split(","):
        if "-" in part:
            a, b = part.split("-")
            frames.extend(range(int(a), int(b) + 1))
        elif part:
            frames.append(int(part))

    s = RenderManager.RenderingSettings()
    s.asynch = False                          # CRITICAL: serial, blocking renders
    s.allowWaitingForRenderCompletion = True

    for i, f in enumerate(frames, 1):
        s.frame = f
        print("rendering %d  (%d of %d)" % (f, i, len(frames)))
        RenderManager.StartRender("diskRender", node=node, settings=s)
    print("all %d frames done" % len(frames))

# ---------------- run ----------------
node = NodegraphAPI.GetNode(NODE_NAME)
if node is None:
    print("Render node not found:", NODE_NAME)
else:
    renderRoot = getRenderRoot(node)
    if renderRoot is None:
        print("could not find a vXXX version folder in the node's output paths")
    else:
        print("render root:", renderRoot)
        if makeVersionedFolders(renderRoot, NODE_NAME, node, MODE) is not None:
            renderRange(node, FRAMES)
