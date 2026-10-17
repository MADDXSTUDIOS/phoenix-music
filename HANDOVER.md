# Handover: start here

For a fresh chat picking Phoenix Music up. Read this first, then
[ROADMAP.md](ROADMAP.md) (proposed next steps and CC's hard limits) and
[README.md](README.md) (what players see). These docs are the source of truth,
not chat history.

Written 17 Oct 2026, from the summary of the first long build chat (Oct 2026).

---

## 1. What this is

- **A music player for CC: Tweaked** (Minecraft 1.21.1, NeoForge). Author:
  Aaron (xPhoenixLRDx), published as **Phoenix Software** (GitHub
  MADDXSTUDIOS). Repo: `github.com/MADDXSTUDIOS/phoenix-music`, branch `main`.
- **Started as a reskin of terreng's
  [computercraft-streaming-music](https://github.com/terreng/computercraft-streaming-music)**
  (MIT) and still uses **terreng's free music server** (API version `2.1`,
  `api_base_url` near the top of `phoenixmusic.lua`). The server does the
  YouTube search and the conversion to DFPWM; we only stream what it gives us.
- **Part of the Phoenix family** with the hardware mod
  **CC: Phoenix Pro Hardware & Networking** (repo MADDXSTUDIOS/CCSN) and
  **Phoenix OS**. Both are still in development. Phoenix Music is just a
  program that uses the mod's Lua APIs when present; it never requires them.

## 2. Current state

- **Release: v3.8.1.** One file, `phoenixmusic.lua` (~145KB).
- Nothing is known to be broken.

**Built so far**
- **UI:** tabs (Playing / Search / Queue / Settings / About), teletext icons,
  themes (Dark, Midnight, Light + 8 accents), visualiser, audio smoothing.
- **Library:** favourites, playlists, queue, recently played.
- **Speaker Link:** synced wireless speakers on other computers, joined by
  Link name + PIN, per-speaker volume, Resync. Grey (standard) computers
  auto-run as linked speakers.
- **Wired speakers** play alongside linked ones.
- **Pocket remote**, and **mode switching** in Settings (player / remote /
  linked speaker), with **separate PINs per mode**.
- **Monitors:** run on a monitor, or mirror the computer to one.
- **Sleep timer, alarm, redstone trigger.**
- **Prefetching** the next song (no gap between songs) and an **in-memory
  song cache** (instant replays).
- **GitHub auto-updater.**
- **Search:** live streams and videos over 15 minutes hidden by default (the
  server can't play them), retries while the server wakes up, readable error
  reasons.
- **CI:** GitHub Actions compiles the file, checks the Lua locals count, checks
  `version.txt` matches, runs a fake-CC smoke test (16 scenarios x 5 seeds,
  `tests/`), and publishes a GitHub release when a new version lands on `main`.

**Fixes worth remembering** (so nobody reintroduces them)

| Version | Bug | Cause / fix |
|---|---|---|
| 3.6.2 | Search returned no results | Live-stream check relied on a "." separator that doesn't arrive in game, so everything was hidden. Length now read without it; if hiding leaves nothing, show all |
| 3.6.3 | Remote flicked between players | Remote now sticks to one player |
| 3.6.4 | Update popup looped | GitHub served the old copy just after a release. Updater now checks the download is the promised version and retries |
| 3.7.3 | Far speaker stuck at wrong volume | Volume changes are confirmed and resent if lost |
| 3.7.5 | Linked speaker crashed on pause/resume | Crash after a rejoin; speakers now rejoin instantly |
| 3.8.1 | Searches failed on odd characters in titles | Parse the JSON before squashing text |

## 3. Decisions and research, with the reasons

- **Direct YouTube playback from CC is impossible.** CC can't decode YouTube
  audio; something off-world has to convert it to DFPWM. So we always depend
  on a backend.
- **If we ever run our own backend** it would be terreng's server (MIT) on
  **Google Cloud Run** using a paid YouTube API via **RapidAPI**. **Aaron
  won't host it from home.** Not needed while terreng's server is up (see
  ROADMAP open questions).
- **JzJad's Jukebox / CraftFM** is the closest rival and inspired Speaker Link
  and playlists (credited in README and About). We compared against it.
  **Never publicly claim Phoenix Music beats it.**
- **Plain CC first.** Everything must work on a stock CC computer with
  CraftOS. Phoenix Pro hardware and Phoenix OS are optional extras.
- **CC hard limits** (1MB disk, one shared thread, 200 Lua locals, speaker
  buffer, etc.) are researched and listed in ROADMAP.md. Phoenix OS Standard
  only has the computer's own 1MB disk, so storing audio can't be assumed.

## 4. Shared APIs live in the mod, not here

The **advanced speaker** (and any other Phoenix Pro hardware Phoenix Music
uses) is defined **only** in the mod's
[DESIGN.md](https://github.com/MADDXSTUDIOS/CCSN/blob/dev/DESIGN.md) on the
CCSN `dev` branch. Don't copy API details into this repo; link to it.

## 5. How we work

- **Aaron tests in-game** and reports back. Claude writes the code.
- Work lands on **`main`**. Each release bumps the version in
  `phoenixmusic.lua` **and** the first line of `version.txt` (the lines after
  it are the in-app "What's new"), plus `.github/release.md` for the GitHub
  release text. CI must be green.
- **Lua locals ceiling:** the worst function is at ~135 of CC's 200, checked
  by `tools/localcheck.py`. Big new features wait for the engine + screens
  split (ROADMAP).

## 6. Next steps

All proposed, none confirmed. Details in [ROADMAP.md](ROADMAP.md):
1. Music server setting + backup server list
2. Playlist sync
3. Engine + screens split
4. Installer
5. Phoenix Music Lite for grey computers
6. Phoenix Pro hardware integration (advanced speaker etc.)
7. Phoenix OS app (must fit on Standard's 1MB disk)
