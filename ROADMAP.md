# Phoenix Music roadmap

> **Status: proposed, not confirmed.** This is where Phoenix Music *might* go. Nothing here is promised, and every item still needs proper discussion before it's built. Things will change, move or get dropped, especially once we've worked through the hard limits below.

> **Note:** some ideas here depend on two other Phoenix Software projects that **don't exist yet and are still in development**: the **Phoenix Pro Hardware & Networking** add-on mod and **Phoenix OS**. Anything that relies on them can't happen until they're released.

Phoenix Music has to keep working on a plain CC: Tweaked computer running the normal CraftOS shell, with nothing else installed. Everything below is an extra on top of that, never a requirement.

---

## Hard limits we have to design around

These come from CC: Tweaked itself (default server config). Server owners can change some of them, but we have to assume the defaults.

| Limit | Default | What it means for us |
| --- | --- | --- |
| Computer disk space | **1,000,000 bytes (1MB)** per computer | Phoenix Music alone is ~145KB, about 15% of a computer. A 3-minute song in DFPWM is ~1MB, so **saving even one song locally doesn't fit** on a default computer. |
| Floppy disk space | **125,000 bytes** | About 20 seconds of audio. Useless for music storage. |
| Computer threads | **1** for the whole Minecraft server | Every computer on the server shares one thread. Heavy work (decoding, smoothing, visualiser, redraws) slows everyone down, and inside Phoenix OS the OS and every window share one computer's time. |
| "Too long without yielding" | A few seconds of non-stop work | Long jobs (decoding, big JSON) must keep pausing, or the program gets killed. |
| Lua locals | **200 per function** | The single-file player is already at ~135 at its worst point. New big features need the code split into modules first. |
| Speaker buffer | **128K samples (~2.7s)** per `playAudio` call, one call queued | Audio must be fed in chunks. Volume only changes when a speaker restarts, hence the blip. |
| Wireless modem range | **64 blocks** (384 up high) | Speaker Link and playlist sync need ender modems for long range. |
| HTTP download size | Capped per request (default config) | Very long tracks may need to be fetched in parts rather than in one download. To be checked. |
| File upload (drag and drop) | **512KB** | Players can't drop a full song file onto a computer, so local music has to come from a URL, a disk drive or a NAS. |
| Screen sizes | Computer 51x19, pocket 26x20, monitors up to 8x6 blocks | Every screen must cope with small sizes, and with arbitrary window sizes inside Phoenix OS. |

**The big one is storage.** Phoenix OS will have a **Standard** edition that uses the computer's own disk (the same 1MB, shared with the OS, other apps and the user's files) and an **enterprise** edition that can use NAS storage. So:

- Phoenix Music must stay **small** and install **only the parts a device needs**.
- Anything that stores audio (saved songs, offline music) only makes sense on a **NAS**, a raised server limit, or extra storage hardware. It **can't be assumed on Standard**.
- Streaming stays the default everywhere.

---

## Ideas under discussion

### 1. Small updates to the current player
- **Music server setting** under Settings → Advanced, behind a warning: connection test before saving, a reset button, and an option for server owners to lock it.
- **Backup server list** (`servers.txt` in this repo): if the main server dies, every install can be moved to a backup by editing one file.
- **Clear "server down" message** instead of generic network errors.
- **Playlist sync** over the Link name and PIN: opt-in, merges changes, remembers deletions.
- **Add to playlist from the remote.**

### 2. Backend safety net
- **Backend adapters** so the player isn't tied to one server's format.
- **Our own backend (optional)**: terreng's server (MIT) on Cloud Run with paid YouTube APIs (via RapidAPI), plus caching, an app key and a length cap. Not hosted from home. (Playing YouTube directly from CC isn't possible, so some backend is always needed.)
- **Support for other backends** (for example JzJad's, if and when it's published, with his blessing).
- **Local / URL DFPWM playback** for when no server is available. Limited by storage (see above).

### 3. Restructure: engine + screens
- One **engine** (audio, queue, search, Speaker Link, remote protocol) with no screen code.
- Separate **screens** on top: full player, linked speaker, remote, Lite, and a Phoenix OS app.
- **Small installs**: a linked speaker or remote only downloads what it needs. This matters most on Phoenix OS Standard.
- **Multi-file updater** driven by a file list in this repo.
- Fixes the Lua locals ceiling and keeps the code workable.

### 4. Installer
- One command (Pastebin / Pinestore) that detects the computer type and peripherals and only offers modes that will work.
- Optional start-on-boot (especially for linked speakers), Link name and PIN asked during install.

### 5. Phoenix Music Lite
- For **standard (grey) computers**: keyboard-driven, greyscale.
- Search, queue, playlists, Now Playing, maybe the visualiser.

### 6. Phoenix Pro Hardware & Networking integration
*The add-on mod is still in development and hasn't been released yet.* Only used when the hardware is present; never required.
- **Advanced speaker**: volume changes without restarting, and possibly better sound. Its API is defined only in the mod's [DESIGN.md](https://github.com/MADDXSTUDIOS/CCSN/blob/dev/DESIGN.md); this repo links to it and never keeps its own copy.
- **Higher-resolution computer**: more room on screen.
- **Laptop**: detected like any other device.
- **Rooms**: zoned audio, with each player only seeing its room's speakers.
- **NAS**: a central music library and space for saved songs (enterprise setups).

### 7. Phoenix OS
*Phoenix OS is still in development and hasn't been released yet.*
- **Hosted mode**: no palette changes that recolour the whole desktop, no drawing outside its window, settings and playlists in the user's folder, updates through the OS's App Store, and the OS's networking instead of taking over modems.
- Must work on **both Standard (local disk only) and enterprise (NAS)** editions.
- **Background music service** with the window as a remote, plus taskbar controls.
- Possibly a **Phoenix Core music role** for building-wide audio.
- CPU budget matters here: the OS, its windows and the music share one computer's time.

---

## Open questions
- Self-hosting: officially supported with a guide, or just allowed?
- Our own backend: needed now, or only if terreng's goes down?
- How far can audio storage go on Phoenix OS Standard, if at all?
- What's the minimum feature set for the Phoenix OS app on Standard?
