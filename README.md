# Omadoro

Omadoro is a [Pomodoro](https://en.wikipedia.org/wiki/Pomodoro_Technique) timer
for the [Omarchy](https://omarchy.org/) bar.

![Omadoro screenshot](preview.png)

## Install

```bash
omarchy plugin add https://github.com/brianblakely/omadoro.git --enable --yes
```

## Use

Click the bar icon to open the timer panel.

| Button    | Action                                    |
| --------- | ----------------------------------------- |
| `` / `` | Start a new cycle or stop the current one |
| `` / `` | Pause or resume                           |
| `󰐕`       | Add five minutes                          |
| ``       | Skip to the next phase                    |
| `󰒓`       | Alert settings (sound, flashes, invert) |

When the timer is stopped, press Play to begin a fresh cycle. Omadoro switches
between work and break phases automatically. When the next phase begins it
sends a notification, plays a sound, and can flash the bar, a 5px monitor
border, and an eased invert of either the wallpaper or the whole screen
(including windows). Open the gear in the corner of the timer panel to change
the sound and which flashes run.

The default cycle is:

- 25 minutes of work
- 5-minute short breaks
- A 15-minute long break after four work phases

## Keyboard controls

With the panel open:

- Use the arrow keys or `h`, `j`, `k`, and `l` to select a button.
- Press Enter or Space to activate it.
- Press Escape to close the panel.
- Press Tab or Shift+Tab to move between bar panels.

You can also control the panel from a terminal or your own keybinding:

```bash
omarchy-shell shell toggle b.omadoro
```

## Customize

Change the phase lengths and long-break frequency through Omarchy:

```bash
omarchy bar plugin set b.omadoro workMinutes 25 --json
omarchy bar plugin set b.omadoro shortBreakMinutes 5 --json
omarchy bar plugin set b.omadoro longBreakMinutes 15 --json
omarchy bar plugin set b.omadoro workPhasesPerLongBreak 4 --json
omarchy bar plugin set b.omadoro soundEnabled true --json
omarchy bar plugin set b.omadoro soundName complete --json
omarchy bar plugin set b.omadoro flashScreenMode background --json
omarchy bar plugin set b.omadoro flashBarEnabled true --json
omarchy bar plugin set b.omadoro flashBorderEnabled true --json
omarchy bar plugin set b.omadoro flashCount 3 --json
omarchy bar plugin set b.omadoro flashSpeed normal --json
```

Phase lengths apply from the next phase onward. Sound and flash take effect
immediately.

## Update

```bash
omarchy plugin update b.omadoro
```

## Uninstall

```bash
omarchy plugin remove b.omadoro
```
