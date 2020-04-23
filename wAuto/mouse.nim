#====================================================================
#
#               wAuto - Windows Automation Module
#                   (c) Copyright 2020 Ward
#
#====================================================================

## This module contains support to simulate mouse movements and clicks.
## For all functions that receives pos (or x, y) as parameter, wDefaultPoint
## or wDefault can be specified to indicate not to change.
##
## The *speed* parameter is the speed to move the mouse in the range 1 (fastest)
## to 100 (slowest). A speed of 0 will move the mouse instantly.

{.deadCodeElim: on.}

import tables
import winim/lean except CURSORSHAPE
import wNim/[wApp, wMacros, wUtils]
import common, private/utils

export common, wApp.wDefault, wApp.wDefaultPoint

proc coordAbs(coord, n: int): int =
  (((65535 * coord) div (n - 1)) + 1)

proc sendMouseEvent(flag: DWORD, pos: wPoint, mouseData: DWORD = 0, extra: ULONG_PTR = 0) =
  var input = INPUT(`type`: INPUT_MOUSE)
  input.mi.dx = LONG pos.x
  input.mi.dy = LONG pos.y
  input.mi.mouseData = mouseData
  input.mi.dwFlags = flag
  input.mi.dwExtraInfo = extra
  SendInput(1, &input, cint sizeof(INPUT))

proc getMouseMessage(mb: MouseButton): (DWORD, DWORD) =
  let mb = case mb
    of mbPrimary:
      if GetSystemMetrics(SM_SWAPBUTTON) == 0: mbLeft else: mbRight
    of mbSecondary:
      if GetSystemMetrics(SM_SWAPBUTTON) == 0: mbRight else: mbLeft
    else: mb

  result = case mb
    of mbRight: (DWORD MOUSEEVENTF_RIGHTDOWN, DWORD MOUSEEVENTF_RIGHTUP)
    of mbMiddle: (DWORD MOUSEEVENTF_MIDDLEDOWN, DWORD MOUSEEVENTF_MIDDLEUP)
    else: (DWORD MOUSEEVENTF_LEFTDOWN, DWORD MOUSEEVENTF_LEFTUP)

proc getCursorPosition*(): wPoint {.property.} =
  ## Retrieves the current position of the mouse cursor.
  var p: POINT
  GetCursorPos(&p)
  result.x = int p.x
  result.y = int p.y

proc getCursorShape*(): CursorShape {.property.} =
  ## Returns the current mouse cursor shape.
  let hwnd = GetForegroundWindow()
  let (tid, pid) = (GetCurrentThreadId(), GetWindowThreadProcessId(hwnd, nil))
  AttachThreadInput(tid, pid, TRUE)
  defer: AttachThreadInput(tid, pid, FALSE)

  const list = [
    (IDC_APPSTARTING, csAppStarting), (IDC_ARROW, csArrow), (IDC_CROSS, csCross),
    (IDC_HELP, csHelp), (IDC_IBEAM, csIBeam), (IDC_ICON, csIcon),  (IDC_NO, csNo),
    (IDC_SIZE, csSize), (IDC_SIZEALL, csSizeAll), (IDC_SIZENESW, csSizeNesw),
    (IDC_SIZENS, csSizeNs), (IDC_SIZENWSE, csSizeNwse),  (IDC_SIZEWE, csSizeWe),
    (IDC_UPARROW, csUpArrow), (IDC_WAIT, csWait), (IDC_HAND, csHand)]

  var map {.global.}: Table[HCURSOR, CursorShape]
  once:
    for (id, shape) in list:
      let hCursor = LoadCursor(0, id)
      if hCursor != 0:
        map[hCursor] = shape

  map.withValue(GetCursor(), shape) do:
    return shape[]
  do:
    return csUnknow

proc mouseMoveRaw(pos = wDefaultPoint, speed: range[0..100] = 10): wPoint {.discardable.} =
  let (width, height) = wGetScreenSize()

  var (x0, y0) = getCursorPosition()
  x0 = x0.coordAbs(width)
  y0 = y0.coordAbs(height)

  var
    x = if pos.x == wDefault: x0 else: pos.x.coordAbs(width)
    y = if pos.y == wDefault: y0 else: pos.y.coordAbs(height)

  if speed == 0:
    sendMouseEvent(MOUSEEVENTF_MOVE or MOUSEEVENTF_ABSOLUTE, (x, y))

  else:
    proc step(n1: var int, n2: int, ratio: float = 1) =
      var delta = (abs(n2 - n1) div speed).clamp(32, int.high)
      if n1 < n2:
        n1 = (n1 + delta).clamp(n1, n2)

      elif n1 > n2:
        n1 = (n1 - delta).clamp(n2, n1)

    while x0 != x or y0 != y:
      step(x0, x)
      step(y0, y)
      sendMouseEvent(MOUSEEVENTF_MOVE or MOUSEEVENTF_ABSOLUTE, (x0, y0))
      Sleep(10)

  result = (x, y)

proc move*(pos = wDefaultPoint, speed: range[0..100] = 10) =
  ## Moves the mouse pointer to *pos*.
  mouseMoveRaw(pos, speed)

proc move*(x = wDefault, y = wDefault, speed: range[0..100] = 10) =
  ## Moves the mouse pointer to (x, y).
  move((x, y), speed)

proc down*(button: MouseButton = mbLeft) =
  ## Perform a mouse down event at the current mouse position.
  let (down, _) = getMouseMessage(button)
  let coord = mouseMoveRaw(wDefaultPoint, 0)
  sendMouseEvent(MOUSEEVENTF_ABSOLUTE or down, coord)
  sleep(opt("mouseclickdowndelay"))

proc up*(button: MouseButton = mbLeft) =
  ## Perform a mouse up event at the current mouse position.
  let (_, up) = getMouseMessage(button)
  let coord = mouseMoveRaw(wDefaultPoint, 0)
  sendMouseEvent(MOUSEEVENTF_ABSOLUTE or up, coord)
  sleep(opt("mouseclickdelay"))

proc click*(button: MouseButton = mbLeft, pos = wDefaultPoint, clicks = 1, speed: range[0..100] = 10) =
  ## Perform a mouse click operation at the position *pos*.
  ## *clicks* is the number of times to click the mouse.
  let (down, up) = getMouseMessage(button)
  let coord = mouseMoveRaw(pos, speed)
  for i in 0 ..< clicks:
    sendMouseEvent(MOUSEEVENTF_ABSOLUTE or down, coord)
    sleep(opt("mouseclickdowndelay"))
    sendMouseEvent(MOUSEEVENTF_ABSOLUTE or up, coord)
    sleep(opt("mouseclickdelay"))

proc click*(button: MouseButton, x, y = wDefault, clicks = 1, speed: range[0..100] = 10) =
  ## Perform a mouse click operation at the position (x, y).
  ## *clicks* is the number of times to click the mouse.
  click(button, (x, y), clicks, speed)

proc clickDrag*(button: MouseButton = mbLeft, pos1, pos2 = wDefaultPoint, speed: range[0..100] = 10) =
  ## Perform a mouse click and drag operation from *pos1* to *pos2*.
  let (down, up) = getMouseMessage(button)
  var coord = mouseMoveRaw(pos1, speed)
  sendMouseEvent(MOUSEEVENTF_ABSOLUTE or down, coord)
  sleep(opt("mouseclickdragdelay"))

  coord = mouseMoveRaw(pos2, speed)
  sendMouseEvent(MOUSEEVENTF_ABSOLUTE or up, coord)
  sleep(opt("mouseclickdragdelay"))

proc wheelUp*(clicks = 1) =
  ## Moves the mouse wheel up.
  ## *clicks* is the number of times to move the wheel.
  var coord = mouseMoveRaw(wDefaultPoint, 0)
  sendMouseEvent(MOUSEEVENTF_ABSOLUTE or MOUSEEVENTF_WHEEL, coord, mouseData=WHEEL_DELTA)
  sleep(opt("mouseclickdelay"))

proc wheelDown*(clicks = 1) =
  ## Moves the mouse wheel down.
  ## *clicks* is the number of times to move the wheel.
  var coord = mouseMoveRaw(wDefaultPoint, 0)
  sendMouseEvent(MOUSEEVENTF_ABSOLUTE or MOUSEEVENTF_WHEEL, coord, mouseData=(-WHEEL_DELTA))
  sleep(opt("mouseclickdelay"))
