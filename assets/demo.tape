# VHS demo for Prune. Regenerate with:
#   vhs assets/demo.tape
# Requires: vhs (charm), ttyd, ffmpeg.
#
# The demo runs against a synthetic fixture DB so it never touches real
# user data and the output is deterministic. Build the fixture first:
#   sqlite3 /tmp/prune-demo-fixture.db < assets/demo-fixture.sql

Output assets/demo.gif

Set FontSize 14
Set Width 1100
Set Height 650
Set Theme "Catppuccin Mocha"
Set TypingSpeed 70ms
Set Framerate 24
Set Padding 18

# Use the in-tree binary (no install required) and the demo fixture DB.
Env PATH "/home/noname/Proyectos/Prune/bin:/usr/bin:/bin"
Env PRUNE_GOOSE_DB "/tmp/prune-demo-fixture.db"
Env PS1 "$ "
Env NO_COLOR ""

Hide
Type "clear"
Enter
Sleep 200ms
Show

# Open the picker
Type "prune goose"
Sleep 600ms
Enter
Sleep 1800ms

# Move down through the list — preview pane updates each step
Down
Sleep 700ms
Down
Sleep 700ms
Down
Sleep 900ms

# Multi-select a couple of sessions with Tab
Tab
Sleep 500ms
Down
Sleep 400ms
Tab
Sleep 900ms

# Trigger the confirm dialog
Enter
Sleep 1500ms

# Pick "No" so the demo is non-destructive (and reproducible)
Sleep 600ms
Enter
Sleep 1200ms
