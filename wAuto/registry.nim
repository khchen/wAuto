#====================================================================
#
#               wAuto - Windows Automation Module
#                 (c) Copyright 2020-2022 Ward
#
#====================================================================

## This module contains support to manipulate Windows registry.
##
## A registry key must start with "HKEY_LOCAL_MACHINE" ("HKLM") or "HKEY_USERS" ("HKU") or
## "HKEY_CURRENT_USER" ("HKCU") or "HKEY_CLASSES_ROOT" ("HKCR") or "HKEY_CURRENT_CONFIG" ("HKCC").
##
## When running on 64-bit Windows if you want to read a value specific to the 64-bit environment
## you have to suffix the HK... with 64 i.e. HKLM64.
##
## To access the (Default) value use "" (an empty string) for the value name.
##
## When reading a REG_MULTI_SZ key the multiple entries are separated by '\\0' - use with .split('\\0')
## to get a seq of each entry.
##
## It is possible to access remote registries by using a keyname in the form *r"⧵⧵computername⧵keyname"*.
## To use this feature you must have the correct access rights.

{.deadCodeElim: on.}

import strutils, endians
import winim/lean, winim/inc/shellapi
import common

export common

type
  RegRight = enum
    rrRead
    rrWrite
    rrDelete

proc `==`*(a, b: RegData): bool =
  ## Checks for equality between two RegData variables.
  if a.kind != b.kind: return false
  if a.kind == rkRegError: return true
  if a.kind in {rkRegDword, rkRegDwordBigEndian}: return a.dword == b.dword
  if a.kind == rkRegQword: return a.qword == b.qword
  return a.data == b.data

proc regOpen(key: string, right: RegRight): HKEY =
  var
    key = key
    machine = ""

  if key.startsWith r"\\":
    key.removePrefix('\\')
    var parts = key.split('\\', maxsplit=1)
    machine = r"\\" & parts[0]
    key = if parts.len >= 2: parts[1] else: ""

  var
    phkey: HKEY
    phkeyNeedClose = false
    parts = key.split('\\', maxsplit=1)
    root = parts[0].toUpperAscii
    sam = REGSAM (if right == rrRead: KEY_READ else: KEY_WRITE) or
      (if root.endsWith "64": KEY_WOW64_64KEY else: 0)

  defer:
    if phkeyNeedClose: RegCloseKey(phkey)

  case root
  of "HKEY_LOCAL_MACHINE", "HKLM", "HKEY_LOCAL_MACHINE64", "HKLM64":
    phkey = HKEY_LOCAL_MACHINE

  of "HKEY_USERS", "HKU", "HKEY_USERS64", "HKU64":
    phkey = HKEY_USERS

  of "HKEY_CURRENT_USER", "HKCU", "HKEY_CURRENT_USER64", "HKCU64":
    phkey = HKEY_CURRENT_USER

  of "HKEY_CLASSES_ROOT", "HKCR", "HKEY_CLASSES_ROOT64", "HKCR64":
    phkey = HKEY_CLASSES_ROOT

  of "HKEY_CURRENT_CONFIG", "HKCC", "HKEY_CURRENT_CONFIG64", "HKCC64":
    phkey = HKEY_CURRENT_CONFIG

  else:
    return 0

  if machine != "":
    if RegConnectRegistry(machine, phkey, &phkey) == ERROR_SUCCESS:
      phkeyNeedClose = true

    else:
      return 0

  elif phkey == HKEY_CURRENT_USER:
    var hkey: HKEY
    if RegOpenCurrentUser(0, &hkey) == ERROR_SUCCESS:
      phkey = hkey
      phkeyNeedClose = true

  let subkey = if parts.len >= 2: parts[1] else: ""

  case right:
  of rrRead, rrDelete:
    if RegOpenKeyEx(phkey, subkey, 0, sam, &result) != ERROR_SUCCESS:
      return 0

  of rrWrite:
    if RegCreateKeyEx(phkey, subkey, 0, nil, 0, sam, nil, &result, nil) != ERROR_SUCCESS:
      return 0

proc regClose(hkey: HKEY) {.inline.} =
  RegCloseKey(hkey)

proc regRead*(key: string, value: string): RegData =
  ## Reads a value from the registry.

  runnableExamples:
    proc example() =
      echo regRead(r"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion", "ProgramFilesDir")

  block:
    let hkey = regOpen(key, rrRead)
    if hkey == 0: break
    defer: regClose(hkey)

    var size, kind: DWORD
    if RegQueryValueEx(hkey, value, nil, &kind, nil, &size) != ERROR_SUCCESS:
      break

    var buffer = newString(size)
    if RegQueryValueEx(hkey, value, nil, &kind, cast[LPBYTE](&buffer), &size) != ERROR_SUCCESS:
      break

    case kind
    of REG_DWORD:
      return RegData(kind: rkRegDword, dword: cast[ptr DWORD](&buffer)[])

    of REG_DWORD_BIG_ENDIAN:
      swapEndian32(&buffer, &buffer)
      return RegData(kind: rkRegDwordBigEndian, dword: cast[ptr DWORD](&buffer)[])

    of REG_QWORD:
      return RegData(kind: rkRegQword, qword: cast[ptr QWORD](&buffer)[])

    of REG_SZ, REG_EXPAND_SZ:
      return RegData(kind: RegKind kind, data: ($cast[TString](buffer)).nullTerminated)

    of REG_MULTI_SZ:
      return RegData(kind: rkRegMultiSz, data: ($cast[TString](buffer)).
        strip(leading=false, trailing=true, chars={'\0'}))

    else:
      return RegData(kind: RegKind kind, data: buffer)

  return RegData(kind: rkRegError)

proc regWrite*(key: string): bool {.discardable.} =
  ## Creates a key in the registry.

  runnableExamples:
    proc example() =
      regWrite(r"HKEY_CURRENT_USER\Software\wAuto")

  let hkey = regOpen(key, rrWrite)
  result = (hkey != 0)
  regClose(hkey)

proc regWrite*(key: string, name: string, value: RegData): bool {.discardable.} =
  ## Creates a value in the registry.

  runnableExamples:
    proc example() =
      regWrite(r"HKEY_CURRENT_USER\Software\wAuto", "Key1", RegData(kind: rkRegSz, data: "Test"))

  block:
    if value.kind == rkRegError: break

    let hkey = regOpen(key, rrWrite)
    if hkey == 0: break
    defer: regClose(hkey)

    var buffer: string
    case value.kind
    of rkRegDword:
      buffer = newString(4)
      cast[ptr DWORD](&buffer)[] = value.dword

    of rkRegDwordBigEndian:
      buffer = newString(4)
      cast[ptr DWORD](&buffer)[] = value.dword
      swapEndian32(&buffer, &buffer)

    of rkRegQword:
      buffer = newString(8)
      cast[ptr QWORD](&buffer)[] = value.qword

    of rkRegSz, rkRegExpandSz:
      buffer = string T(value.data)

    of rkRegMultiSz:
      for line in value.data.split('\0'):
        buffer.add string T(line)
      buffer.add '\0'.repeat(sizeof(TChar))

    else:
      buffer = value.data

    if RegSetValueEx(hkey, name, 0, DWORD value.kind,
        cast[LPBYTE](&buffer), DWORD buffer.len) != ERROR_SUCCESS:
      break

    return true

proc regWrite*(key: string, name: string, value: string): bool {.discardable.} =
  ## Creates a value of REG_SZ type in the registry.

  runnableExamples:
    proc example() =
      regWrite(r"HKEY_CURRENT_USER\Software\wAuto", "Key2", "Test")

  regWrite(key, name, RegData(kind: rkRegSz, data: value))

proc regWrite*(key: string, name: string, value: DWORD): bool {.discardable.} =
  ## Creates a value of REG_DWORD type in the registry.

  runnableExamples:
    proc example() =
      regWrite(r"HKEY_CURRENT_USER\Software\wAuto", "Key3", 12345)

  regWrite(key, name, RegData(kind: rkRegDword, dword: value))

proc regDelete*(key: string, name: string): bool {.discardable.} =
  ## Deletes a value from the registry.

  runnableExamples:
    proc example() =
      regDelete(r"HKEY_CURRENT_USER\Software\wAuto", "Key3")

  let hkey = regOpen(key, rrDelete)
  if hkey != 0:
    if RegDeleteValue(hkey, name) == ERROR_SUCCESS:
      result = true
    regClose(hkey)

proc regDelete*(key: string): bool {.discardable.} =
  ## Deletes the entire key from the registry.
  ## **Deleting from the registry is potentially dangerous--please exercise caution!**

  runnableExamples:
    proc example() =
      regDelete(r"HKEY_CURRENT_USER\Software\wAuto")

  let hkey = regOpen(key, rrDelete)
  if hkey != 0:
    if SHDeleteKey(hkey, "") == ERROR_SUCCESS :
      result = true
    regClose(hkey)

iterator regKeys*(key: string): string =
  ## Iterates over subkeys.
  let hkey = regOpen(key, rrRead)
  if hkey != 0:
    var
      i: DWORD = 0
      buffer = T(255)

    while true:
      if RegEnumKey(hkey, i, &buffer, 255) != ERROR_SUCCESS: break
      yield $buffer.nullTerminated
      i.inc

    regClose(hkey)

iterator regValues*(key: string): tuple[name: string, kind: RegKind] =
  ## Iterates over name and kind of values.
  let hkey = regOpen(key, rrRead)
  if hkey != 0:
    var
      buffer = T(32767)
      size, kind, i: DWORD = 0

    while true:
      size = DWORD buffer.len
      if RegEnumValue(hkey, i, &buffer, &size, nil, &kind, nil, nil) != ERROR_SUCCESS: break
      yield ($buffer.nullTerminated, RegKind kind)
      i.inc

    regClose(hkey)
