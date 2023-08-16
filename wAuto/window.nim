#====================================================================
#
#               wAuto - Windows Automation Module
#               Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

## This module contains support to manipulate windows and standard windows controls.
## There are two ways to find a specified window. windows() iterator,
## or enumerate() template. The main difference is that inside the iterator,
## it must create a seq of all windows and then yield one by one. However, the
## enumerate() template can be break during enumeration if specified window is
## found. Moreover, the enumerate() template can aslo collect the window
## that match the specified condition.

import strutils
import winim/lean, winim/inc/commctrl
import wNim/[wApp, wMacros]
import common, private/utils

export common, wApp.wDefault, wApp.wDefaultPoint

type
  EnumWindowCallback = proc (hwnd: HWND): bool
  EnumerateBreakError = object of CatchableError

  EnumData = object
    callback: EnumWindowCallback
    isBreak: bool

  EnumTextData = object
    detectHidden: bool
    text: string

proc getClassName*(window: Window): string
proc getTitle*(window: Window): string

proc `$`*(x: Window): string {.borrow.}
  ## The stringify operator for a window.

proc `==`*(x, y: Window): bool {.borrow.}
  ## Checks for equality between two window.

proc repr*(x: Window): string =
  ## Returns string representation of a window.
  result = "Window(ClassName: "
  result.add x.getClassName.escape
  result.add ", Title: "
  result.add x.getTitle.escape
  result.add ")"

proc getMouseMessage(mb: MouseButton): (int, int, int) =
  let mb = case mb
    of mbPrimary:
      if GetSystemMetrics(SM_SWAPBUTTON) == 0: mbLeft else: mbRight
    of mbSecondary:
      if GetSystemMetrics(SM_SWAPBUTTON) == 0: mbRight else: mbLeft
    else: mb

  result = case mb
    of mbRight: (WM_RBUTTONDOWN, WM_RBUTTONUP, MK_RBUTTON)
    of mbMiddle: (WM_MBUTTONDOWN, WM_MBUTTONUP, MK_MBUTTON)
    else: (WM_LBUTTONDOWN, WM_LBUTTONUP, MK_LBUTTON)

proc enumChildrenProc(hwnd: HWND, data: LPARAM): WINBOOL {.stdcall.} =
  let pData = cast[ptr EnumData](data)
  pData[].isBreak = pData[].callback(hwnd)
  return not pData[].isBreak

proc enumDescendantsProc(hwnd: HWND, data: LPARAM): WINBOOL {.stdcall.} =
  let pData = cast[ptr EnumData](data)
  pData[].isBreak = pData[].callback(hwnd)
  if not pData[].isBreak:
    EnumChildWindows(hwnd, enumDescendantsProc, data)

  return not pData[].isBreak

proc enumChildrenTextProc(hwnd: HWND, data: LPARAM): WINBOOL {.stdcall.} =
  let pData = cast[ptr EnumTextData](data)
  defer:
    result = true # the callback return true to continue enumeration

  if IsWindowVisible(hwnd) == FALSE and not pData[].detectHidden:
    return

  var length: LRESULT
  if SendMessageTimeout(hwnd, WM_GETTEXTLENGTH, 0, 0,
    SMTO_ABORTIFHUNG, 100, cast[PDWORD_PTR](&length)) == 0: return

  var buffer = T(length + 8)
  var ret: int

  if SendMessageTimeout(hwnd, WM_GETTEXT, WPARAM buffer.len, cast[LPARAM](&buffer),
    SMTO_ABORTIFHUNG, 100, cast[PDWORD_PTR](&ret)) == 0: return

  buffer.setLen(ret)
  pData[].text.add($buffer & "\n")

proc enumChildren(callback: EnumWindowCallback) =
  # Enumerates all top-level windows.
  # The callback return true to stop enumeration.
  var data = EnumData(callback: callback)
  EnumWindows(enumChildrenProc, cast[LPARAM](addr data))

proc enumChildren(hwnd: HWND, callback: EnumWindowCallback) =
  # Enumerates the children that belong to the specified parent window.
  # The callback return true to stop enumeration.
  var data = EnumData(callback: callback)
  EnumChildWindows(hwnd, enumChildrenProc, cast[LPARAM](addr data))

proc enumDescendants(callback: EnumWindowCallback) =
  # Enumerates all top-level windows and their descendants.
  # The callback return true to stop enumeration.
  var data = EnumData(callback: callback)
  EnumWindows(enumDescendantsProc, cast[LPARAM](addr data))

proc enumDescendants(hwnd: HWND, callback: EnumWindowCallback) =
  # Enumerates all the descendants that belong to the specified window.
  # The callback return true to stop enumeration.
  var data = EnumData(callback: callback)
  EnumChildWindows(hwnd, enumDescendantsProc, cast[LPARAM](addr data))

proc getHandle*(window: Window): HWND {.property, inline.} =
  ## Gets the Win32 hWnd from the specified window.
  result = HWND window

proc getTitle*(window: Window): string {.property.} =
  ## Retrieves the full title from a window.
  var title = T(65536)
  title.setLen(GetWindowText(HWND window, &title, 65536))
  result = $title

proc setTitle*(window: Window, title: string) {.property.} =
  ## Changes the title of a window.
  SetWindowText(HWND window, title)

proc getClassName*(window: Window): string {.property.} =
  ## Retrieves the class name from a window.
  var class = T(256)
  class.setLen(GetClassName(HWND window, &class, 256))
  result = $class

proc getText*(window: Window, detectHidden = false): string {.property.} =
  ## Retrieves the text from a window.
  var data = EnumTextData(detectHidden: detectHidden)
  discard enumChildrenTextProc(HWND window, cast[LPARAM](addr data))
  EnumChildWindows(HWND window, enumChildrenTextProc, cast[LPARAM](addr data))
  result = data.text

proc getStatusBarText*(window: Window, index = 0): string {.property.} =
  ## Retrieves the text from a standard status bar control.
  var pResult = addr result

  proc doGetText(hStatus: HWND) =
    var count, length: int
    if SendMessageTimeout(hStatus, SB_GETPARTS, 0, 0,
      SMTO_ABORTIFHUNG, 100, cast[PDWORD_PTR](&count)) == 0: return

    if SendMessageTimeout(hStatus, SB_GETTEXTLENGTH, WPARAM index, 0,
      SMTO_ABORTIFHUNG, 100, cast[PDWORD_PTR](&length)) == 0: return

    length = length and 0xffff
    if length == 0: return

    let bufferSize = length * sizeof(TChar) + 8
    var rp = remoteAlloc(HWND window, bufferSize)
    if not rp.ok: return
    defer: rp.remoteDealloc()

    if SendMessageTimeout(hStatus, SB_GETTEXT, WPARAM index, cast[LPARAM](rp.address),
      SMTO_ABORTIFHUNG, 100, cast[PDWORD_PTR](&length)) == 0: return

    length = length and 0xffff
    if length == 0: return

    var buffer = rp.remoteRead()
    pResult[] = nullTerminated($cast[TString](buffer))

  if window.getClassName == "msctls_statusbar32":
    doGetText(HWND window)

  else:
    enumDescendants(HWND window) do (hStatus: HWND) -> bool:
      if getClassName(Window hStatus) == "msctls_statusbar32":
        doGetText(hStatus)
        return true

proc getPosition*(window: Window, pos: wPoint = (0, 0)): wPoint {.property.} =
  ## Retrieves the screen coordinates of specified window position.
  var rect: RECT
  if GetWindowRect(HWND window, &rect):
    result = (pos.x + int rect.left, pos.y + int rect.top)

proc getPosition*(window: Window, x: int, y: int): wPoint {.property.} =
  ## Retrieves the screen coordinates of specified window position.

  runnableExamples:
    import mouse

    proc example() =
      move(activeWindow().position(100, 100))

  result = getPosition(window, (x, y))

proc setPosition*(window: Window, pos: wPoint) {.property.} =
  ## Moves a window.
  SetWindowPos(HWND window, 0, cint pos.x, cint pos.y, 0, 0,
    SWP_NOZORDER or SWP_NOREPOSITION or SWP_NOACTIVATE or SWP_NOSIZE)

proc setPosition*(window: Window, x: int, y: int) {.property, inline.} =
  ## Moves a window.
  setPosition(window, (x, y))

proc getClientPosition*(window: Window, pos: wPoint = (0, 0)): wPoint {.property.} =
  ## Retrieves the screen coordinates of specified client-area coordinates.
  var pt = POINT(x: LONG pos.x, y: LONG pos.y)
  ClientToScreen(HWND window, &pt)
  result = (int pt.x, int pt.y)

proc getClientPosition*(window: Window, x: int, y: int): wPoint {.property.} =
  ## Retrieves the screen coordinates of specified client-area coordinates.

  runnableExamples:
    import mouse

    proc example() =
      move(activeWindow().clientPosition(100, 100))

  result = getClientPosition(window, (x, y))

proc setSize*(window: Window, size: wSize) {.property.} =
  ## Resizes a window.
  SetWindowPos(HWND window, 0, 0, 0, cint size.width, cint size.height,
    SWP_NOZORDER or SWP_NOREPOSITION or SWP_NOACTIVATE or SWP_NOMOVE)

proc setSize*(window: Window, width: int, height: int) {.property, inline.} =
  ## Resizes a window.
  setSize(window, (width, height))

proc getSize*(window: Window): wSize {.property.} =
  ## Retrieves the size of a given window.
  var rect: RECT
  if GetWindowRect(HWND window, &rect):
    result = (int(rect.right - rect.left), int(rect.bottom - rect.top))

proc getRect*(window: Window): wRect {.property.} =
  ## Retrieves the position and size of a given window.
  var rect: RECT
  if GetWindowRect(HWND window, &rect):
    result.x = int rect.left
    result.y = int rect.top
    result.width = int(rect.right - rect.left)
    result.height = int(rect.bottom - rect.top)

proc setRect*(window: Window, rect: wRect) {.property.} =
  ## Moves and resizes a window.
  SetWindowPos(HWND window, 0, cint rect.x, cint rect.y, cint rect.width, cint rect.height,
    SWP_NOZORDER or SWP_NOREPOSITION or SWP_NOACTIVATE)

proc setRect*(window: Window, x: int, y: int, width: int, height: int) {.property, inline.} =
  ## Moves and resizes a window.
  setRect(window, (x, y, width, height))

proc getCaretPos*(window: Window): wPoint {.property.} =
  ## Returns the coordinates of the caret in the given window (works for foreground window only).
  if window.HWND != GetForegroundWindow():
    return (-1, -1)

  let (tid, pid) = (GetCurrentThreadId(), GetWindowThreadProcessId(HWND window, nil))
  AttachThreadInput(tid, pid, TRUE)
  defer: AttachThreadInput(tid, pid, FALSE)

  var p: POINT
  GetCaretPos(&p)
  result = (int p.x, int p.y)

proc getClientSize*(window: Window): wSize {.property.} =
  ## Retrieves the size of a given window's client area.
  var rect: RECT
  GetClientRect(HWND window, &rect)
  result = (int rect.right, int rect.bottom)

proc getProcess*(window: Window): Process {.property.} =
  ## Retrieves the process associated with a window.
  var pid: DWORD
  GetWindowThreadProcessId(HWND window, &pid)
  result = Process pid

proc getParent*(window: Window): Window {.property.} =
  ## Retrieves the parent of a given window.
  result = Window GetAncestor(HWND window, GA_PARENT)

proc getChildren*(window: Window): seq[Window] {.property.} =
  ## Retrieves the children of a given window.
  let pResult = addr result
  enumChildren(HWND window) do (hwnd: HWND) -> bool:
    pResult[].add(Window hwnd)

proc getActiveWindow*(): Window {.property, inline.} =
  ## Get the currently active window.
  result = Window GetForegroundWindow()

proc setTransparent*(window: Window, alpha: range[0..255]) {.property.} =
  ## Sets the transparency of a window.
  ## A value of 0 sets the window to be fully transparent.
  let hwnd = HWND window
  SetWindowLongPtr(hwnd, GWL_EXSTYLE,
    WS_EX_LAYERED or GetWindowLongPtr(hwnd, GWL_EXSTYLE))
  SetLayeredWindowAttributes(hwnd, 0, BYTE alpha, LWA_ALPHA)

proc getTransparent*(window: Window): int {.property.} =
  ## Gets the transparency of a window. Return -1 if failed.
  var alpha: byte
  if GetLayeredWindowAttributes(HWND window, nil, &alpha, nil) == 0: return -1
  result = int alpha

proc setOnTop*(window: Window, flag = true) {.property.} =
  ## Change a window's "Always On Top" attribute.
  if flag:
    SetWindowPos(HWND window, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE)
  else:
    SetWindowPos(HWND window, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE)

proc isExists*(window: Window): bool {.inline.} =
  ## Checks to see if a specified window exists.
  result = bool IsWindow(HWND window)

proc isVisible*(window: Window): bool {.inline.} =
  ## Checks to see if a specified window is currently visible.
  result = bool IsWindowVisible(HWND window)

proc isEnabled*(window: Window): bool {.inline.} =
  ## Checks to see if a specified window is currently enabled.
  result = bool IsWindowEnabled(HWND window)

proc isActive*(window: Window): bool {.inline.} =
  ## Checks to see if a specified window is currently active.
  result = GetForegroundWindow() == HWND window

proc isMinimized*(window: Window): bool {.inline.} =
  ## Checks to see if a specified window is currently minimized.
  result = bool IsIconic(HWND window)

proc isMaximized*(window: Window): bool {.inline.} =
  ## Checks to see if a specified window is currently maximized.
  result = bool IsZoomed(HWND window)

proc isFocused*(window: Window): bool =
  ## Checks to see if a specified window has the focus.
  let (tid, pid) = (GetCurrentThreadId(), GetWindowThreadProcessId(HWND window, nil))
  AttachThreadInput(tid, pid, TRUE)
  defer: AttachThreadInput(tid, pid, FALSE)

  result = (window.HWND == GetFocus())

proc activate*(window: Window) =
  ## Activates (gives focus to) a window.
  let hwnd = HWND window
  if IsIconic(hwnd): ShowWindow(hwnd, SW_RESTORE)
  SetForegroundWindow(hwnd)
  sleep(opt("windelay"))

proc close*(window: Window) =
  ## Closes a window.
  PostMessage(HWND window, WM_CLOSE, 0, 0)
  sleep(opt("windelay"))

proc kill*(window: Window, byProcess = true) =
  ## Forces a window to close by terminating the related process or thread.
  setPrivilege("SeDebugPrivilege")
  var pid: DWORD
  var tid = GetWindowThreadProcessId(HWND window, addr pid)

  if byProcess:
    let process = OpenProcess(PROCESS_TERMINATE, 0, pid)
    if process != 0:
      TerminateProcess(process, 0)
      CloseHandle(process)
  else:
    let thread = OpenThread(THREAD_TERMINATE, 0, tid)
    if thread != 0:
      TerminateThread(thread, 0)
      CloseHandle(thread)

proc show*(window: Window) {.inline.} =
  ## Shows window.
  ShowWindow(HWND window, SW_SHOW)

proc hide*(window: Window) {.inline.} =
  ## Hides window.
  ShowWindow(HWND window, SW_HIDE)

proc enable*(window: Window) {.inline.} =
  ## Enables the window.
  EnableWindow(HWND window, TRUE)

proc disable*(window: Window) {.inline.} =
  ## Disables the window.
  EnableWindow(HWND window, FALSE)

proc minimize*(window: Window) {.inline.} =
  ## Minimize the window.
  ShowWindow(HWND window, SW_MINIMIZE)

proc maximize*(window: Window) {.inline.} =
  ## Maximize the window.
  ShowWindow(HWND window, SW_MAXIMIZE)

proc restore*(window: Window) {.inline.} =
  ## Undoes a window minimization or maximization
  ShowWindow(HWND window, SW_RESTORE)

proc minimizeAll*() {.inline.} =
  ## Minimizes all windows. Equal to send("#m").
  PostMessage(FindWindow(("Shell_TrayWnd"), NULL), WM_COMMAND, 419, 0)
  sleep(opt("windelay"))

proc minimizeAllUndo*() {.inline.} =
  ## Undoes a previous minimizeAll(). Equal to send("#+m").
  PostMessage(FindWindow(("Shell_TrayWnd"), NULL), WM_COMMAND, 416, 0)
  sleep(opt("windelay"))

proc focus*(window: Window) =
  ## Focus a window.
  let (tid, pid) = (GetCurrentThreadId(), GetWindowThreadProcessId(HWND window, nil))
  AttachThreadInput(tid, pid, TRUE)
  defer: AttachThreadInput(tid, pid, FALSE)
  SetFocus(HWND window)
  sleep(opt("windelay"))

proc click*(window: Window, button = mbLeft, pos = wDefaultPoint, clicks = 1) =
  ## Sends a mouse click command to a given window. The default position is center.
  let
    (msgDown, msgUp, wParam) = getMouseMessage(button)
    size = window.getSize
    lParam = MAKELPARAM(
      if pos.x == wDefault: (size.width div 2) else: pos.x,
      if pos.y == wDefault: (size.height div 2) else: pos.y)

  for i in 1..clicks:
    PostMessage(HWND window, UINT msgDown, WPARAM wParam, lparam)
    sleep(opt("mouseclickdowndelay"))
    PostMessage(HWND window, UINT msgUp, WPARAM wParam, lparam)
    sleep(opt("mouseclickdelay"))

proc click*(window: Window, item: MenuItem) =
  ## Invokes a menu item of a window.
  if item.byPos:
    PostMessage(HWND window, WM_MENUCOMMAND, WPARAM item.index, LPARAM item.handle)
  else:
    PostMessage(HWND window, WM_COMMAND, WPARAM item.id, 0)
  sleep(opt("windelay"))

proc flash*(window: Window, flashes = 4, delay = 500, wait = true) =
  ## Flashes a window in the taskbar.
  let hwnd = HWND window
  if wait:
    for i in 1..(flashes - 2) * 2 + 1:
      FlashWindow(hwnd, true)
      sleep(delay)
  else:
    var fi = FLASHWINFO(
      cbSize: cint sizeof(FLASHWINFO),
      hwnd: hwnd,
      dwFlags: FLASHW_ALL or FLASHW_TIMERNOFG,
      uCount: UINT flashes,
      dwTimeout: DWORD delay)

    FlashWindowEx(&fi)
    sleep(opt("windelay"))

iterator windows*(): Window =
  ## Iterates over all the top-level windows.
  var list = newSeq[Window]()
  enumChildren do (hwnd: HWND) -> bool:
    list.add(Window hwnd)

  for window in list: yield window

iterator windows*(parent: Window): Window =
  ## Iterates over the children that belong to the specified parent window.
  var list = newSeq[Window]()
  enumChildren(HWND parent) do (hwnd: HWND) -> bool:
    list.add(Window hwnd)

  for window in list: yield window

iterator allWindows*(): Window =
  ## Iterates over all top-level windows and their descendants.
  var list = newSeq[Window]()
  enumDescendants do (hwnd: HWND) -> bool:
    list.add(Window hwnd)

  for window in list: yield window

iterator allWindows*(parent: Window): Window =
  ## Iterates over all the descendants that belong to the specified window.
  var list = newSeq[Window]()
  enumDescendants(HWND parent) do (hwnd: HWND) -> bool:
    list.add(Window hwnd)

  for window in list: yield window

proc walkMenu(list: var seq[MenuItem], hMenu: HMENU) =
  var menuInfo = MENUINFO(cbSize: cint sizeof(MENUINFO), fMask: MIM_STYLE)
  GetMenuInfo(hMenu, &menuInfo)
  var byPos = (menuInfo.dwStyle and MNS_NOTIFYBYPOS) != 0

  for i in 0..<GetMenuItemCount(hMenu):
    var buffer = T(65536)
    GetMenuString(hMenu, i, &buffer, cint buffer.len, MF_BYPOSITION)
    buffer.nullTerminate

    var item = MenuItem(
      handle: hMenu,
      index: i,
      id: GetMenuItemID(hMenu, i),
      text: $buffer,
      byPos: byPos)

    list.add item

    if item.id == -1:
      walkMenu(list, GetSubMenu(hMenu, i))

iterator menuItems*(window: Window): MenuItem =
  ## Iterates over all the menu items in the specified window.
  runnableExamples:
    import strutils

    proc example() =
      for window in windows():
        if window.className == "Notepad":
          for item in window.menuItems:
            if "Ctrl+O" in item.text:
              window.click(item)
          break

  var list = newSeq[MenuItem]()
  walkMenu(list, GetMenu(HWND window))
  for item in list: yield item

template enumerate*(body: untyped): untyped =
  ## Enumerates all the top-level windows.
  ## A *window* symbol is injected into the body.
  ## The template can return a seq[Window] that collects all *window* if the body can be evaluated as true.
  ## Use *enumerateBreak* template to break the enumeration.

  runnableExamples:
    proc example() =
      echo enumerate(window.title != "")

  runnableExamples:
    proc example() =
      enumerate:
        if window.className == "Notepad":
          echo window.title
          enumerateBreak

  block:
    template enumerateBreak {.used.} = raise newException(EnumerateBreakError, "")

    var
      window {.inject.}: Window
      result = newSeq[Window]()

    enumChildren do (hwnd: HWND) -> bool:
      window = Window hwnd
      try:
        when compiles(bool body):
          if body:
            result.add window
        else:
          body
      except EnumerateBreakError:
        return true

    discardable result

template enumerate*(parent: untyped, body: untyped): untyped =
  ## Enumerates the children that belong to the specified parent window.
  ## A *window* symbol is injected into the body.
  ## The template can return a seq[Window] that collects all *window* if the body can be evaluated as true.
  ## Use *enumerateBreak* template to break the enumeration.

  runnableExamples:
    proc example() =
      enumerate:
        if window.className == "Notepad":
          enumerate(window):
            echo window.className

          enumerateBreak

  var hParent = HWND parent # allow nested enumerate
  block:
    template enumerateBreak {.used.} = raise newException(EnumerateBreakError, "")

    var
      window {.inject.}: Window
      result = newSeq[Window]()

    enumChildren(hParent) do (hwnd: HWND) -> bool:
      window = Window hwnd
      try:
        when compiles(bool body):
          if body:
            result.add window
        else:
          body
      except EnumerateBreakError:
        return true

    discardable result

template enumerateAll*(body: untyped): untyped =
  ## Enumerates all top-level windows and their descendants.
  ## A *window* symbol is injected into the body.
  ## The template can return a seq[Window] that collects all *window* if the body can be evaluated as true.
  ## Use *enumerateBreak* template to break the enumeration.

  runnableExamples:
    proc example() =
      enumerateAll:
        if window.className == "Button" and window.title != "":
          echo window.repr

  block:
    template enumerateBreak {.used.} = raise newException(EnumerateBreakError, "")

    var
      window {.inject.}: Window
      result = newSeq[Window]()

    enumDescendants do (hwnd: HWND) -> bool:
      window = Window hwnd
      try:
        when compiles(bool body):
          if body:
            result.add window
        else:
          body
      except EnumerateBreakError:
        return true

    discardable result

template enumerateAll*(parent: untyped, body: untyped): untyped =
  ## Enumerates all the descendants that belong to the specified window.
  ## A *window* symbol is injected into the body.
  ## The template can return a seq[Window] that collects all *window* if the body can be evaluated as true.
  ## Use *enumerateBreak* template to break the enumeration.

  runnableExamples:
    proc example() =
      enumerate:
        if window.className == "Notepad":
          enumerateAll(window):
            echo window.className

          enumerateBreak

  var hParent = HWND parent # allow nested enumerate
  block:
    template enumerateBreak {.used.} = raise newException(EnumerateBreakError, "")

    var
      window {.inject.}: Window
      result = newSeq[Window]()

    enumDescendants(hParent) do (hwnd: HWND) -> bool:
      window = Window hwnd
      try:
        when compiles(bool body):
          if body:
            result.add window
        else:
          body
      except EnumerateBreakError:
        return true

    discardable result

template waitAny*(condition: untyped, timeout: untyped = 0): untyped =
  ## Repeatly examines all the top-level windows until condition becomes true for any window.
  ## A *window* symbol is injected into the condition.
  ## *timeout* specifies how long to wait (in seconds). Default (0) is to wait indefinitely.
  ## The template can return the *window* that match the condition.

  runnableExamples:
    proc example() =
      waitAny(window.className == "Notepad" and window.isActive)

  block:
    var
      timer = GetTickCount()
      window {.inject.}: Window
      found = false

    while not found:
      enumChildren do (hwnd: HWND) -> bool:
        window = Window hwnd
        if condition:
          found = true
          return true

      sleep(opt("winwaitdelay"))
      if timeout != 0 and (GetTickCount() -% timer) > timeout * 1000:
        window = Window 0
        break

    discardable window

template waitAll*(condition: untyped, timeout: untyped = 0): untyped =
  ## Repeatly examines all the top-level windows until condition becomes true for all windows.
  ## A *window* symbol is injected into the condition.
  ## *timeout* specifies how long to wait (in seconds). Default (0) is to wait indefinitely.

  runnableExamples:
    proc example() =
      waitAll(window.className != "Notepad")

  block:
    var
      timer = GetTickCount()
      window {.inject.}: Window
      flag: bool

    while not flag:
      flag = true
      enumChildren do (hwnd: HWND) -> bool:
        window = Window hwnd
        flag = flag and (bool condition)

      sleep(opt("winwaitdelay"))
      if timeout != 0 and (GetTickCount() -% timer) > timeout * 1000:
        break
