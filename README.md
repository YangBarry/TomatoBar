# TomatoBar (Custom Edition)

Custom build of [ivoronin/TomatoBar](https://github.com/ivoronin/TomatoBar) located at `/Users/zyang99/Documents/Build/TomatoBar`.

## Custom Features

1. **30-Minute Default + Overtime Count-Up (Manual Break Start)**
   - Defaults to a 30-minute work countdown (`workIntervalLength = 30`).
   - When the countdown reaches `00:00`, it chimes once and automatically switches to **overtime count-up** (`+00:01`, `+00:02`, ...) in the macOS menu bar while keeping your background audio playing.
   - Only transitions to the break timer when you actively click **开始休息 (Start Break)** (or trigger the shortcut / notification action). A separate **停止 (Stop)** button lets you end and return to idle at any time.

2. **Built-in Focus Audio (`声音` Tab)**
   - **1. Brown Noise (Default)**: Warm, seamless stereo Brown Noise synthesized in-memory (or optionally load your own local `.mp3`/`.wav`/`.m4a` file via `选择文件...`).
   - **2. Lofi Hip Hop Radio**: Live online stream (`Lofi Hip Hop Radio` via Zeno.FM with automatic fallback to `FluxFM Chillhop`).
   - Automatically starts when a work session begins and stops when entering break or idle.

3. **Daily Cumulative Stats & AI-Friendly Data Persistence (`统计` Tab)**
   - Displays **今日专注 (Today's cumulative focus time & session count)** directly in the popover header and a 7-day breakdown in the **统计 (Stats)** tab.
   - Saves all completed work and rest sessions automatically to `~/.tomatobar/`:
     - `~/.tomatobar/sessions.jsonl` (JSON Lines, one object per session)
     - `~/.tomatobar/sessions.csv` (CSV table with headers)
     - `~/.tomatobar/daily_summary.json` (Daily aggregated metrics)
     - `~/.tomatobar/events.jsonl` (Raw state machine transition events)

## Building from Command Line

No full Xcode.app installation is required (builds directly with macOS Command Line Tools / SwiftPM):

```bash
cd /Users/zyang99/Documents/Build/TomatoBar
./build-app.sh
open TomatoBar.app
```
