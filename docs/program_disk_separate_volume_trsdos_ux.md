Your concept doc already lines this up well: **“Program editor/store”** plus **`SAVE` / `LOAD` / `FILES` / `DEL` / `REN`** are the right surface; the separate volume should be **implementation detail + one invisible boot step**, not a new “OS personality.”

Here are practical patterns that keep the feel TRSDOS-ish without turning the machine into Linux.

### 1. **Two logical drives, one vocabulary (strongest fit)**

Treat storage like **drive 0 vs drive 1**, not paths:

- **Drive 0 (internal):** whatever lives on the main image (read-only library, scratch, or “nowhere” if you want everything off-root).
- **Drive 1 (external):** the second block device / USB / virtio disk image the user attaches in QEMU or hardware.

User-facing commands stay familiar:

- `DRIVE 0` / `DRIVE 1` (or `USE 0` / `USE 1` if you want fewer letters than TRSDOS)
- Then unchanged `FILES`, `LOAD "NAME"`, `SAVE "NAME"`, `DEL`, `REN` against the **current drive**.

Under the hood, MBASIC resolves to different roots (`/var/lib/trs-ai/programs` vs `/run/trs-ai/volume1` or similar). **Mounting happens only at boot (or on “disk change”), never as a user ritual.**

This matches your “BASIC first” list in [trs80_ai_basic_appliance_concept.md](./trs80_ai_basic_appliance_concept.md) — you’re just namespacing where those commands point.

### 2. **Boot-time automation: “disk always there if present”**

On appliance boot (systemd unit **before** `trs-ai-basic`):

- If the expected device node exists (e.g. second virtio disk), **mount** to a fixed mountpoint with stable options (sync or `dirsync` if you care about unplug safety).
- If it’s **unformatted**, you have a product choice:
  - **Silent mkfs once** (dangerous on wrong device; only if the device identity is unambiguous), or  
  - **BASIC-visible message:** `PROGRAM DISK NOT FORMATTED` / `INSERT PROGRAM DISK` and keep drive 1 unavailable until a maintenance path formats it, or  
  - **Preformatted image** shipped as a second `.qcow2` the user attaches — zero format surprises.

The user never runs `mount`; they only see **READY** or a **single line** on the splash if something’s wrong (“NO PROGRAM DISK”).

### 3. **FAT32 on the exchange volume (low friction with the outside world)**

If the goal is **get `.BAS` files in and out without Linux on the host**, putting **FAT32** on that second volume is underrated:

- Windows/macOS/Linux all read it trivially when the image is attached elsewhere.
- Your appliance still uses normal file APIs; only the **filesystem choice** changes.

You stay “not Linux” in the UI; the volume is just **“the program disk.”**

### 4. **Optional: “eject” as a BASIC metaphor, not `umount`**

If the medium can disappear (USB):

- Add **`EJECT`** or **`DISK OFF`** that **flushes**, closes files, and **unmounts** safely — still one **BASIC** word, not a shell lesson.
- **`DISK ON`** / replug could trigger udev + automount, or require reboot for v1 simplicity.

### 5. **What I’d avoid for “feel”**

- Exposing **paths** (`SAVE "/mnt/foo/bar.bas"`) as the primary model.
- A **file manager** or **shell-like** catalog of directories unless you truly want TRSDOS depth.
- Making the user **attach + mount + chmod** — that’s exactly the Linux leak you’re trying to avoid.

### 6. **Scope control relative to your milestone plan**

This doesn’t have to be a huge detour:

- **Phase A:** Second partition or disk image, fixed mountpoint, env var or config `TRS_AI_PROGRAM_DISK=/…`, implement **drive select** + path prefix in SAVE/LOAD/FILES.
- **Phase B:** FAT32 + documented “second image” workflow for QEMU.
- **Phase C:** Hotplug / EJECT if you need removable media story.

---

**Bottom line:** Present the separate volume as **“drive 1” / “program disk”**, automate **mount + identity** at boot, keep **`LOAD` / `SAVE` / `FILES`** as the only exchange verbs, and choose **FAT32** if cross-machine friction matters. Linux stays a boot script detail, consistent with principle 3 in your concept doc (“The host OS stays hidden”).
