#====================================================================
#
#               wAuto - Windows Automation Module
#               Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

## This module contains support to manipulate process.

import strutils, tables
import winim/lean, winim/inc/[tlhelp32, psapi, shellapi]
import wNim/wMacros
import common, window, private/utils

export common, lean.STILL_ACTIVE

proc NtSuspendProcess(hProcess: HANDLE): LONG {.stdcall, dynlib: "ntdll", importc.}
proc NtResumeProcess(hProcess: HANDLE): LONG {.stdcall, dynlib: "ntdll", importc.}

type
  Pipes = object
    stdinRead: HANDLE
    stdinWrite: HANDLE
    stdoutRead: HANDLE
    stdoutWrite: HANDLE
    stderrRead: HANDLE
    stderrWrite: HANDLE

var gPipe {.threadvar.}: Table[Process, Pipes]

proc `[]`[T](x: T, U: typedesc): U =
  # syntax sugar for cast
  cast[U](x)

proc `{}`[T](x: T, U: typedesc): U =
  # syntax sugar for zero extends cast
  when sizeof(x) == 1: x[uint8][U]
  elif sizeof(x) == 2: x[uint16][U]
  elif sizeof(x) == 4: x[uint32][U]
  elif sizeof(x) == 8: x[uint64][U]
  else: {.fatal.}

template `{}`[T](p: T, x: SomeInteger): T =
  # syntax sugar for pointer (or any other type) arithmetics
  cast[T]((cast[int](p) +% x{int}))

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

proc getCurrentProcess*(): Process {.property, inline.} =
  return Process GetCurrentProcessId()

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

  proc isExists1(process: Process): bool =
    # Fast, but may return true on some non-exists pid
    if process == Process 0: # System Idle Process
      return true

    let handle = OpenProcess(PROCESS_QUERY_INFORMATION, 0, DWORD process)
    if handle != 0:
      defer:
        CloseHandle(handle)

      var exitCode: DWORD
      if GetExitCodeProcess(handle, &exitCode) != 0:
        return exitCode == STILL_ACTIVE

      else:
        return true

    else:
      return GetLastError() != ERROR_INVALID_PARAMETER

  proc isExists2(process: Process): bool =
    # Slow, but exactly
    if process == Process 0: # System Idle Process
      return true

    var
      processes = newSeq[DWORD](4096)
      needed: DWORD = 0

    while true:
      let size = cint(sizeof(DWORD) * processes.len)
      if EnumProcesses(addr processes[0], size, &needed) == 0:
        break

      if DWORD size == needed:
        processes.setLen(processes.len * 2)

      else:
        break

    for i in 0 ..< (needed div sizeof(DWORD)):
      if process == Process processes[i]:
        return true

  return isExists1(process) and isExists2(process)

proc isProcessExists*(name: string): bool =
  ## Checks to see if a specified process exists.
  for process in processes(name):
    return true

proc isWow64*(process: Process): bool =
  ## Determines whether the specified process is running under WOW64 or an Intel64 of x64 processor.
  let handle = OpenProcess(PROCESS_QUERY_INFORMATION, 0, DWORD process)
  if handle != 0:
    defer: CloseHandle(handle)
    var wow64: BOOL
    if IsWow64Process(handle, &wow64) != 0:
      result = bool wow64

proc getProcess*(name: string): Process {.property.} =
  ## Returns the process of specified name or InvalidProcess if not found.
  for process in processes(name):
    return process

  return InvalidProcess

proc getStats*(process: Process): ProcessStats {.property.} =
  ## Returns Memory and IO infos of a running process.
  setPrivilege("SeDebugPrivilege")
  let handle = OpenProcess(PROCESS_QUERY_INFORMATION, 0, DWORD process)
  if handle != 0:
    defer: CloseHandle(handle)
    var
      ioCounters: IO_COUNTERS
      memCounters: PROCESS_MEMORY_COUNTERS

    if GetProcessIoCounters(handle, &ioCounters) != 0:
      result.readOperationCount = ioCounters.ReadOperationCount
      result.writeOperationCount = ioCounters.WriteOperationCount
      result.otherOperationCount = ioCounters.OtherOperationCount
      result.readTransferCount = ioCounters.ReadTransferCount
      result.writeTransferCount = ioCounters.WriteTransferCount
      result.otherTransferCount = ioCounters.OtherTransferCount

    if GetProcessMemoryInfo(handle, &memCounters, cint sizeof(memCounters)) != 0:
      result.pageFaultCount = memCounters.PageFaultCount
      result.peakWorkingSetSize = memCounters.PeakWorkingSetSize
      result.workingSetSize = memCounters.WorkingSetSize
      result.quotaPeakPagedPoolUsage = memCounters.QuotaPeakPagedPoolUsage
      result.quotaPagedPoolUsage = memCounters.QuotaPagedPoolUsage
      result.quotaPeakNonPagedPoolUsage = memCounters.QuotaPeakNonPagedPoolUsage
      result.quotaNonPagedPoolUsage = memCounters.QuotaNonPagedPoolUsage
      result.pagefileUsage = memCounters.PagefileUsage
      result.peakPagefileUsage = memCounters.PeakPagefileUsage

    result.gdiObjects = GetGuiResources(handle, GR_GDIOBJECTS)
    result.userObjects = GetGuiResources(handle, GR_USEROBJECTS)

proc kill*(process: Process): bool {.discardable.} =
  ## Terminates a process.
  setPrivilege("SeDebugPrivilege")
  let handle = OpenProcess(PROCESS_TERMINATE, 0, DWORD process)
  if handle != 0:
    defer: CloseHandle(handle)
    if TerminateProcess(handle, 0) != 0:
      return true

proc suspend*(process: Process): bool {.discardable.} =
  ## Suspend a process.
  setPrivilege("SeDebugPrivilege")
  # PROCESS_SUSPEND_RESUME may not work
  let handle = OpenProcess(PROCESS_ALL_ACCESS, 0, DWORD process)
  if handle != 0:
    defer: CloseHandle(handle)
    return NtSuspendProcess(handle) == 0

proc resume*(process: Process): bool {.discardable.} =
  ## Resume a process.
  setPrivilege("SeDebugPrivilege")
  let handle = OpenProcess(PROCESS_ALL_ACCESS, 0, DWORD process)
  if handle != 0:
    defer: CloseHandle(handle)
    return NtResumeProcess(handle) == 0

proc killProcess*(name: string) =
  ## Terminates all processes with the same name.
  var name = name.toLowerAscii
  for process in processes(name):
    kill(process)

proc waitProcess*(name: string, timeout = 0.0): Process {.discardable.} =
  ## Pauses until a given process exists.
  ## *timeout* specifies how long to wait (in seconds). Default (0.0) is to wait indefinitely.
  ## Returns the process or InvalidProcess if timeout reached.
  var timer = GetTickCount()
  while timeout == 0.0 or float(GetTickCount() -% timer) < timeout * 1000:
    for process in processes(name):
      return process

    Sleep(250)

  result = InvalidProcess

proc waitClose*(process: Process, timeout = 0.0): DWORD {.discardable.} =
  ## Pauses until a given process does not exist.
  ## *timeout* specifies how long to wait (in seconds). Default (0.0) is to wait indefinitely.
  ## Returns exit code of the process or STILL_ACTIVE(259) if timeout reached.
  setPrivilege("SeDebugPrivilege")
  var
    timeout = if timeout == 0.0: INFINITE else: cint timeout * 1000
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
    # use QueryFullProcessImageName first
    # https://stackoverflow.com/questions/20792076/
    var
      buffer = T(MAX_PATH)
      size: DWORD = MAX_PATH

    if QueryFullProcessImageName(handle, 0, &buffer, &size) != 0:
      buffer.setLen(size)
      result = $buffer
    else:
      buffer.setLen(GetModuleFileNameEx(handle, 0, &buffer, MAX_PATH))
      result = $buffer

proc getCommandLine*(process: Process): string {.property.} =
  ## Gets the command line of a process.

  proc getCommandLine(handle: HANDLE): string =
    var
      pbi: PROCESS_BASIC_INFORMATION
      prupp: PRTL_USER_PROCESS_PARAMETERS
      commandLine: UNICODE_STRING

    if NtQueryInformationProcess(handle, 0, &pbi, sizeof(pbi), nil) != S_OK: return

    if ReadProcessMemory(handle,
        pbi.PebBaseAddress{offsetof(PEB, ProcessParameters)},
        &prupp, sizeof(prupp), nil) == 0: return

    if ReadProcessMemory(handle,
        prupp{offsetof(RTL_USER_PROCESS_PARAMETERS, CommandLine)},
        &commandLine, sizeof(commandLine), nil) == 0: return

    var buffer = newString(commandLine.Length + 2)
    if ReadProcessMemory(handle,
      commandLine.Buffer,
      &buffer, SIZE_T commandLine.Length, nil) == 0: return

    result = $cast[LPWSTR](&buffer)

  when winimCpu32:
    type
      PROCESS_BASIC_INFORMATION64 {.pure.} = object
        Reserved1: int64
        PebBaseAddress: int64
        Reserved2: array[4, int64]

    proc NtWow64QueryInformationProcess64(ProcessHandle: HANDLE,
      ProcessInformationClass: PROCESSINFOCLASS,
      ProcessInformation: PVOID,
      ProcessInformationLength: ULONG,
      ReturnLength: PULONG): NTSTATUS
      {.stdcall, dynlib: "ntdll", importc.}

    proc NtWow64ReadVirtualMemory64(
      hProcess: HANDLE,
      lpBaseAddress: int64,
      lpBuffer: LPVOID,
      nSize: ULONG64,
      lpNumberOfBytesRead: PULONG64): NTSTATUS
      {.stdcall, dynlib: "ntdll", importc.}

    proc getCommandLineWow64(handle: HANDLE): string =
      var
        pbi: PROCESS_BASIC_INFORMATION64
        prupp: int64
        commandLine: UNICODE_STRING64

      if NtWow64QueryInformationProcess64(handle, 0, &pbi, sizeof(pbi), nil) != S_OK: return

      if NtWow64ReadVirtualMemory64(handle,
        pbi.PebBaseAddress +% 0x20,
        &prupp, sizeof(prupp), nil) != 0: return

      if NtWow64ReadVirtualMemory64(handle,
        prupp +% 0x70,
        &commandLine, sizeof(commandLine), nil) != 0: return

      var buffer = newString(commandLine.Length)
      if NtWow64ReadVirtualMemory64(handle,
        commandLine.Buffer,
        &buffer, SIZE_T commandLine.Length, nil) != 0: return

      result = $cast[LPWSTR](&buffer)

  setPrivilege("SeDebugPrivilege")
  let handle = OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, 0, DWORD process)
  if handle != 0:
    defer: CloseHandle(handle)

    when winimCpu32:
      if not process.isWow64 and currentProcess().isWow64:
        return getCommandLineWow64(handle)
      else:
        return getCommandLine(handle)
    else:
      return getCommandLine(handle)

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

proc close(pipes: var Pipes, options: set[ProcessOption]) =
  if poStdin in options:
    CloseHandle(pipes.stdinRead); pipes.stdinRead = 0
    CloseHandle(pipes.stdinWrite); pipes.stdinWrite = 0

  if poStdout in options:
    CloseHandle(pipes.stdoutRead); pipes.stdoutRead = 0
    CloseHandle(pipes.stdoutWrite); pipes.stdoutWrite = 0

  if poStderr in options:
    CloseHandle(pipes.stderrRead); pipes.stderrRead = 0
    CloseHandle(pipes.stderrWrite); pipes.stderrWrite = 0

proc stdioClose*(process: Process, options: set[ProcessOption] = {}) =
  ## Closes resources associated with a process previously run with STDIO redirection.
  if process in gPipe:
    var pipes = gPipe[process]
    var options = options
    if options == {}: options = {poStdin, poStdout, poStderr}
    if poStderrMerged in options: options.incl {poStdout, poStderr}

    pipes.close(options)

    if pipes == default(Pipes):
      gPipe.del(process)
    else:
      gPipe[process] = pipes

proc stdinWrite*(process: Process, data: string): int {.discardable} =
  ## Writes to the STDIN stream of a previously run child process.
  if process in gPipe:
    let pipes = gPipe[process]
    var written: DWORD
    WriteFile(pipes.stdinWrite, &data, data.len, &written, nil)
    return int written

proc stdread(handle: HANDLE, peek = false): string =
  var read, total: DWORD
  if PeekNamedPipe(handle, nil, 0, nil, &total, nil) != 0:
    if total != 0:
      result = newString(total)

      if peek:
        PeekNamedPipe(handle, &result, cint result.len, &read, nil, nil)
        result.setLen(read)

      else:
        ReadFile(handle, &result, cint result.len, &read, nil)
        result.setLen(read)

proc stdoutRead*(process: Process, peek = false): string =
  ## Reads from the STDOUT stream of a previously run child process.
  if process in gPipe:
    let pipes = gPipe[process]
    result = stdread(pipes.stdoutRead, peek)

proc stderrRead*(process: Process, peek = false): string =
  ## Reads from the STDERR stream of a previously run child process.
  if process in gPipe:
    let pipes = gPipe[process]
    result = stdread(pipes.stderrRead, peek)

proc run(path: string, username = "", password = "", domain = "",
    workingDir = "", options: set[ProcessOption] = {}): Process =

  var
    si = STARTUPINFO(cb: cint sizeof(STARTUPINFO),
      dwFlags: STARTF_USESHOWWINDOW,
      wShowWindow: SW_SHOWDEFAULT,
      hStdInput: GetStdHandle(STD_INPUT_HANDLE),
      hStdOutput: GetStdHandle(STD_OUTPUT_HANDLE),
      hStdError: GetStdHandle(STD_ERROR_HANDLE))

    pi: PROCESS_INFORMATION

    sa = SECURITY_ATTRIBUTES(nLength: cint sizeof(SECURITY_ATTRIBUTES),
      bInheritHandle: true)

    creationFlags: DWORD = NORMAL_PRIORITY_CLASS or CREATE_UNICODE_ENVIRONMENT
    logonFlags: DWORD = 0

    pipes: Pipes
    inheritHandle = false

  defer:
    if result == InvalidProcess:
      pipes.close({poStdin, poStdout, poStderr})

    else:
      CloseHandle(pi.hProcess)
      CloseHandle(pi.hThread)
      if inheritHandle:
        gPipe[result] = pipes

  result = InvalidProcess

  if poMinimize in options: si.wShowWindow = SW_MINIMIZE
  if poMaximize in options: si.wShowWindow = SW_MAXIMIZE
  if poHide in options: si.wShowWindow = SW_HIDE
  if poShow in options: si.wShowWindow = SW_SHOW

  if poLogonNetwork in options: logonFlags = LOGON_NETCREDENTIALS_ONLY
  if poLogonProfile in options: logonFlags = LOGON_WITH_PROFILE

  if poCreateNewConsole in options:
    creationFlags = creationFlags or CREATE_NEW_CONSOLE

  if poStdin in options:
    if CreatePipe(&pipes.stdinRead, &pipes.stdinWrite, &sa, 0) == 0:
      return InvalidProcess

    SetHandleInformation(pipes.stdinWrite, HANDLE_FLAG_INHERIT, 0)
    si.hStdInput = pipes.stdinRead
    inheritHandle = true
    si.dwFlags = si.dwFlags or STARTF_USESTDHANDLES

  if poStdout in options or poStderrMerged in options:
    if CreatePipe(&pipes.stdoutRead, &pipes.stdoutWrite, &sa, 0) == 0:
      return InvalidProcess

    SetHandleInformation(pipes.stdoutRead, HANDLE_FLAG_INHERIT, 0)
    si.hStdOutput = pipes.stdoutWrite
    if poStderrMerged in options: si.hStdError = pipes.stdoutWrite
    inheritHandle = true
    si.dwFlags = si.dwFlags or STARTF_USESTDHANDLES

  if poStderr in options and poStderrMerged notin options:
    if CreatePipe(&pipes.stderrRead, &pipes.stderrWrite, &sa, 0) == 0:
      return InvalidProcess

    SetHandleInformation(pipes.stderrRead, HANDLE_FLAG_INHERIT, 0)
    si.hStdError = pipes.stderrWrite
    inheritHandle = true
    si.dwFlags = si.dwFlags or STARTF_USESTDHANDLES

  if username == "" and password == "":
    var dir: LPTSTR
    if workingDir.len != 0:
      dir = T(workingDir)

    if CreateProcess(nil, path, nil, nil, inheritHandle, creationFlags, nil,
        dir, &si, &pi) != 0:
      result = Process pi.dwProcessId

  else:
    var dir: LPCWSTR
    if workingDir.len != 0:
      dir = +$workingDir

    if CreateProcessWithLogonW(username, domain, password, logonFlags,
        nil, path, creationFlags, nil, dir, &si, &pi) != 0:
      result = Process pi.dwProcessId

proc run*(path: string, workingDir = "", options: set[ProcessOption] = {}): Process
  {.discardable.} =
  ## Runs an external program.
  ## Returns the process or InvalidProcess if error occured.
  run(path, username="", password="", domain="", workingDir=workingDir, options=options)

proc runAs*(path: string, username: string, password: string, domain = "",
    workingDir = "", options: set[ProcessOption] = {}): Process {.discardable.} =
  ## Runs an external program under the context of a different user.
  ## Returns the process or InvalidProcess if error occured.
  run(path, username, password, domain, workingDir, options)

proc runWait*(path: string, workingDir = "", options: set[ProcessOption] = {},
  timeout = 0.0): DWORD {.discardable.} =
  ## Runs an external program and pauses execution until the program finishes.
  ## Returns exit code of the process or STILL_ACTIVE(259) if timeout reached.
  let pid = run(path, workingDir, options)
  result = waitClose(pid, timeout)
  stdioClose(pid)

proc runAsWait*(path: string, username: string, password: string, domain = "",
    workingDir = "", options: set[ProcessOption] = {}, timeout = 0.0): DWORD
    {.discardable.} =
  ## Runs an external program under the context of a different user and pauses
  ## execution until the program finishes.
  ## Returns exit code of the process or STILL_ACTIVE(259) if timeout reached.
  let pid = runAs(path, username, password, domain, workingDir, options)
  result = waitClose(pid, timeout)
  stdioClose(pid)

proc shellExecute*(file: string, parameters = "", workingdir = "", verb = "",
  show: ProcessOption = poShow): Process {.discardable.} =
  ## Runs an external program using the ShellExecute API.
  var info = SHELLEXECUTEINFO(cbSize: cint sizeof(SHELLEXECUTEINFO))
  info.lpFile = file
  info.lpParameters = parameters
  info.lpDirectory = workingdir
  info.lpVerb = verb
  info.fMask = SEE_MASK_NOCLOSEPROCESS or SEE_MASK_FLAG_NO_UI
  info.nShow = case show
    of poHide: SW_HIDE
    of poMaximize: SW_MAXIMIZE
    of poMinimize: SW_MINIMIZE
    else: SW_SHOW

  if ShellExecuteEx(&info):
    defer: CloseHandle(info.hProcess)
    var pid = GetProcessId(info.hProcess)
    if pid != 0:
      return Process pid

  return InvalidProcess

proc shellExecuteWait*(file: string, parameters = "", workingdir = "", verb = "",
  show: ProcessOption = poShow, timeout = 0.0): DWORD {.discardable.} =
  ## Runs an external program using the ShellExecute API and
  ## pauses script execution until it finishes.
  ## Returns exit code of the process or STILL_ACTIVE(259) if timeout reached.
  let pid = shellExecute(file, parameters, workingdir, verb, show)
  result = waitClose(pid, timeout)

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
