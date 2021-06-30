#====================================================================
#
#               wAuto - Windows Automation Module
#                   (c) Copyright 2020 Ward
#
#====================================================================

## This module contains support to manipulate process.

{.deadCodeElim: on.}

import strutils
import winim/lean, winim/inc/[tlhelp32, psapi]
import wNim/wMacros
import common, window, private/utils

export common, lean.STILL_ACTIVE

proc getName*(process: Process): string

proc `$`*(x: Process): string {.borrow.}
  ## The stringify operator for a process.

proc `==`*(x, y: Process): bool {.borrow.}
  ## Checks for equality between two process.

proc repr*(x: Process): string =
  ## Returns string representation of a process.
  result = "Process(name: "
  result.add x.getName.escape
  result.add ", pid: "
  result.add $x
  result.add ")"

iterator processes*(): tuple[name: string, process: Process] =
  ## Iterates over all processes.
  let handle = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
  if handle != INVALID_HANDLE_VALUE:
    defer: CloseHandle(handle)

    var entry = PROCESSENTRY32(dwSize: cint sizeof(PROCESSENTRY32))
    if Process32First(handle, &entry) != FALSE:
      while true:
        yield ((%$(entry.szExeFile)).nullTerminated, Process entry.th32ProcessID)
        if Process32Next(handle, &entry) == FALSE:
          break

iterator processes*(name: string): Process =
  ## Iterates over process of specified name.

  runnableExamples:
    proc example() =
      for process in processes("notepad.exe"):
        waitClose(process)

  var name = name.toLowerAscii
  for tup in processes():
    if tup.name.toLowerAscii == name:
      yield tup.process

proc getHandle*(process: Process): DWORD {.property, inline.} =
  ## Gets the Win32 process ID (PID) from the specified process.
  result = DWORD process

proc isExists*(process: Process): bool =
  ## Checks to see if a specified process exists.
  for tup in processes():
    if process == tup.process:
      return true

proc isProcessExists*(name: string): bool =
  ## Checks to see if a specified process exists.
  for process in processes(name):
    return true

proc kill*(process: Process): bool {.discardable.} =
  ## Terminates a process.
  setPrivilege("SeDebugPrivilege")
  let handle = OpenProcess(PROCESS_TERMINATE, 0, DWORD process)
  if handle != 0:
    defer: CloseHandle(handle)
    if TerminateProcess(handle, 0) != 0:
      return true

proc killProcess*(name: string) =
  ## Terminates all processes with the same name.
  var name = name.toLowerAscii
  for process in processes(name):
    kill(process)

proc waitProcess*(name: string, timeout = 0): Process {.discardable.} =
  ## Pauses until a given process exists.
  ## *timeout* specifies how long to wait (in seconds). Default (0) is to wait indefinitely.
  ## Returns the process or InvalidProcess if timeout.
  var timer = GetTickCount()
  while timeout == 0 or (GetTickCount() -% timer) < timeout * 1000:
    for process in processes(name):
      return process

    Sleep(250)

  result = InvalidProcess

proc waitClose*(process: Process, timeout = 0): DWORD {.discardable.} =
  ## Pauses until a given process does not exist.
  ## *timeout* specifies how long to wait (in seconds). Default (0) is to wait indefinitely.
  ## Returns exit code of the process or STILL_ACTIVE(259) if timeout.
  setPrivilege("SeDebugPrivilege")
  var
    timeout = if timeout == 0: INFINITE else: cint timeout * 1000
    handle = OpenProcess(PROCESS_QUERY_INFORMATION or SYNCHRONIZE, 0, DWORD process)

  if handle != 0:
    WaitForSingleObject(handle, timeout)
    GetExitCodeProcess(handle, &result)
    CloseHandle(handle)

proc setPriority*(process: Process, priority: ProcessPriority): bool {.property, discardable.} =
  ## Changes the priority of a process.
  setPrivilege("SeDebugPrivilege")
  let handle = OpenProcess(PROCESS_SET_INFORMATION, 0, DWORD process)
  if handle != 0:
    defer: CloseHandle(handle)
    let priorityClass = case priority
    of ppIdle: IDLE_PRIORITY_CLASS
    of ppBelowNormal: BELOW_NORMAL_PRIORITY_CLASS
    of ppNormal: NORMAL_PRIORITY_CLASS
    of ppAboveNormal: ABOVE_NORMAL_PRIORITY_CLASS
    of ppHigh: HIGH_PRIORITY_CLASS
    of ppRealtime: REALTIME_PRIORITY_CLASS
    else: 0

    if priorityClass != 0:
      result = SetPriorityClass(handle, DWORD priorityClass) != 0

proc getPriority*(process: Process): ProcessPriority {.property.} =
  ## Gets the priority of a process.
  setPrivilege("SeDebugPrivilege")
  result = ppError
  let handle = OpenProcess(PROCESS_QUERY_INFORMATION, 0, DWORD process)
  if handle != 0:
    defer: CloseHandle(handle)
    result = case GetPriorityClass(handle)
    of IDLE_PRIORITY_CLASS: ppIdle
    of BELOW_NORMAL_PRIORITY_CLASS: ppBelowNormal
    of NORMAL_PRIORITY_CLASS: ppNormal
    of ABOVE_NORMAL_PRIORITY_CLASS: ppAboveNormal
    of HIGH_PRIORITY_CLASS: ppHigh
    of REALTIME_PRIORITY_CLASS: ppRealtime
    else: ppError

proc getPath*(process: Process): string {.property.} =
  ## Gets the path of a process.
  setPrivilege("SeDebugPrivilege")
  let handle = OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, 0, DWORD process)
  if handle != 0:
    defer: CloseHandle(handle)
    var buffer = T(MAX_PATH)
    buffer.setLen(GetModuleFileNameEx(handle, 0, &buffer, MAX_PATH))
    result = $buffer

proc getName*(process: Process): string {.property.} =
  ## Gets the name of a process.
  setPrivilege("SeDebugPrivilege")
  let handle = OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, 0, DWORD process)
  if handle != 0:
    defer: CloseHandle(handle)
    var buffer = T(MAX_PATH)
    buffer.setLen(GetModuleBaseName(handle, 0, &buffer, MAX_PATH))
    result = $buffer

  else:
    for tup in processes():
      if process == tup.process:
        return tup.name

proc isWow64*(process: Process): bool =
  ## Determines whether the specified process is running under WOW64 or an Intel64 of x64 processor.
  let handle = OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, 0, DWORD process)
  if handle != 0:
    defer: CloseHandle(handle)
    var wow64: BOOL
    if IsWow64Process(handle, addr wow64) != 0:
      result = bool wow64

iterator windows*(process: Process): Window =
  ## Iterates over all top-level windows that created by the specified process.
  for window in windows():
    if window.getProcess == process:
      yield window

iterator allWindows*(process: Process): Window =
  ## Iterates over all windows that created by the specified process.
  for window in allWindows():
    if window.getProcess == process:
      yield window
