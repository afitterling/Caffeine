# BreakTimer

A tiny macOS menu-bar app that tracks active time (typing, clicking, watching) and reminds you to take a break. Also flags app-switching thrash so you notice when you're losing focus.

## Build

Requires macOS 13+ and Swift 5.9+.

```sh
./build.sh           # produces ./BreakTimer.app
./build.sh install   # also copies it to ~/Applications
```

Then:

```sh
open BreakTimer.app
```
