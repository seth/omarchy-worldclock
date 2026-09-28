# seth.worldclock

A world clock bar widget for the [Omarchy](https://omarchy.org/) shell, in the
spirit of Clocker + Timeshifter on macOS.

- **Bar:** a short label for the zones in `barZones` (default `UTC 16:50`).
  Click to open the panel.
- **Panel:** every configured zone in order, all showing the same instant.
  A slider picks a time across the selected zone's day, so you can map
  "9am in Paris" onto every other zone.
  - The selected zone is outlined; its time and name are the header.
  - The system zone (from `/etc/localtime`) is bold.
  - Zones on a different date get a `+1d` / `−1d` marker.
  - Hours outside 08:00–18:00 dim, overnight hours dim further.

## Keys

| Key | Action |
|-----|--------|
| ↑ / ↓ | Select zone |
| ← / → | Move time 15 minutes (crosses midnight) |
| Enter / T | Back to now |
| Esc | Back to now; closes the panel when already at now |

Clicking a row selects it; clicking the header time goes back to now.

## Install

```bash
omarchy plugin add <git-url> --enable
```

or clone into `~/.config/omarchy/plugins/seth.worldclock/`, then
`omarchy-shell shell rescanPlugins` and `omarchy plugin enable seth.worldclock`.

## Configuration

Settings live on the widget's entry in `~/.config/omarchy/shell.json` and
apply on save:

```json
{
  "id": "seth.worldclock",
  "barZones": ["UTC"],
  "hour12": false,
  "zones": [
    { "label": "San Francisco", "tz": "America/Los_Angeles" },
    { "label": "Denver",        "tz": "America/Denver" },
    { "label": "Minneapolis",   "tz": "America/Chicago" },
    { "label": "UTC",           "tz": "UTC" },
    { "label": "UK",            "tz": "Europe/London" },
    { "label": "Paris",         "tz": "Europe/Paris" }
  ]
}
```

- `zones` — `{ label, tz }` in display order; `tz` is an IANA zone name.
  Omitted, the list above is used.
- `barZones` — labels from `zones` to show in the bar.
- `hour12` — `true` for 12-hour times.

## How it works

The shell's QML JavaScript engine has no `Intl`, so it can't convert between
zones itself. `BarWidget.qml` runs `date` once to sample every zone's offset
on each hour from local midnight yesterday to midnight tomorrow; the panel
does all slider math against that table. It re-samples hourly and at
midnight, so DST changes stay correct.

## Development

Saving files here triggers the shell's plugin reload, but a live instance
may keep running the old code. `omarchy restart shell` reliably picks up
changes.
