# Handover: start here

For anyone (or any fresh chat) picking Phoenix Music up. Read this first, then
[ROADMAP.md](ROADMAP.md) (proposed next steps and CC's hard limits) and
[README.md](README.md) (what players see). **These docs are the source of
truth, not chat history.** Keep this file up to date when something important
changes.

*Last full update: 17 October 2026, at v3.8.1.*

---

## 1. What this is

**Phoenix Music** is a music player for **CC: Tweaked** (the ComputerCraft mod for Minecraft), published by **Phoenix Software** (Aaron's label; GitHub org **MADDXSTUDIOS**). It searches YouTube and streams audio to in-game speakers.

- **Based on** terreng's (Terren Gurule's) [computercraft-streaming-music](https://github.com/terreng/computercraft-streaming-music) (MIT). Phoenix Music started as a reskin and is now a heavily extended rewrite of his client. It still uses **terreng's free music server** for search and audio.
- **Who it's for:** anyone playing CC: Tweaked, especially people who want music around a base (synced speakers, remotes), not just one computer with a speaker.
- **End goal:**
  1. The best CC music player: polished UI, multi-room synced audio, remotes, auto-updates.
  2. Survive terreng's server going away (backend redundancy).
  3. Eventually run as an app inside **Phoenix OS** (Aaron's Windows-style OS for CC, in development), and use hardware from Aaron's add-on mod **CC: Phoenix Pro Hardware & Networking** (in development).
- **Hard rule:** it must **always work on a plain CC: Tweaked computer running the normal CraftOS shell**, with nothing else installed. Phoenix OS and the add-on mod are optional extras that are detected, never required.

---

## 2. Current state (v3.8.1, released 16 Oct 2026)

### Built and working (tested in-game by Aaron)
- **Player tabs:** Playing, Search, Queue, Settings, About. On narrow screens the tabs are "Now / Find / Queue / Set", and About is reached from Settings.
- **Search** YouTube, or paste a video or playlist link. Live streams and videos of 15 minutes or more are hidden by default ("Long & live videos: Hidden/Shown"). Search **retries twice, 2 seconds apart**, before showing "Network error", and the error now shows the reason (e.g. "The server said 500", "Couldn't read the results: …").
- **Controls:** play/pause, stop, previous, next, restart, loop (off/queue/song), shuffle, seek (tap or drag the bar; the seek applies on release), volume (0–3 in 0.25 steps, shown as %), mute.
- **Gapless-ish playback:** the next song is **prefetched** while the current one plays (`X.maybePrefetch`, `X.peekNext`; the shuffle pick is chosen early and kept in `X.next_pick`).
- **In-memory song cache:** last **4 songs / 6MB** (`X.CACHE_MAX`, `X.CACHE_BYTES`) for instant replays.
- **Library:** Favourites (heart), playlists (max 50 playlists, 500 tracks each), Recently played (50). **Heart on Now Playing**, with a **+ box under it** to add the current song to a playlist (3.8.0).
- **Queue:** reorder, remove, play now, add to playlist, shuffle, save as playlist, clear.
- **Picks up where you left off:** queue, song, position and settings survive a restart.
- **Speaker Link:** play through speakers on other computers, in sync. Per-speaker volume (−/+ in Settings), with confirm-and-resend if the message is lost (3.7.3). Linked speakers rejoin instantly after a volume change by replaying their recent audio (3.7.5). There's a **Resync** button (Settings → Speaker Link → "Out of sync?", 3.8.0), plus a warning if another player is on the same Link.
- **Wired speakers:** speakers on a wired modem network act as the player's own speakers. Speaker Link and the remote need a **wireless or ender** modem.
- **Remote mode:** control a player from another computer or pocket. It locks to one host (3.6.3).
- **Mode switching inside the app:** Settings → "Use as remote" / "Use as speaker". A computer with a modem but no speaker asks once which it should be.
- **Standard (grey) computers** auto-run as a linked speaker (they can't show the player). The linked-speaker screen has buttons (Link, PIN, −, +, Check/Update, Player) on advanced computers, and keys (l, p, +/−, u, q) on all.
- **Per-mode Link name and PIN:** the player, remote and linked speaker on one computer each keep their own (3.6.4).
- **Monitors:** run on a monitor (`phoenixmusic monitor_0 0.5`), or **mirror** the player onto a monitor while still using the computer (Settings → Appearance → Monitor, with Small/Large text), or start it with `monitor right phoenixmusic`, which now mirrors instead of blanking the computer (3.7.0/3.7.1). The monitor is tappable; typing happens on the computer.
- **Themes:** backgrounds Dark/Midnight/Light, plus 8 accent colours (palette remap).
- **Visualiser** (fake spectrum from loudness and treble, teletext bars). **Smoothing** (light low-pass filter on/off).
- **Sleep timer** (minutes or after this song), **alarm** (at a Minecraft time, optionally playing a playlist), **redstone trigger** (play/pause, next, or play a list).
- **Settings descriptions:** a short dimmed line under the non-obvious settings (3.7.2).
- **Auto-updater:** checks GitHub when it opens and again every 30 minutes (linked speakers every 15 minutes, or on "Check"). It shows an Update/Cancel popup, verifies the downloaded file's version (retrying 3 times, with a 4-second wait, because GitHub raw caches stale files), keeps a `.bak`, then relaunches.
- **Auto GitHub releases:** CI publishes `vX.Y.Z` when a new version lands on `main`.

### Half done / not yet confirmed in-game
- The **3.7.5 rejoin replay** and **3.8.0 Resync** were built and pass CI. Aaron said "perfect" after 3.8.0, but there's been no detailed long-session test of linked-speaker drift since.
- **Remote** has no "+ add to playlist" yet. That would need a new remote command.
- **README** is missing a **monitor-mirroring screenshot**.

### Known limitations (not bugs)
- **Videos over ~15 minutes don't play** (a server-side limit) and **live streams can't play**; both are hidden by default.
- **Volume changes cause a short blip** (CC speakers latch volume; see section 10).
- **Audio quality** is limited by DFPWM (1-bit).
- **Depends entirely on terreng's server** being up.

### Broken
- Nothing known broken at v3.8.1.

### Fixes worth remembering (so nobody reintroduces them)
| Version | Bug | Cause / fix |
| --- | --- | --- |
| 3.6.2 | Search returned no results | Live-stream check relied on a separator that doesn't arrive in game, so everything was hidden. Length now read without it; if hiding leaves nothing, show all |
| 3.6.3 | Remote flicked between players | Remote now sticks to one player |
| 3.6.4 | Update popup looped | GitHub served the old copy just after a release. Updater checks the download is the promised version and retries |
| 3.7.3 | Far speaker stuck at wrong volume | Volume changes are confirmed via `hello` and resent if lost |
| 3.7.5 | Linked speaker crashed on pause/resume | `until_ms` wiped mid-chunk under lag; now always set before use. Rejoin replays recent audio |
| 3.8.1 | Searches failed on odd characters in titles | Parse the JSON first, then squash text to CC characters |
| (CI) | Test hang with several speakers | Skipping busy speakers looped forever; every speaker now waits for room |

---

## 3. Decisions (with reasons), including rejected ideas

### Product and features
- **Base on terreng's client and server, with credit.** It's MIT, the server is free, and he's credited in the About tab, the README and the LICENSE. His Patreon (patreon.com/exclamatory) is promoted in About and the README. The server's fake "Patreon" first search result is filtered out.
- **JzJad credited** as inspiration for Speaker Link and playlists (his Jukebox, craftfm.cc). **Don't publicly claim Phoenix Music "beats Jukebox"**; let the community make that comparison and keep goodwill with both terreng and JzJad.
- **Live streams: hidden, not supported.** We considered handling them and rejected it as unfair on terreng's server costs. Aaron: "hide the streams, credit JzJad". Live is detected if the artist line starts with `undefined`, `null` or `live`.
- **Long videos (≥15 min) hidden by default**, with a toggle, and the search never hides *everything*.
- **Smoothing: "Strong" dropped, "Light" kept.** Strong sounded worse; an old saved "strong" value maps to Light.
- **Crossfading rejected.** CC can't mix two streams on one speaker cheaply. The real problem was the gap while the next song downloads, which **prefetching** solved (3.6.0).
- **Per-mode PINs** (player/remote/link separate). The first attempt, where the player pushed a relink to its speakers, was rejected by Aaron: setting a PIN in remote or link mode must not change the player's PIN.
- **Remote locks to one host:** two players on one Link made the remote flicker between them (3.6.3).
- **Grey computers become linked speakers automatically**, because they can't draw the player.
- **Wired modem:** speakers on it play as local speakers; Speaker Link and the remote only work with a wireless or ender modem (`isWireless()`).
- **Monitor mirroring draws the player twice** (once per screen size) rather than copying pixels, so each screen gets a proper layout.
- **Search errors show their real reason**, so bugs get diagnosed from screenshots.
- **Search JSON is parsed first, then text is squashed to CC characters** (3.8.1). Squashing first broke whole replies whenever a title had odd characters. There are fallbacks: strip lone surrogate escapes (`\uD8xx`) and control characters, then try the old way.
- **Volume changes to linked speakers are confirmed** via their 5-second `hello` and resent for up to 60 seconds. Speakers ignore repeats so they don't restart for nothing.
- **"Open link" in the app: not possible.** CC can't open a browser, so links are shown as text.
- **An OpenComputers port was considered and dropped.** Phoenix OS stays on CC: Tweaked, and the add-on mod exists so OpenComputers isn't needed.

### Process and tooling
- **Fake-CC smoke tests on GitHub Actions** (the sandbox has no Lua). Random clicks and keys, plus scripted scenarios.
- **The CI release job publishes releases** because the Claude sandbox's GitHub proxy blocks creating releases, tags and branch deletes. The same job deletes `ci-check`.
- **Update verification with retries**, because GitHub raw served stale files and caused an update popup loop (3.6.4 fix).
- **Version notes in `version.txt` must be short lines**, because they're shown on pocket screens.

### Future and architecture (discussed, all *proposed*, not confirmed; see `ROADMAP.md`)
- **Split into an engine plus screens** (full player, linked speaker, remote, Lite, Phoenix OS app). It's needed for the Lua locals limit, smaller installs and Phoenix OS. **Don't split it the lazy way** (just chopping the file up).
- **An installer** (Pastebin or Pinestore, *fetching from GitHub* so the paste never needs editing) that detects the computer type and peripherals, offers only modes that work, sets up start-on-boot, and asks for the Link name and PIN.
- **Phoenix Music Lite** for grey computers: keyboard-driven and greyscale. A separate file, not crammed into the main one.
- **Playlist sync** over the Link name and PIN: opt-in, separate message types (Speaker Link untouched), merging changes rather than "newest wins", and remembering deletions.
- **Music server setting** hidden in Settings → Advanced behind a warning: test before saving, reset, auto-revert offer, and server owners can lock it. Plus a **`servers.txt` backup list** in the repo so every install can be moved to another server by editing one file.
- **Backend redundancy** in layers: server list, then backend adapters, then saved/local music, then a clear "server down" message.
- **Direct YouTube playback from CC is impossible.** YouTube serves AAC/Opus (too heavy to decode in CC Lua), its stream URLs are scrambled (needs yt-dlp-level work), and requests come from the Minecraft server's (usually datacenter) IP, which YouTube blocks. A converting server is always needed.
- **Own backend, if ever needed:** Aaron **won't host from home**. The cheapest route is **terreng's server code forked onto Google Cloud Run** (free tier: 2M requests, but only **1GB/month egress free**, about 1,000 songs) **plus paid RapidAPI services** (YT-API for search, YouTube MP3 for audio; prices unchecked). Add caching, an app key and a length cap. Rough cost is £0 for light use and single-digit pounds a month if popular. A VPS was rejected because datacenter IPs get YouTube-blocked; running a public ripping server under Aaron's name was advised against.
- **Phoenix OS has a Standard edition (local disk only, 1MB) and an enterprise edition (NAS).** Audio storage can't be assumed on Standard, so streaming stays the default.

---

## 4. Architecture and design

### Repo layout (`MADDXSTUDIOS/phoenix-music`, branch `main`)
```
phoenixmusic.lua            the whole program (~4,180 lines, ~145KB, pure ASCII)
version.txt                 line 1 = version; lines 2+ = "What's new" (short lines)
HANDOVER.md                 this file: start here
README.md                   install, features, commands, Speaker Link, keys, limits, credits, roadmap link
ROADMAP.md                  proposed future work + CC hard limits ("proposed, not confirmed")
LICENSE                     MIT: (c) 2024 Terren Gurule, (c) 2026 Phoenix Software
screenshots/*.png           about, in-world, library, now-playing, playlist, pocket, queue,
                            remote, settings, speaker-link, speaker-link-basic, up-next
tests/ccmock.lua            fake CC: Tweaked + scenario scripts + monkey tester
tests/run_all.lua           runs every scenario x seeds 1-5, prints GitHub annotations
tools/localcheck.py         counts Lua locals in scope (fails at >=180)
.github/workflows/check.yml CI: compile, locals check, version match, smoke tests, auto-release
.github/release.md          release description used by the auto-release job
```

### Inside `phoenixmusic.lua` (top to bottom)
1. Licence header and server settings: `api_base_url = "https://ipod-2to6magyna-uc.a.run.app/"`, API `version = "2.1"`, then the `APP` table (`version = "3.8.1"`).
2. **Constants:** `CHUNK = 16*1024` bytes, `BYTES_PER_SEC = 6000`, `VOLUME_MAX = 3`, `VOLUME_STEP = 0.25`, `SEEK_STEP = 10`, `HISTORY_MAX = 50`, `STATE_FILE = ".phoenix_music"`, `LIBRARY_FILE = ".phoenix_library"`, `PLAYLIST_MAX = 50`, `PLAYLIST_TRACKS_MAX = 500`, glyph table `G`.
3. **Speaker Link constants:** `PROTOCOL = "phoenix_music"`, `RECEIVER_TIMEOUT = 15` seconds, `SYNC_LEAD = 600` ms, `LEAD_AHEAD = 3000` ms.
4. **`settings.define`** keys (all prefixed `phoenix_music.`): `group`, `pin`, `background`, `accent`, `smoothing`, `hide_long`, `nospeaker_mode`, `update_channel` (branch the updater reads; default `main`), `mirror`, `mirror_scale`, `rx_volume`. Per-mode credentials also use `remote_group`/`remote_pin` and `link_group`/`link_pin` (via `P.credKeys`), falling back to the player's.
5. **`P` table** (shared helpers usable by every mode): `P.trim`, `P.smooth` (low-pass filter), `P.ok` (group/PIN check), `P.creds`/`P.saveCreds`, updater (`P.REPO = "MADDXSTUDIOS/phoenix-music"`, `P.rawUrl`, `P.fetch`, `P.newer`, `P.checkUpdate`, `P.installUpdate(expected)`), `P.relaunch`.
6. **`F.openModems`**, then **`F.runReceiver(group, pin)`**, the whole linked-speaker mode (own loops: `net`, `player`, `heartbeat`, UI, updater). It uses a `recent` list for rejoin replay and `rejoin()` / `setRxVolume()` / `stopAll()`.
7. **Argument handling and modes:** `link`/`receiver`, `remote`, `player` (forces player), a monitor name with optional scale, auto-mirror when started via `monitor <side>`, grey computer → receiver, no-speaker prompt.
8. **Display:** theme palette on a `window` (`win`) over `parent`. `W, H` are screen size; `X.compact()` gives the narrow layout.
9. **State** and the **`X` table** for newer state and functions (`cache`, `upd`, `mirror`, `next_pick`, `search_tries`, `search_why`, …). **`F`** holds most functions. Functions live in **F / X / P tables** because CC Lua caps locals at 200 in scope.
10. Playback (`play`, `pause`, `F.resume`, seek, `X.resync`), library, drawing (teletext icon buttons, lists, Now Playing, Search, Queue, Settings, About), input (`F.uiLoop`), audio (`F.audioLoop`), HTTP (`F.httpLoop`, `X.retrySearch`, `X.parseResults`), network (`F.netLoop`), ticking/timers, visualiser, redstone/sleep/alarm, settings tab, themes, mirroring (`X.openMirror`, `X.closeMirror`, `X.mirrorMenu`), mode switching and updates, the remote (`X.runRemote`), and run/shutdown.
11. **Main loop:** `parallel.waitForAny(F.uiLoop, F.audioLoop, F.httpLoop, F.netLoop, F.tickLoop, X.vizLoop, X.redstoneLoop, X.updateLoop)`. Remote mode: `X.runRemote` + `X.updateLoop`.

### Audio pipeline
HTTP download of raw DFPWM (binary) → memory handle (`memHandle`) → 16KB chunks → `cc.audio.dfpwm` decoder → optional `P.smooth` → `speaker.playAudio(buf, volume)`, waiting on `speaker_audio_empty`. Every speaker waits for room (a skip-when-busy version caused an infinite loop in CI). Position = `anchor_pos + time since anchor_time`.

### Speaker Link sync
The player sends each chunk to receivers with `at` = the server epoch (ms) when it should play. A fresh start uses `now + SYNC_LEAD`. A player with no local speaker sends up to `LEAD_AHEAD` ahead. Receivers decode lazily, wait until `at`, or trim late audio at **48 samples/ms**, and then rely on the speaker queue. A volume change or resync → `rejoin()`: stop the speakers, put the recent audio back, trim to now, carry on.

### rednet protocol (`"phoenix_music"`; every message has `group` and `pin`)
| type | from → to | fields |
| --- | --- | --- |
| `audio` | player → receivers | `data` (DFPWM string), `at`, `volume`, `smoothing`, `name`, `artist` |
| `stop` | player → receivers | — |
| `ping` | player → all | (receivers answer with hello) |
| `hello` | receiver → player | `label`, `speakers`, `volume` (every 5s) |
| `rxvol` | player → one receiver | `target` (computer ID), `value` (0–150 %) |
| `state` | player → remotes | name, artist, playing, loading, error, pos, total, seekable, volume, muted, looping, shuffle, fav, queue (every 0.5s) |
| `remote_hello` | remote → player | — |
| `cmd` | remote → player | `cmd` = toggle/next/prev/stop/restart/loop/shuffle/fav/mute/volume/seek, `value` |

### Music server API (terreng's, v2.1)
- `GET {base}?v=2.1&search=<urlencoded>` returns a JSON array of `{id, name, artist}`, where `artist` = `"3:33 · Channel"`. A playlist link returns `[{id, name, artist, type:"playlist", playlist_items:[…]}]`. The first item may be a Patreon banner (no `id`), which we filter out.
- `GET {base}?v=2.1&id=<videoId>` returns a raw DFPWM stream (48kHz mono).
- The server is a Firebase/Cloud Run Node function (`functions/index.js` in terreng's repo). It calls RapidAPI **YT-API** (`yt-api.p.rapidapi.com`: search, video info, playlist) and **YouTube MP3** (`youtube-mp36.p.rapidapi.com`: `/dl`), then ffmpeg (via prism-media) to DFPWM. There's no caching and no auth. The 15-minute limit comes from the services or the hosting, not his code.

### Files written on the CC computer
`.phoenix_music` (state), `.phoenix_library` (favourites and playlists), `.settings` (CC settings), and `<program>.bak` after an update.

### Naming conventions
- Settings keys: `phoenix_music.<name>`.
- Functions: `F.*` (core), `X.*` (newer features and state), `P.*` (shared by all modes).
- Commit messages: `X.Y.Z: <what changed>`.
- UI text: plain British English, no jargon.

---

## 5. Where everything lives

| What | Where | Notes |
| --- | --- | --- |
| **Source of truth** | GitHub **`MADDXSTUDIOS/phoenix-music`**, branch **`main`** | The auto-updater reads `main` (`phoenix_music.update_channel` can point elsewhere) |
| Program | `phoenixmusic.lua` on `main` | Install: `wget https://raw.githubusercontent.com/MADDXSTUDIOS/phoenix-music/main/phoenixmusic.lua phoenixmusic.lua` |
| Version | `version.txt` + `APP.version` | Must match (CI checks) |
| Releases | GitHub Releases, `v3.7.1` … `v3.8.1` | Auto-published by CI |
| Scratch branch | `ci-check` | Pushed to test; deleted by the CI release job |
| Roadmap | `ROADMAP.md` | Proposed, not confirmed |
| Original project | `github.com/terreng/computercraft-streaming-music` | Server code: `functions/index.js` |
| terreng contact | GitHub Discussions on his repo | |
| JzJad | Issue **#46** on terreng's repo; craftfm.cc | Jukebox: own Lavalink backend for craftfm.cc (unpublished), 3-hour tracks, enrollment codes, Smart Glasses |
| Add-on mod | **`MADDXSTUDIOS/CCSN`**, design doc **`DESIGN.md` on branch `dev`** | "CC: Phoenix Pro Hardware & Networking" (mod ID `phoenixhw`, formerly ccsn), NeoForge 1.21.1 |
| Phoenix OS notes | `phoenix_architecture_notes.md` (from the Phoenix OS chats) | No code yet |

---

## 6. How we work

### Workflow (Claude)
1. Edit `phoenixmusic.lua` with exact-match patch scripts (Python `str.replace` asserting one match) or the Edit tool. Keep the file **pure ASCII** and use `\ddd` escapes for CC glyphs.
2. Run `python3 tools/localcheck.py phoenixmusic.lua` (it must stay well under 180; currently **135 worst case, 100 top-level**).
3. Bump `APP.version`, the header comment version and `version.txt` (short note lines).
4. `git checkout -B ci-check main`, commit, `git push -f origin ci-check`, then watch CI with `gh run watch` and read results with `gh api repos/MADDXSTUDIOS/phoenix-music/check-runs/<job>/annotations`.
5. If it's green, `git checkout main && git merge --ff-only ci-check && git push origin main`. CI runs again and publishes the release.
6. Add a scenario to `tests/ccmock.lua` for any new behaviour, especially anything that previously broke.

### Sandbox limits seen
- No Lua installed locally, so the tests only run on CI.
- The GitHub proxy blocks creating releases or tags and deleting branches; the workflow handles those.
- `curl` to `raw.githubusercontent.com` gets a 403 in the shell, but WebFetch works.
- terreng's server is unreachable from the sandbox, so Aaron runs live server tests in-game with a one-line `lua` snippet.

### Tests (`tests/ccmock.lua` + `tests/run_all.lua`)
- **Fake CC:** event/timer simulation, a watchdog, `parallel`, `term`/`window`, `fs`, `settings`, `shell.run` (records relaunches), `textutils` with a **strict** JSON decoder (rejects raw control characters and lone surrogate escapes, like CC or stricter), a DFPWM mock, speakers with buffer timing, monitor `monitor_0`, modem (`isWireless = not setup.wired`), rednet, `pocket`, and HTTP with fake search JSON. The fake JSON includes emoji, Bengali, curly quotes, a Patreon banner, a 1h video, a live stream, a playlist and a half-emoji title. On even seeds every other search fails; on seed%3==0 there's a fake update (9.9.9), whose first download is stale.
- **Scenarios (16):** `queue, mirror, via_monitor, computer, pocket, medium, monitor, nospeaker, remote, remote_wide, link, link_basic, wired, pocket_nospeaker, pocket_noisy_remote, basic_auto`.
  - Each runs with **seeds 1–5**, with a **45-second** real timeout and 240 seconds simulated.
  - A random "monkey" clicks, taps and types (never `q`).
  - Scripted helpers: `playerScript` + `hostChatter` (including a second idle player), `linkScript` (audio every 2.7s, stops, rxvol, pings, **8-second pauses**), `remoteScript` (a second idle player, ID 4), `queueScript` (asserts 3 songs, ≥2 early downloads, 0 gaps).
- **CI (`.github/workflows/check.yml`):** ubuntu, `lua5.2`, `luac5.2 -p`, `tools/localcheck.py`, version.txt = app version, `lua5.2 tests/run_all.lua`. Then a `release` job (main only): create `v<version>` if it's missing, using `.github/release.md`, and delete `ci-check`.

### Testing in-game
Aaron tests in-game and reports back with screenshots. Testing covers on advanced and grey computers, advanced pockets (with a speaker and with an ender modem), monitors, linked speakers at distance, and wired networks. Fixes go out as releases, and he updates in-game via the popup or Settings → Check.

---

## 7. Open questions

1. **Self-hosting:** officially supported with a guide, or just quietly allowed?
2. **Own backend:** build it now as a backup, or only if terreng's dies? (It'd be Cloud Run + RapidAPI; check RapidAPI prices first.)
3. **Audio storage on Phoenix OS Standard:** possible at all with 1MB? Could Phoenix Pro add a computer storage upgrade?
4. **Minimum feature set for the Phoenix OS Standard app** (CPU and storage budget).
5. **Playlist sync conflicts:** confirm "merge" over "newest wins".
6. **Lite scope:** which features make the cut on grey computers.
7. **Advanced speaker API:** agree it with the CCSN design (section 10).
8. **JzJad's backend:** ask for his blessing to support it once he publishes.

---

## 8. Next steps (in order)

1. **Outside the code:** announce the release (terreng, JzJad #46, Pinestore, Discord, Reddit) and add a monitor-mirroring screenshot to the README.
2. **Music server setting + `servers.txt` backup list + "server down" message** (small update to the current file).
3. **Playlist sync** over Link/PIN (opt-in).
4. **+ to playlist on the remote** (new `cmd`).
5. **Engine + screens split**, with a multi-file updater and file list. **Required before any other big feature** (locals limit).
6. **Installer** (Pastebin/Pinestore → GitHub), with device and peripheral detection, start-on-boot, and Link/PIN setup.
7. **Phoenix Music Lite** for grey computers.
8. **Advanced speaker support**, once the CCSN advanced speaker exists (section 10).
9. Other Phoenix Pro hardware (higher-res computer, laptop, rooms, NAS library).
10. **Phoenix OS hosted mode and app** (no palette changes, no `term.native()`, no `shell.run` relaunch, per-user storage, App Store updates, OS networking, background service, CPU-light), once Phoenix OS exists.

---

## 9. CC hard limits that shape everything (defaults)

| Limit | Value | Impact |
| --- | --- | --- |
| Computer disk | **1,000,000 bytes** | The program is ~145KB. A 3-minute song is ~1MB, so local song storage doesn't fit |
| Floppy | **125,000 bytes** | About 20 seconds of audio |
| Computer threads | **1** for the whole server | Every computer shares it; keep decoding, the visualiser and redraws light |
| Lua locals | **200** in scope | We're at 135, hence the F/X/P tables and the planned split |
| Speaker `playAudio` | **≤131,072 samples (~2.7s)** per call, one call buffered | Feed in chunks and wait for `speaker_audio_empty` |
| Wireless modem range | **64 blocks** (384 at high altitude) | Ender modems for distance |
| Drag-and-drop upload | **512KB** | Users can't drop in song files |
| Screens | Computer **51x19**, pocket **26x20**, monitor up to **8x6 blocks** | Every layout must adapt |
| Max open files | **128** | Not an issue yet |

---

## 10. Advanced speaker: what Phoenix Music needs

> **The advanced speaker's API is defined only in the mod's [DESIGN.md](https://github.com/MADDXSTUDIOS/CCSN/blob/dev/DESIGN.md) (CCSN repo, `dev` branch).** Don't keep a copy of the API here. This section lists Phoenix Music's *requirements*: the CC speaker problems it has hit, which the API should solve. Function names below are suggestions only.

**The plan (from Aaron):** CC: Phoenix Pro Hardware & Networking (`MADDXSTUDIOS/CCSN`, `DESIGN.md` on `dev`) will add an **advanced speaker** that is a **full superset of CC's speaker**:
- Still type `"speaker"`, and every existing function works the same.
- **Better audio quality**, because CC squashes audio to 1-bit DFPWM.
- **Live volume**, **pause and skip**, and **synced multi-speaker groups**.

**Phoenix Music must keep working on normal CC speakers and use the extras only when it detects an advanced speaker.**

### Speaker limitations Phoenix Music has hit (these should shape the API)
1. **Volume is latched per stream.** `playAudio`'s volume only takes effect after `stop()`. Every volume change means stop + restart, which causes an audible blip, a 700ms debounce (`X.vol_dirty_at`), re-sync of linked speakers, and the whole rejoin/replay machinery. → **Need `setVolume(v)` that applies live.**
2. **No pause/resume.** Pause = `stop()` and lose the buffer; resume = re-download or re-chunk from a byte offset that we track ourselves. → **Need `pause()` / `resume()` that keep the buffer.**
3. **`stop()` throws away queued audio** with no way to get it back. We had to keep our own copy (`recent`) to rejoin without silence. → Pause/resume and live volume make this unnecessary.
4. **No position or buffer query.** We can't ask what's playing or how much is queued, so we estimate with clocks (`anchor_pos`/`anchor_time`, `until_ms`). Under server lag the estimate drifts, and that caused a crash (`until_ms` nil). → **Need `getPosition()` (samples played) and `getBuffered()` (samples queued).**
5. **Only one `playAudio` call buffered (~2.7s).** We have to poll `speaker_audio_empty` and feed every speaker separately; a busy speaker once caused an infinite loop. → **Need a deeper queue, or "queue N chunks", and a free-space query.**
6. **No scheduled playback.** There's no "play this at time T", so Speaker Link fakes it with server-epoch timestamps (`SYNC_LEAD` 600ms, `LEAD_AHEAD` 3000ms) and trims late audio at 48 samples/ms. Speakers drain per game tick while our clock is real time, so they drift when TPS drops. → **Need `playAudioAt(samples, epochMs, volume)` or tick-based scheduling.**
7. **No speaker groups.** Every speaker is fed individually; across computers, full audio is shipped over rednet. → **Need groups (by name/ID) where one `playAudio` plays on every member in sync, ideally including speakers on other computers or the CCSN network.**
8. **No skip/clear distinct from stop.** → **Need `clear()` (drop the queue but keep the stream state) or skip-to-next-chunk.**
9. **Quality:** input is 8-bit PCM, but CC re-encodes it to **1-bit DFPWM**, and our smoothing filter is a band-aid. → **Need a higher-quality path (e.g. 8- or 16-bit PCM kept as-is), plus a way to ask which formats are supported.**
10. **Decoding costs Lua CPU** (all computers share 1 thread by default, and Phoenix OS shares one computer). → **Nice to have: `playDFPWM(bytes)` decoded in Java, or `playStream(url)` handled natively.**
11. **Range is tied to volume** (max 3.0), so far listeners hear it quietly. → Optional: **separate range and loudness**.
12. **Events:** we rely on `speaker_audio_empty` (with the speaker name). → **Keep it, and add events for position/position-reached and group state.**

### How Phoenix Music should detect it
- It must still match `peripheral.find("speaker")`.
- Detect extras with a second peripheral type (e.g. `peripheral.hasType(name, "advanced_speaker")`), and/or a `getCapabilities()` that returns e.g. `{ liveVolume=true, pause=true, groups=true, formats={"dfpwm","pcm8","pcm16"} }`.
- **Never assume it.** With mixed normal and advanced speakers, normal ones keep the current behaviour.

---

## 11. Glossary

| Term | Meaning |
| --- | --- |
| **Phoenix Music** | This music player (`phoenixmusic.lua`) |
| **Phoenix Software** | Aaron's publisher name; GitHub org **MADDXSTUDIOS** (MADD X Studios) |
| **Player** | The full app that searches and plays music (advanced computer or pocket) |
| **Speaker Link** | Playing through speakers on other computers over rednet, in sync |
| **Link (name)** | Group name for Speaker Link, the remote and (planned) playlist sync. Default `default` |
| **PIN** | Optional code required to join or control a Link |
| **Linked speaker / receiver** | A computer running `phoenixmusic link` that plays what the player sends |
| **Remote** | A computer running `phoenixmusic remote` that controls a player (`host`) |
| **Host** | The player a remote is locked onto |
| **Resync** | Restart every speaker at the same spot to fix drift |
| **Rejoin** | A linked speaker restarting its speakers (volume change) and replaying recent audio |
| **Mirroring** | Showing the player on a monitor as well as the computer |
| **Compact layout** | Narrow-screen layout (`W < 43`; tabs Now/Find/Queue/Set) |
| **Long & live** | The setting that hides ≥15-minute videos and live streams |
| **F / X / P tables** | Where functions live to stay under the Lua locals limit (core / newer features / shared by all modes) |
| **`ci-check`** | Scratch branch pushed for CI before merging to `main` |
| **ccmock** | The fake CC: Tweaked used in tests |
| **Engine + screens** | Planned split: one core, several front-ends |
| **Lite** | Planned keyboard and greyscale version for standard (grey) computers |
| **Hosted mode** | Planned behaviour when running inside Phoenix OS |
| **`servers.txt`** | Planned backup server list in the repo |
| **Phoenix OS** | Aaron's Windows-style OS for CC (in development). Editions: **Standard** (standalone, local disk), **Professional** (domain-joined), **Server / Phoenix Core**. Also called Phoenix Station (client) and Phoenix Suite (apps) |
| **CC: Phoenix Pro Hardware & Networking** | Aaron's CC add-on mod (repo `MADDXSTUDIOS/CCSN`, mod ID `phoenixhw`, formerly "CC: Servers & Networking"/ccsn): racks, blades, NAS, cables, switches, planned advanced speaker. In development |
| **Advanced speaker** | Planned superset of CC's speaker in that mod (section 10) |
| **terreng** | Terren Gurule, author of the original program and the music server |
| **JzJad** | Author of Jukebox / craftfm.cc, credited as inspiration |
| **DFPWM** | CC's 1-bit audio format (48kHz, 6,000 bytes/second; ~1MB per 3 minutes) |
