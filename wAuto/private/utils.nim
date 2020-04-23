#====================================================================
#
#               wAuto - Windows Automation Module
#                   (c) Copyright 2020 Ward
#
#====================================================================

{.deadCodeElim: on.}

import winim/lean

type
  RemotePointer* = object
    handle*: HANDLE
    address*: pointer
    size*: Natural

template sleep*(n: int) = Sleep(DWORD n)

proc setPrivilege*(privilege = "SeDebugPrivilege") =
  var
    token: HANDLE
    tp = TOKEN_PRIVILEGES(
      PrivilegeCount: 1,
      Privileges: [LUID_AND_ATTRIBUTES(Attributes: SE_PRIVILEGE_ENABLED)])

  if OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES, addr token):
    defer:
      CloseHandle(token)

    if LookupPrivilegeValue(nil, privilege, addr tp.Privileges[0].Luid):
      AdjustTokenPrivileges(token, false, addr tp, cint sizeof(TOKEN_PRIVILEGES), nil, nil)

proc remoteAlloc*(hwnd: HWND, size: Natural): RemotePointer =
  block:
    var pid: DWORD
    GetWindowThreadProcessId(hwnd, &pid)
    if pid == 0: break

    result.handle = OpenProcess(PROCESS_VM_OPERATION or PROCESS_VM_READ or PROCESS_VM_WRITE, FALSE, pid)
    if result.handle == 0: break

    result.address = VirtualAllocEx(result.handle, nil, SIZE_T size, MEM_RESERVE or MEM_COMMIT, PAGE_READWRITE)
    if result.address.isNil: break

    result.size = size

proc remoteDealloc*(rp: var RemotePointer) =
  VirtualFreeEx(rp.handle, rp.address, 0, MEM_RELEASE)
  CloseHandle(rp.handle)
  rp.size = 0
  rp.handle = 0
  rp.address = nil

proc remoteRead*(rp: RemotePointer): string =
  var bytesRead: SIZE_T
  result.setLen(rp.size)
  ReadProcessMemory(rp.handle, rp.address, addr result[0], SIZE_T rp.size, addr bytesRead)
  result.setLen(bytesRead)

proc ok*(rp: RemotePointer): bool {.inline.} =
  not rp.address.isNil
