# Charging icons

`charging-01.png` .. `charging-05.png` from spruceOS's SPRUCE theme (spruceUI/spruceOS
`Themes/SPRUCE/<skin>/`, Development 00a9439f4e02fa20cb5eef2be82ddf79768fb56f; Ryan Sartor's art),
the charging animation Miyoo's MainUI draws: the tree in #545454, lit white a part at a time (01 none,
02 the trunk, 03 the bottom tier, 04 the middle tier, 05 all), on a full-height strip centred on the
screen. `scripts/charge-mode/make-frames.py` builds every unit's charge screen from them.

- `skin`: 640x480 (strip 100x480); `skin_720x540`: 720x540; `skin_960x720`: 960x720 and the RGB30's
  720x720 (the theme's own `skin_720x720` tree is drawn narrower, 54x127 against 72x127).
