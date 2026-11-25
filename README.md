# Sonos Sound for Omarchy

A bar widget for the [Omarchy](https://omarchy.org/) shell that controls a Sonos home-theater setup over the local network:

| Slider | Range | Sonos setting |
|---|---|---|
| Volume limit | 1 % to 100 % | None, kept on this PC: the highest volume this widget allows |
| Volume | 0 to 100 | Master volume |
| Bass | −10 to +10 | EQ bass |
| Sub | −15 to +15 | Sub level (`SubGain`) |
| Surround TV | −15 to +15 | Surround level for TV (`SurroundLevel`) |
| Surround music | −15 to +15 | Surround level for music (`MusicSurroundLevel`) |

Sliders for a sub or surrounds you don't have are hidden.

## Install

```bash
git clone https://github.com/runeballe/omarchy-sonos-sound ~/.config/omarchy/plugins/rune.sonos-sound
omarchy bar put rune.sonos-sound
omarchy bar set rune.sonos-sound host 192.168.1.45   # IP of your soundbar (Playbar/Beam/Arc)
```

To find the soundbar IP, open the Sonos app and go to Settings → System → About My System.

Set up a DHCP reservation in your router so the IP stays the same.

## Use

- Left-click the icon to open the popup.
- Scroll on the icon to change the volume, one step (1 of 100) per scroll event.
- The volume slider never jumps: the speaker moves one step at a time to where you drag or click.
- Right-click an EQ slider to reset it to 0, or the volume limit to reset it to 100 %.
- The volume limit (default 100 %) caps scrolling and the volume slider. Lowering it below the current volume brings the volume down to the limit, and so does turning it up past the limit from the Sonos app while the popup is open. It is stored in `~/.local/state/omarchy/sonos-sound-volume-limit`.

The popup reads the levels again every 3 seconds, so it picks up changes made in the Sonos app.

## Command line

The `sonos-sound` helper needs Python 3 and its standard library, nothing else:

```bash
./sonos-sound 192.168.1.45 get            # {"ok": true, "volume": 20, "bass": -5, ...}
./sonos-sound 192.168.1.45 set sub 3
```

It talks to the speaker's UPnP `RenderingControl` service on port 1400. It sends no data to the internet.

## License

MIT
