# txmake "Send to" script

`txmake-sendto.cmd` converts image files to RenderMan `.tx` textures with
Pixar's `txmake`, writing each `.tx` into the same folder as its source image.

## Install (scripted)

Copy both files somewhere stable, e.g. `C:\Scripts\`, then run:

```
powershell -ExecutionPolicy Bypass -File C:\Scripts\install-shortcuts.ps1
```

That creates two shortcuts to `txmake-sendto.cmd`:

- **Desktop** — a drag-and-drop target. Drop one or many images on it.
- **Send to** — the Explorer right-click entry.

Useful switches: `-Name "Make TX"` to rename the entry, `-SkipDesktop` /
`-SkipSendTo` to create only one, `-IconLocation "C:\icons\tx.ico"` to set the
icon, and `-Uninstall` to remove the shortcuts again.

## Install (manual)

1. Copy `txmake-sendto.cmd` somewhere stable, e.g. `C:\Scripts\`.
2. Press <kbd>Win</kbd>+<kbd>R</kbd>, type `shell:sendto`, press Enter. That
   opens `%APPDATA%\Microsoft\Windows\SendTo`.
3. Right-drag `txmake-sendto.cmd` into that folder and choose
   **Create shortcuts here**.
4. Rename the shortcut to whatever you want the menu entry to read, e.g.
   `Convert to .tx`. Optionally set an icon via Properties → Change Icon.

Put the *shortcut* in SendTo rather than the script itself — that keeps the
script editable in one place and lets you rename the menu entry freely.

For a desktop drop target, right-drag the same `.cmd` onto the Desktop and
choose **Create shortcuts here**.

## Use

Drag images onto the Desktop shortcut, or select them in Explorer →
right-click → **Send to** → **Convert to .tx**. On Windows 11 the Send to menu
is under **Show more options**, or hold <kbd>Shift</kbd> while right-clicking.

Dropping images from several different folders at once is fine — each `.tx` is
written beside its own source.

It also runs fine from a command prompt:

```
txmake-sendto.cmd "C:\tex\brick_diff.tif" "C:\tex\brick_spec.tif"
```

## Finding txmake.exe

The script looks in this order and uses the first hit:

1. `%TXMAKE_EXE%` — full path to the executable, if you set it.
2. `%RMANTREE%\bin\txmake.exe` — set by a normal RenderMan install.
3. The highest-numbered `RenderManProServer-*` folder under `Program Files\Pixar`.
4. `txmake.exe` anywhere on `PATH`.

If none of those match your setup, set `TXMAKE_EXE` as a user environment
variable, or edit the `:find_txmake` section.

## Configuration

Edit the config block at the top of the script:

| Variable | Purpose |
|---|---|
| `TXOPTS` | Flags passed to `txmake`. Default: `-resize none -mode periodic -format openexr -compression lossless` |
| `IMAGE_EXTS` | Extensions the script will process. Anything else is skipped with a message. |
| `SKIP_EXISTING` | `1` = skip a file whose `.tx` is already newer than the source. Set to `0` to always reconvert. |
| `ALWAYS_PAUSE` | `1` = keep the console open even on full success. The window always stays open when something fails. |

Useful `TXOPTS` variations:

- `-mode clamp` — for maps that should not tile (badges, decals, cards).
- `-smode periodic -tmode clamp` — different wrap per axis.
- `-format pixar` — the legacy Pixar texture format instead of tiled OpenEXR.
- `-compression dwaa` — lossy but much smaller; fine for colour maps, avoid for
  displacement, normals, or anything used as data rather than colour.
- `-t:8` — thread count on large inputs.

Run `txmake` with no arguments to see the full flag list for your RenderMan
version.

## Notes and limits

- **Multi-select is bounded.** "Send to" passes every selected path on one
  command line, and Windows caps that at roughly 8191 characters. Selecting a
  few hundred files with long paths can silently truncate the list. For bulk
  jobs, run the script from a command prompt with a `for /r` loop instead.
- **Dropped folders are skipped**, not recursed. The script reports them rather
  than failing.
- **Drag-and-drop onto an elevated target does not work.** If you ever wrap this
  in a "run as administrator" shortcut, Windows will silently refuse the drop.
  Nothing here needs admin rights, so leave it unelevated.
- Failures leave the console window open so you can read `txmake`'s error.
