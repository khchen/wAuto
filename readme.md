# wAuto

wAuto is the Windows automation module for nim based on
[winim](https://github.com/khchen/winim) and
[wNim](https://github.com/khchen/wNim). It contains support to simulate
keystrokes and mouse movements, manipulate windows, processes, and registry.
Some functions are inspired by [AutoIt Script](https://www.autoitscript.com)

## Install
With git on windows:

    nimble install wAuto

Without git:

    1. Download and unzip this moudle (by click "Clone or download" button).
    2. Start a console, change current dir to the folder which include "wAuto.nimble" file.
       (for example: C:\wAuto-master\wAuto-master>)
    3. Run "nimble install"

## Example

```nim
import wAuto

# Open "Run" box
send("#r")

# Start notepad.exe
send("notepad{enter}")

# Wait the window
let notepad = waitAny(window.className == "Notepad" and window.isActive)

# Send some words
send("Hello, world")

# Drag the mouse cursor to select
clickDrag(pos1=notepad.clientPosition(0, 0), pos2=notepad.clientPosition(200, 0))

# Copy it
send("^c")

# Paste 10 times slowly
opt("SendKeyDelay", 250)
send("^{v 10}")

# Terminates the process
kill(notepad.process)
```

## Docs
* https://khchen.github.io/wAuto

## License
Read license.txt for more details.

Copyright (c) Chen Kai-Hung, Ward. All rights reserved.

## Donate
If this project help you reduce time to develop, you can give me a cup of coffee :)

[![paypal](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)](https://paypal.me/khchen0915?country.x=TW&locale.x=zh_TW)
