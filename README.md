# Phoenix Music

A feature-packed music player for [CC: Tweaked](https://tweaked.cc/). Search YouTube, build playlists, sync wireless speakers around your base with **Speaker Link**, and control it all from a pocket remote.

Built by **Phoenix Software** on top of terreng's [computercraft-streaming-music](https://github.com/terreng/computercraft-streaming-music).

## Install

On an **Advanced Computer** (or Advanced Pocket Computer) with a speaker attached:

```
wget https://raw.githubusercontent.com/MADDXSTUDIOS/phoenix-music/main/phoenixmusic.lua phoenixmusic.lua
```

Then run:

```
phoenixmusic
```

Needs CC: Tweaked 1.100.0 or newer.

## Features

- **Search and play** YouTube videos and playlists, or paste a link
- **Proper controls**: play/pause, stop, previous, next, restart, seek by tapping the progress bar
- **Loop** the queue or a single song, and **shuffle mode**
- **Queue** you can reorder, remove from, shuffle and save
- **Favourites and playlists**, plus a recently played list
- **Picks up where you left off**: song, position, queue and settings survive a restart
- **Speaker Link**: play through speakers on other computers, in sync, with an optional PIN and per-speaker volume
- **Pocket remote**: control the player from anywhere with an ender modem
- **Visualiser** that moves with the music
- **Sleep timer, alarm and redstone trigger**
- **Themes**: Dark, Midnight or Light, with 8 accent colours
- **Audio smoothing** to take the edge off CC's crunchy sound
- Works on computers, pocket computers and monitors, with mouse, touch and keyboard

## Commands

| Command | What it does |
| --- | --- |
| `phoenixmusic` | Run the player |
| `phoenixmusic <monitor> [scale]` | Run on a monitor, e.g. `phoenixmusic monitor_0 0.5` |
| `phoenixmusic link [name]` | Turn this computer into a wireless speaker on a Speaker Link |
| `phoenixmusic remote` | Turn this computer into a remote for a player |

## Speaker Link

1. Give the player an **ender modem** (or wireless/wired modem).
2. On each other computer, attach a speaker and a modem, then run `phoenixmusic link`.
3. They'll show up under **Settings → Speaker Link** on the player within a few seconds.

Use a different Link name to run separate zones, and set a PIN so nobody else can join or control your speakers. The player doesn't need its own speaker if it has linked ones.

## Keyboard shortcuts

| Key | Action |
| --- | --- |
| Space | Play / pause |
| ← / → | Seek 10 seconds |
| n / p | Next / previous |
| s | Stop |
| r | Restart |
| + / - | Volume |
| m | Mute |
| l | Loop mode |
| h | Shuffle |
| f | Favourite the current song |
| v | Visualiser on/off |
| / | Search |
| Tab | Switch tab |
| q | Quit |

## Known limits

- **Videos over about 15 minutes won't play.** This is a limit of the music server, not the player. Long results are greyed out in search.
- **Audio quality** is limited by CC's speakers and audio format. Smoothing helps a little but it'll always sound like CC.
- **Phoenix Music uses terreng's free music server.** If it ever goes down, the player can't fetch music. Running it costs him money, so if you enjoy this, consider supporting him at [patreon.com/exclamatory](https://patreon.com/exclamatory).

## Credits

- **terreng (Terren Gurule)**: original player, music server and audio engine
- **Phoenix Software**: new interface, controls and everything else

Released under the [MIT License](LICENSE).
