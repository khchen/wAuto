#====================================================================
#
#               wAuto - Windows Automation Module
#                   (c) Copyright 2020 Ward
#
#====================================================================

## This module contains support to simulate keystrokes.

{.deadCodeElim: on.}

import strutils, tables
import winim/lean
import wNim/[wApp, wMacros, wWindow, wHotkeyCtrl]
import npeg, npeg/lib/utf8
import common, window, private/utils

export common, wApp # for wKeyCodes

type
  KeyModifier = enum
    kmLShift, kmRShift, kmLControl, kmRControl, kmLAlt, kmRAlt, kmLWin, kmRWin

  KeyDownUp = enum
    kDown, kUp

  KeyToggle = enum
    ktNil, ktOn, ktOff, ktToggle, ktDown, ktUp

  KeyCommand = object
    text: string
    count: int
    toggle: KeyToggle
    modifiers: set[KeyModifier]

  KeyItem = object
    vk: int
    shift: bool
    extend: bool

  ModifierItem = object
    modifier: KeyModifier
    downup: KeyDownUp

  WinData = tuple[hwnd: HWND, id: int]

  HotkeyData = object
    hHook: HHOOK
    table: Table[Hotkey, WinData]
    lastKeyCode: int
    lastModifiers: int

proc sendKeyboardEvent(vk: int, keyDownUp: KeyDownUp, isExtended: bool = false) =
  var input = INPUT(`type`: INPUT_KEYBOARD)
  input.ki.wVk = WORD vk
  input.ki.wScan = WORD MapVirtualKey(UINT vk, MAPVK_VK_TO_VSC)
  if keyDownUp == kUp: input.ki.dwFlags = input.ki.dwFlags or KEYEVENTF_KEYUP
  if isExtended: input.ki.dwFlags = input.ki.dwFlags or KEYEVENTF_EXTENDEDKEY
  SendInput(1, &input, cint sizeof(INPUT))

proc sendUnicodeKeyboardEvent(unicode: WCHAR, keyDownUp: KeyDownUp, isExtended: bool = false) =
  var input = INPUT(`type`: INPUT_KEYBOARD)
  input.ki.wScan = unicode
  input.ki.dwFlags = KEYEVENTF_UNICODE
  if keyDownUp == kUp: input.ki.dwFlags = input.ki.dwFlags or KEYEVENTF_KEYUP
  if isExtended: input.ki.dwFlags = input.ki.dwFlags or KEYEVENTF_EXTENDEDKEY
  SendInput(1, addr input, cint sizeof(INPUT))

proc sendModifier(modifiers: set[KeyModifier], keyDownUp: KeyDownUp, window = InvalidWindow) =
  template sendModifierKeyboardEvent(vk: int, isExtended: bool) =
    if window != InvalidWindow: window.activate()
    sendKeyboardEvent(vk, keyDownUp, isExtended)
    sleep(opt("sendkeydelay"))

  if kmLShift in modifiers: sendModifierKeyboardEvent(VK_LSHIFT, false)
  if kmRShift in modifiers: sendModifierKeyboardEvent(VK_RSHIFT, true)
  if kmLControl in modifiers: sendModifierKeyboardEvent(VK_LCONTROL, false)
  if kmRControl in modifiers: sendModifierKeyboardEvent(VK_RCONTROL, true)
  if kmLAlt in modifiers: sendModifierKeyboardEvent(VK_LMENU, false)
  if kmRAlt in modifiers: sendModifierKeyboardEvent(VK_RMENU, true)
  if kmLWin in modifiers: sendModifierKeyboardEvent(VK_LWIN, true)
  if kmRWin in modifiers: sendModifierKeyboardEvent(VK_RWIN, true)

proc pressKey(vk: int, downup: KeyDownUp, isExtended: bool, window = InvalidWindow) =
  if window != InvalidWindow: window.activate()
  sendKeyboardEvent(vk, downup)
  case downup
  of kDown: sleep(opt("sendkeydowndelay"))
  of kUp: sleep(opt("sendkeydelay"))

proc sendKey(vk: int, modifiers: set[KeyModifier], count: int, isExtended: bool, window = InvalidWindow) =
  if modifiers.card != 0:
    sendModifier(modifiers, kDown, window)
    sleep(opt("sendkeydowndelay"))

  for i in 1..count:
    pressKey(vk, kDown, isExtended, window)
    pressKey(vk, kUp, isExtended, window)

  if modifiers.card != 0:
    sendModifier(modifiers, kUp, window)
    sleep(opt("sendkeydelay"))

proc toggleKey(vk: int, toggle: KeyToggle, window = InvalidWindow): KeyToggle {.discardable.} =
  result = if (GetKeyState(cint vk) and 1) != 0: ktOn else: ktOff
  if toggle in {ktNil, result}: return # nothing to do

  if window != InvalidWindow: window.activate()
  sendKeyboardEvent(vk, kDown)
  sleep(opt("sendkeydowndelay"))

  if window != InvalidWindow: window.activate()
  sendKeyboardEvent(vk, kUp)
  sleep(opt("sendkeydelay"))

proc sendStringByMessage(wstr: wstring, window: Window) =
  for unicode in wstr:
    PostMessage(HWND window, WM_CHAR, WPARAM unicode, 0)
    sleep(opt("sendkeydelay"))

proc sendString(wstr: wstring, count: int = 1, window = InvalidWindow) =
  for i in 1..count:
    for unicode in wstr:
      if window != InvalidWindow: window.activate()
      sendUnicodeKeyboardEvent(unicode, kDown)
      sleep(opt("sendkeydowndelay"))

      if window != InvalidWindow: window.activate()
      sendUnicodeKeyboardEvent(unicode, kUp)
      sleep(opt("sendkeydelay"))

proc initKeyTable(): Table[string, KeyItem] =
  for i in 'a'..'z': result[$i] = KeyItem(vk: int i.toUpperAscii)
  for i in 'A'..'Z': result[$i] = KeyItem(vk: int i, shift: true)
  for i in '0'..'9': result[$i] = KeyItem(vk: int i)

  result[";"] = KeyItem(vk: VK_OEM_1)
  result[":"] = KeyItem(vk: VK_OEM_1, shift: true)
  result["/"] = KeyItem(vk: VK_OEM_2)
  result["?"] = KeyItem(vk: VK_OEM_2, shift: true)
  result["`"] = KeyItem(vk: VK_OEM_3)
  result["~"] = KeyItem(vk: VK_OEM_3, shift: true)
  result["["] = KeyItem(vk: VK_OEM_4)
  result["{"] = KeyItem(vk: VK_OEM_4, shift: true)
  result["\\"] = KeyItem(vk: VK_OEM_5)
  result["|"] = KeyItem(vk: VK_OEM_5, shift: true)
  result["]"] = KeyItem(vk: VK_OEM_6)
  result["}"] = KeyItem(vk: VK_OEM_6, shift: true)
  result["'"] = KeyItem(vk: VK_OEM_7)
  result["\""] = KeyItem(vk: VK_OEM_7, shift: true)
  result["="] = KeyItem(vk: VK_OEM_PLUS)
  result["+"] = KeyItem(vk: VK_OEM_PLUS, shift: true)
  result["-"] = KeyItem(vk: VK_OEM_MINUS)
  result["_"] = KeyItem(vk: VK_OEM_MINUS, shift: true)
  result[","] = KeyItem(vk: VK_OEM_COMMA)
  result["<"] = KeyItem(vk: VK_OEM_COMMA, shift: true)
  result["."] = KeyItem(vk: VK_OEM_PERIOD)
  result[">"] = KeyItem(vk: VK_OEM_PERIOD, shift: true)
  result[")"] = KeyItem(vk: int '0', shift: true)
  result["!"] = KeyItem(vk: int '1', shift: true)
  result["@"] = KeyItem(vk: int '2', shift: true)
  result["#"] = KeyItem(vk: int '3', shift: true)
  result["$"] = KeyItem(vk: int '4', shift: true)
  result["%"] = KeyItem(vk: int '5', shift: true)
  result["^"] = KeyItem(vk: int '6', shift: true)
  result["&"] = KeyItem(vk: int '7', shift: true)
  result["*"] = KeyItem(vk: int '8', shift: true)
  result["("] = KeyItem(vk: int '9', shift: true)
  result["SPACE"] = KeyItem(vk: VK_SPACE)
  result["ENTER"] = KeyItem(vk: VK_RETURN)
  result["ALT"] = KeyItem(vk: VK_MENU)
  result["BACKSPACE"] = KeyItem(vk: VK_BACK)
  result["BS"] = KeyItem(vk: VK_BACK)
  result["DELETE"] = KeyItem(vk: VK_DELETE, extend: true)
  result["DEL"] = KeyItem(vk: VK_DELETE, extend: true)
  result["UP"] = KeyItem(vk: VK_UP, extend: true)
  result["DOWN"] = KeyItem(vk: VK_DOWN, extend: true)
  result["LEFT"] = KeyItem(vk: VK_LEFT, extend: true)
  result["RIGHT"] = KeyItem(vk: VK_RIGHT, extend: true)
  result["HOME"] = KeyItem(vk: VK_HOME, extend: true)
  result["END"] = KeyItem(vk: VK_END, extend: true)
  result["ESCAPE"] = KeyItem(vk: VK_ESCAPE)
  result["ESC"] = KeyItem(vk: VK_ESCAPE)
  result["INSERT"] = KeyItem(vk: VK_INSERT, extend: true)
  result["INS"] = KeyItem(vk: VK_INSERT, extend: true)
  result["PGUP"] = KeyItem(vk: VK_PRIOR, extend: true)
  result["PAGEUP"] = KeyItem(vk: VK_PRIOR, extend: true)
  result["PGDN"] = KeyItem(vk: VK_NEXT, extend: true)
  result["PAGEDOWN"] = KeyItem(vk: VK_NEXT, extend: true)
  result["F1"] = KeyItem(vk: VK_F1)
  result["F2"] = KeyItem(vk: VK_F2)
  result["F3"] = KeyItem(vk: VK_F3)
  result["F4"] = KeyItem(vk: VK_F4)
  result["F5"] = KeyItem(vk: VK_F5)
  result["F6"] = KeyItem(vk: VK_F6)
  result["F7"] = KeyItem(vk: VK_F7)
  result["F8"] = KeyItem(vk: VK_F8)
  result["F9"] = KeyItem(vk: VK_F9)
  result["F10"] = KeyItem(vk: VK_F10)
  result["F11"] = KeyItem(vk: VK_F11)
  result["F12"] = KeyItem(vk: VK_F12)
  result["TAB"] = KeyItem(vk: VK_TAB)
  result["PRINTSCREEN"] = KeyItem(vk: VK_SNAPSHOT)
  result["LWIN"] = KeyItem(vk: VK_LMENU, extend: true)
  result["RWIN"] = KeyItem(vk: VK_RMENU, extend: true)
  result["NUMLOCK"] = KeyItem(vk: VK_NUMLOCK)
  result["CAPSLOCK"] = KeyItem(vk: VK_CAPITAL)
  result["SCROLLLOCK"] = KeyItem(vk: VK_SCROLL)
  result["BREAK"] = KeyItem(vk: VK_CANCEL)
  result["PAUSE"] = KeyItem(vk: VK_PAUSE)
  result["NUMPAD0"] = KeyItem(vk: VK_NUMPAD0)
  result["NUMPAD1"] = KeyItem(vk: VK_NUMPAD1)
  result["NUMPAD2"] = KeyItem(vk: VK_NUMPAD2)
  result["NUMPAD3"] = KeyItem(vk: VK_NUMPAD3)
  result["NUMPAD4"] = KeyItem(vk: VK_NUMPAD4)
  result["NUMPAD5"] = KeyItem(vk: VK_NUMPAD5)
  result["NUMPAD6"] = KeyItem(vk: VK_NUMPAD6)
  result["NUMPAD7"] = KeyItem(vk: VK_NUMPAD7)
  result["NUMPAD8"] = KeyItem(vk: VK_NUMPAD8)
  result["NUMPAD9"] = KeyItem(vk: VK_NUMPAD9)
  result["NUMPADMULT"] = KeyItem(vk: VK_MULTIPLY)
  result["NUMPADADD"] = KeyItem(vk: VK_ADD)
  result["NUMPADSUB"] = KeyItem(vk: VK_SUBTRACT)
  result["NUMPADDIV"] = KeyItem(vk: VK_DIVIDE, extend: true)
  result["NUMPADDOT"] = KeyItem(vk: VK_DECIMAL)
  result["NUMPADENTER"] = KeyItem(vk: VK_RETURN, extend: true)
  result["APPSKEY"] = KeyItem(vk: VK_APPS, extend: true)
  result["LALT"] = KeyItem(vk: VK_LMENU)
  result["RALT"] = KeyItem(vk: VK_RMENU, extend: true)
  result["LCTRL"] = KeyItem(vk: VK_LCONTROL)
  result["RCTRL"] = KeyItem(vk: VK_RCONTROL, extend: true)
  result["LSHIFT"] = KeyItem(vk: VK_LSHIFT)
  result["RSHIFT"] = KeyItem(vk: VK_RSHIFT, extend: true)
  result["SLEEP"] = KeyItem(vk: VK_SLEEP, extend: true)
  result["BROWSERBACK"] = KeyItem(vk: VK_BROWSER_BACK, extend: true)
  result["BROWSERFORWARD"] = KeyItem(vk: VK_BROWSER_FORWARD, extend: true)
  result["BROWSERREFRESH"] = KeyItem(vk: VK_BROWSER_REFRESH, extend: true)
  result["BROWSERSTOP"] = KeyItem(vk: VK_BROWSER_STOP, extend: true)
  result["BROWSERSEARCH"] = KeyItem(vk: VK_BROWSER_SEARCH, extend: true)
  result["BROWSERFAVORITES"] = KeyItem(vk: VK_BROWSER_FAVORITES, extend: true)
  result["BROWSERHOME"] = KeyItem(vk: VK_BROWSER_HOME, extend: true)
  result["VOLUMEMUTE"] = KeyItem(vk: VK_VOLUME_MUTE, extend: true)
  result["VOLUMEDOWN"] = KeyItem(vk: VK_VOLUME_DOWN, extend: true)
  result["VOLUMEUP"] = KeyItem(vk: VK_VOLUME_UP, extend: true)
  result["MEDIANEXT"] = KeyItem(vk: VK_MEDIA_NEXT_TRACK, extend: true)
  result["MEDIAPREV"] = KeyItem(vk: VK_MEDIA_PREV_TRACK, extend: true)
  result["MEDIASTOP"] = KeyItem(vk: VK_MEDIA_STOP, extend: true)
  result["MEDIAPLAYPAUSE"] = KeyItem(vk: VK_MEDIA_PLAY_PAUSE, extend: true)
  result["LAUNCHMAIL"] = KeyItem(vk: VK_LAUNCH_MAIL, extend: true)
  result["LAUNCHMEDIA"] = KeyItem(vk: VK_LAUNCH_MEDIA_SELECT, extend: true)
  result["LAUNCHAPP1"] = KeyItem(vk: VK_LAUNCH_APP1, extend: true)
  result["LAUNCHAPP2"] = KeyItem(vk: VK_LAUNCH_APP2, extend: true)
  result["NUMLOCK"] = KeyItem(vk: VK_NUMLOCK)
  result["CAPSLOCK"] = KeyItem(vk: VK_CAPITAL)
  result["SCROLLLOCK"] = KeyItem(vk: VK_SCROLL)

proc initModifierTable(): Table[string, ModifierItem] =
  result["ALTDOWN"] = ModifierItem(modifier: kmLAlt, downup: kDown)
  result["LALTDOWN"] = ModifierItem(modifier: kmLAlt, downup: kDown)
  result["RALTDOWN"] = ModifierItem(modifier: kmRAlt, downup: kDown)
  result["ALTUP"] = ModifierItem(modifier: kmLAlt, downup: kUp)
  result["LALTUP"] = ModifierItem(modifier: kmLAlt, downup: kUp)
  result["RALTUP"] = ModifierItem(modifier: kmRAlt, downup: kUp)

  result["SHIFTDOWN"] = ModifierItem(modifier: kmLShift, downup: kDown)
  result["LSHIFTDOWN"] = ModifierItem(modifier: kmLShift, downup: kDown)
  result["RSHIFTDOWN"] = ModifierItem(modifier: kmRShift, downup: kDown)
  result["SHIFTUP"] = ModifierItem(modifier: kmLShift, downup: kUp)
  result["LSHIFTUP"] = ModifierItem(modifier: kmLShift, downup: kUp)
  result["RSHIFTUP"] = ModifierItem(modifier: kmRShift, downup: kUp)

  result["CTRLDOWN"] = ModifierItem(modifier: kmLControl, downup: kDown)
  result["LCTRLDOWN"] = ModifierItem(modifier: kmLControl, downup: kDown)
  result["RCTRLDOWN"] = ModifierItem(modifier: kmRControl, downup: kDown)
  result["CTRLUP"] = ModifierItem(modifier: kmLControl, downup: kUp)
  result["LCTRLUP"] = ModifierItem(modifier: kmLControl, downup: kUp)
  result["RCTRLUP"] = ModifierItem(modifier: kmRControl, downup: kUp)

  result["WINDOWN"] = ModifierItem(modifier: kmLWin, downup: kDown)
  result["LWINDOWN"] = ModifierItem(modifier: kmLWin, downup: kDown)
  result["RWINDOWN"] = ModifierItem(modifier: kmRWin, downup: kDown)
  result["WINUP"] = ModifierItem(modifier: kmLWin, downup: kUp)
  result["LWINUP"] = ModifierItem(modifier: kmLWin, downup: kUp)
  result["RWINUP"] = ModifierItem(modifier: kmRWin, downup: kUp)

proc send(cmd: KeyCommand, window = InvalidWindow) =
  const
    keyTable = initKeyTable()
    modifierTable = initModifierTable()

  var
    presistModifiers {.global.}: set[KeyModifier]
    cmd = cmd

  let keyName =
    if cmd.text.len > 1:
      cmd.text.replace("_", "").toUpperAscii
    else:
      cmd.text

  if keyName == "ASC":
    # Send as unicode input
    sendString(+$ WCHAR(cmd.count), 1, window)

  elif keyName in keyTable:
    # Send as keystroke in keytable
    let item = keyTable[keyName]
    if item.shift: cmd.modifiers.incl kmLShift

    # Ignores the modifiers that are already be pressed down
    cmd.modifiers.excl presistModifiers

    if cmd.toggle in {ktDown, ktUp}:
      let downup = if cmd.toggle == ktDown: kDown else: kUp
      pressKey(item.vk, downup, item.extend, window)

    elif item.vk in {VK_NUMLOCK, VK_CAPITAL, VK_SCROLL} and cmd.toggle in {ktOn, ktOff, ktToggle}:
      toggleKey(item.vk, cmd.toggle, window)

    else:
      sendKey(item.vk, cmd.modifiers, cmd.count, item.extend, window)

  elif keyName in modifierTable:
    # Send modifier down or up
    let item = modifierTable[keyName]
    sendModifier({item.modifier}, item.downup, window)

    if item.downup == kDown:
      presistModifiers.incl item.modifier
    else:
      presistModifiers.excl item.modifier

  else:
    # Send as string
    sendString(+$cmd.text, cmd.count, window)

proc send*(text: string, raw = false, window = InvalidWindow, attach = false,
    restoreCapslock = false) =
  ## Sends simulated keystrokes to the active window.
  ## If *raw* is true, keys are sent raw.
  ## If *window* is specified, it attempts to keep it active during send().
  ## If *attach* is true, it attaches input threads when during send().
  ## If *restoreCapslock* is true, the state of capslock is restored after send().
  ##
  ## ================================  =============================================================
  ## Syntax                            Description
  ## ================================  =============================================================
  ## +                                 Combine next key with SHIFT.
  ## !                                 Combine next key with ALT.
  ## ^                                 Combine next key with CTRL.
  ## #                                 Combine next key with Windows key.
  ## {!}                               !
  ## {#}                               #
  ## {+}                               +
  ## {^}                               ^
  ## {{}                               {
  ## {}}                               }
  ## {SPACE}                           SPACE
  ## {ENTER}                           ENTER
  ## {ALT}                             ALT
  ## {BACKSPACE} or {BS}               BACKSPACE
  ## {DELETE} or {DEL}                 DELETE
  ## {UP}                              Up arrow
  ## {DOWN}                            Down arrow
  ## {LEFT}                            Left arrow
  ## {RIGHT}                           Right arrow
  ## {HOME}                            HOME
  ## {END}                             END
  ## {ESCAPE} or {ESC}                 ESCAPE
  ## {INSERT} or {INS}                 INS
  ## {PGUP}                            PageUp
  ## {PGDN}                            PageDown
  ## {F1} - {F12}                      Function keys
  ## {TAB}                             TAB
  ## {PRINTSCREEN}                     Print Screen key
  ## {LWIN}                            Left Windows key
  ## {RWIN}                            Right Windows key
  ## {NUMLOCK on/off/toggle}           NUMLOCK (on/off/toggle)
  ## {CAPSLOCK on/off/toggle}          CAPSLOCK (on/off/toggle)
  ## {SCROLLLOCK on/off/toggle}        SCROLLLOCK (on/off/toggle)
  ## {BREAK}                           Break
  ## {PAUSE}                           Pause
  ## {NUMPAD0} - {NUMPAD9}             Numpad digits
  ## {NUMPADMULT}                      Numpad Multiply
  ## {NUMPADADD}                       Numpad Add
  ## {NUMPADSUB}                       Numpad Subtract
  ## {NUMPADDIV}                       Numpad Divide
  ## {NUMPADDOT}                       Numpad period
  ## {NUMPADENTER}                     Enter key on the numpad
  ## {APPSKEY}                         Windows App key
  ## {LALT}                            Left ALT key
  ## {RALT}                            Right ALT key
  ## {LCTRL}                           Left CTRL key
  ## {RCTRL}                           Right CTRL key
  ## {LSHIFT}                          Left Shift key
  ## {RSHIFT}                          Right Shift key
  ## {SLEEP}                           Computer SLEEP key
  ## {ALTDOWN}                         Holds the ALT key down until {ALTUP}
  ## {LALTDOWN} or {RALTDOWN}          Holds the left or right ALT key down until {LALTUP} or {RALTUP}
  ## {SHIFTDOWN}                       Holds the SHIFT key down until {SHIFTUP}
  ## {LSHIFTDOWN} or {RSHIFTDOWN}      Holds the left or right SHIFT key down until {LALTUP} or {RALTUP}
  ## {CTRLDOWN}                        Holds the CTRL key down until {CTRLUP}
  ## {LCTRLDOWN} or {RCTRLDOWN}        Holds the left or right CTRL key down until {LCTRLUP} or {RCTRLUP}
  ## {WINDOWN}                         Holds the left Windows key down until {WINUP}
  ## {LWINDOWN} or {RWINDOWN}          Holds the left or right Windows key down until {LWINUP} or {RWINUP}
  ## {ASC nnnn}                        Send the specified ASCII character
  ## {BROWSER_BACK}                    Select the browser "back" button
  ## {BROWSER_FORWARD}                 Select the browser "forward" button
  ## {BROWSER_REFRESH}                 Select the browser "refresh" button
  ## {BROWSER_STOP}                    Select the browser "stop" button
  ## {BROWSER_SEARCH}                  Select the browser "search" button
  ## {BROWSER_FAVORITES}               Select the browser "favorites" button
  ## {BROWSER_HOME}                    Launch the browser and go to the home page
  ## {VOLUME_MUTE}                     Mute the volume
  ## {VOLUME_DOWN}                     Reduce the volume
  ## {VOLUME_UP}                       Increase the volume
  ## {MEDIA_NEXT}                      Select next track in media player
  ## {MEDIA_PREV}                      Select previous track in media player
  ## {MEDIA_STOP}                      Stop media player
  ## {MEDIA_PLAY_PAUSE}                Play/pause media player
  ## {LAUNCH_MAIL}                     Launch the email application
  ## {LAUNCH_MEDIA}                    Launch media player
  ## {LAUNCH_APP1}                     Launch user app1
  ## {LAUNCH_APP2}                     Launch user app2
  ## {KEY n}                           KEY (or character) will be sent repeated n times
  ## ================================  =============================================================

  runnableExamples:
    import window

    proc example() =
      send("#r")
      send("notepad{enter}")
      send("abc{BS 3}def", window=waitAny(window.className == "Notepad"))
      send("!fxn")

  let
    window = window
    (tid, pid) = (GetCurrentThreadId(), GetWindowThreadProcessId(HWND window, nil))
    capslock = toggleKey(VK_CAPITAL, ktOff, window=window)

  if attach:
    AttachThreadInput(tid, pid, TRUE)

  defer:
    if attach: AttachThreadInput(tid, pid, FALSE)
    if restoreCapslock: toggleKey(VK_CAPITAL, capslock, window=window)

  if raw:
    sendString(+$text, window=window)
    return

  var
    state = KeyCommand(count: 1)
    isSpecial = false

  let p = peg "start":
    start <- *key
    key <- modifier * (special | uchar):
      var cmd = KeyCommand(count: 1, text: state.text, modifiers: state.modifiers)

      if isSpecial:
        # state.toggle and state.count is only vaild if isSpecial = true
        cmd.toggle = state.toggle
        cmd.count = state.count

      send(cmd, window)

      # reset the state
      state = KeyCommand(count: 1)
      isSpecial = false

    modifier <- *{'+', '!', '^', '#'}:
      if '+' in $0: state.modifiers.incl kmLShift
      if '!' in $0: state.modifiers.incl kmLAlt
      if '^' in $0: state.modifiers.incl kmLControl
      if '#' in $0: state.modifiers.incl kmLWin

    special <- '{' * *Blank * name * >?supplement * *Blank * '}':
      isSpecial = true

    supplement <- +Blank * (toggle | count)

    toggle <- i"ON" | i"OFF" | i"TOGGLE" | i"DOWN" | i"UP":
      state.toggle = case ($0).toUpperAscii
        of "ON": ktOn
        of "OFF": ktOff
        of "TOGGLE": ktToggle
        of "DOWN": ktDown
        of "UP": ktUp
        else: ktNil

    count <- +Digit:
      state.count = parseInt($0)

    name <- +(utf8.any - {' ', '\t', '}'}):
      state.text = $0

    uchar <- utf8.any:
      # if special fail, backtrack to uchar, the text will be overwrite
      state.text = $0

  discard p.match(text)

proc send*(window: Window, text: string) =
  ## Sends a string of characters to a window.
  ## This window must process WM_CHAR event, for example: an editor contorl.
  let (tid, pid) = (GetCurrentThreadId(), GetWindowThreadProcessId(HWND window, nil))
  sendStringByMessage(+$text, window)
  AttachThreadInput(tid, pid, FALSE)

var hkData {.threadvar.}: HotkeyData

proc keyProc(nCode: int32, wParam: WPARAM, lParam: LPARAM): LRESULT {.stdcall.} =
  var processed = false
  let kbd = cast[LPKBDLLHOOKSTRUCT](lParam)
  defer:
    result = if processed: LRESULT 1 else: CallNextHookEx(0, nCode, wParam, lParam)

  case int wParam
  of WM_KEYUP, WM_SYSKEYUP:
    hkData.lastKeyCode = 0
    var isMod = false

    case int kbd.vkCode
    of VK_LCONTROL, VK_RCONTROL: hkData.lastModifiers = hkData.lastModifiers and (not wModCtrl); isMod = true
    of VK_LMENU, VK_RMENU: hkData.lastModifiers = hkData.lastModifiers and (not wModAlt); isMod = true
    of VK_LSHIFT, VK_RSHIFT: hkData.lastModifiers = hkData.lastModifiers and (not wModShift); isMod = true
    of VK_LWIN, VK_RWIN: hkData.lastModifiers = hkData.lastModifiers and (not wModWin); isMod = true
    else: discard

  of WM_KEYDOWN, WM_SYSKEYDOWN:
    case int kbd.vkCode

    of VK_LCONTROL, VK_RCONTROL, VK_LMENU, VK_RMENU, VK_LSHIFT, VK_RSHIFT, VK_LWIN, VK_RWIN:
      hkData.lastKeyCode = 0
      case int kbd.vkCode
      of VK_LCONTROL, VK_RCONTROL: hkData.lastModifiers = hkData.lastModifiers or wModCtrl
      of VK_LMENU, VK_RMENU: hkData.lastModifiers = hkData.lastModifiers or wModAlt
      of VK_LSHIFT, VK_RSHIFT: hkData.lastModifiers = hkData.lastModifiers or wModShift
      of VK_LWIN, VK_RWIN: hkData.lastModifiers = hkData.lastModifiers or wModWin
      else: discard

    else:
      let keyCode = int kbd.vkCode
      var modifiers = 0
      if hkData.lastModifiers != 0:
        if (GetAsyncKeyState(VK_CONTROL) and 0x8000) != 0: modifiers = modifiers or wModCtrl
        if (GetAsyncKeyState(VK_MENU) and 0x8000) != 0: modifiers = modifiers or wModAlt
        if (GetAsyncKeyState(VK_SHIFT) and 0x8000) != 0: modifiers = modifiers or wModShift
        if (GetAsyncKeyState(VK_LWIN) and 0x8000) != 0 or (GetAsyncKeyState(VK_RWIN) and 0x8000) != 0:
          modifiers = modifiers or wModWin
          hkData.lastModifiers = modifiers

      if keyCode != hkData.lastKeyCode:
        let hotkey = (modifiers, keyCode)
        hkData.table.withValue(hotkey, winData):
          let ret = int SendMessage(winData.hwnd, WM_HOTKEY, WPARAM winData.id, MAKELPARAM(modifiers, keyCode))
          if ret <= 0:
            processed = true

      hkData.lastKeyCode = keyCode

  else: discard

proc registerHotKeyEx*(self: wWindow, id: int, hotkey: Hotkey): bool
    {.validate, discardable.} =
  ## Registers a system wide hotkey. Every time the user presses the hotkey
  ## registered here, the window will receive a wEvent_HotKey event.
  ## If the user processes wEvent_HotKey event and set a postive result
  ## (e.g. event.result = 1), the key will not be blocked.
  ##
  ## The difference from wNim/wWindow.registerHotKey() is that this procedure
  ## use low-level keyboard hook instead of RegisterHotKey API. So that the
  ## system default key combination can be replaced, For example: Win + R.
  if hkData.hHook == 0:
    hkData.hHook = SetWindowsHookEx(WH_KEYBOARD_LL, keyProc, GetModuleHandle(nil), 0)
    if hkData.hHook == 0:
      return false

  hkData.table[hotkey] = (self.getHandle, id)

proc registerHotKeyEx*(self: wWindow, id: int, hotkey: string): bool
    {.validate, inline, discardable.} =
  ## Registers a system wide hotkey. Accept a hotkey string.

  runnableExamples:
    import wNim/wFrame

    proc example() =
      var frame = Frame()
      frame.registerHotKeyEx(0, "Ctrl + Alt + F1")

  result = self.registerHotKeyEx(id, wStringToHotkey(hotkey))

proc unregisterHotKeyEx*(self: wWindow, id: int): bool
    {.validate, discardable.} =
  ## Unregisters a system wide hotkey.
  for hotkey, winData in hkData.table:
    if winData == (self.getHandle, id):
      hkData.table.del hotkey
      break

  if hkData.table.len == 0 and hkData.hHook != 0:
    UnhookWindowsHookEx(hkData.hHook)
    hkData.hHook = 0
