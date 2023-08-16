#====================================================================
#
#               wAuto - Windows Automation Module
#               Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

## This module contains common definitions and procedures used in wAuto.

import tables, strutils
import winim/lean

type
  Window* = distinct HWND
    ## The type of a window.

  Process* = distinct DWORD
    ## The type of a process.

  MouseButton* = enum
    ## Mouse buttons.
    mbLeft, mbRight, mbMiddle, mbPrimary, mbSecondary

  CursorShape* = enum
    ## Mouse cursor shapes.
    csUnknow, csHand, csAppStarting, csArrow, csCross, csHelp, csIBeam, csIcon,
    csNo, csSize, csSizeAll, csSizeNesw, csSizeNs, csSizeNwse, csSizeWe, csUpArrow,
    csWait

  ProcessPriority* = enum
    ## Priority of process.
    ppError, ppIdle, ppBelowNormal, ppNormal, ppAboveNormal, ppHigh, ppRealtime

  ProcessOption* = enum
    ## Options to create child process.
    ##
    ## ================================  =============================================================
    ## Options                           Description
    ## ================================  =============================================================
    ## poStdin                           Provide a handle to the child's STDIN stream
    ## poStdout                          Provide a handle to the child's STDOUT stream
    ## poStderr                          Provide a handle to the child's STDERR stream
    ## poStderrMerged                    Provides the same handle for STDOUT and STDERR.
    ## poShow                            Shown window.
    ## poHide                            Hidden window.
    ## poMaximize                        Maximized window.
    ## poMinimize                        Minimized window.
    ## poCreateNewConsole                The child console process should be created with it's own window instead of using the parent's window.
    ## poLogonProfile                    Interactive logon with profile (for RunAs).
    ## poLogonNetwork                    Network credentials only (for RunAs).
    ## ================================  =============================================================
    poStdin, poStdout, poStderr, poStderrMerged
    poShow, poHide, poMaximize, poMinimize
    poCreateNewConsole, poLogonProfile, poLogonNetwork

  Hotkey* = tuple[modifiers: int, keyCode: int]
    ## A tuple represents a hotkey combination. *modifiers* is a bitwise combination
    ## of wModShift, wModCtrl, wModAlt, wModWin. *keyCode* is one of
    ## `virtual-key codes <https://khchen.github.io/wNim/wKeyCodes.html>`_.
    ## This tuple is compatible to hotkey in
    ## `wNim/wWindow <https://khchen.github.io/wNim/wWindow.html>`_.

  MenuItem* = object
    ## Represents a menu item.
    handle*: HMENU
    index*: int
    text*: string
    id*: int
    byPos*: bool

  RegKind* = enum
    ## The kinds of data type in registry.
    rkRegNone = (0, "REG_NONE")
    rkRegSz = (1, "REG_SZ")
    rkRegExpandSz = (2, "REG_EXPAND_SZ")
    rkRegBinary = (3, "REG_BINARY")
    rkRegDword = (4, "REG_DWORD")
    rkRegDwordBigEndian = (5, "REG_DWORD_BIG_ENDIAN")
    rkRegLink = (6, "REG_LINK")
    rkRegMultiSz = (7, "REG_MULTI_SZ")
    rkRegResourceList = (8, "REG_RESOURCE_LIST")
    rkRegFullResourceDescriptor = (9, "REG_FULL_RESOURCE_DESCRIPTOR")
    rkRegResourceRequirementsList = (10, "REG_RESOURCE_REQUIREMENTS_LIST")
    rkRegQword = (11, "REG_QWORD")
    rkRegError = (12, "REG_ERROR")

  RegData* = object
    ## The kind and data for the specified value in registry.
    case kind*: RegKind
    of rkRegError: nil
    of rkRegDword, rkRegDwordBigEndian: dword*: DWORD
    of rkRegQword: qword*: QWORD
    else: data*: string

  ProcessStats* = object
    readOperationCount*: ULONGLONG
    writeOperationCount*: ULONGLONG
    otherOperationCount*: ULONGLONG
    readTransferCount*: ULONGLONG
    writeTransferCount*: ULONGLONG
    otherTransferCount*: ULONGLONG
    pageFaultCount*: DWORD
    peakWorkingSetSize*: SIZE_T
    workingSetSize*: SIZE_T
    quotaPeakPagedPoolUsage*: SIZE_T
    quotaPagedPoolUsage*: SIZE_T
    quotaPeakNonPagedPoolUsage*: SIZE_T
    quotaNonPagedPoolUsage*: SIZE_T
    pagefileUsage*: SIZE_T
    peakPagefileUsage*: SIZE_T
    gdiObjects*: DWORD
    userObjects*: DWORD

const
  InvalidProcess* = Process -1

  InvalidWindow* = Window 0

  ppLow* = ppIdle


var table {.threadvar.}: Table[string, int]

proc opt*(key: string): int =
  ## Gets the current setting value.
  let key = key.toLowerAscii
  table.withValue(key, value) do:
    result = value[]

  do:
    result = case key
    of "winwaitdelay": 250
    of "windelay": 10
    of "mouseclickdelay": 10
    of "mouseclickdowndelay": 10
    of "mouseclickdragdelay": 250
    of "sendkeydowndelay": 5
    of "sendkeydelay": 5
    else: 0

proc opt*(key: string, value: int): int {.discardable.} =
  ## Change the global setting for window, mouse, and keyboard module.
  ## All options are case-insensitive and in milliseconds.
  ##
  ## ================================  =============================================================
  ## Options                           Description
  ## ================================  =============================================================
  ## MouseClickDelay                   Alters the length of the brief pause in between mouse clicks.
  ## MouseClickDownDelay               Alters the length a click is held down before release.
  ## MouseClickDragDelay               Alters the length of the brief pause at the start and end of a mouse drag operation.
  ## SendKeyDelay                      Alters the length of the brief pause in between sent keystrokes.
  ## SendKeyDownDelay                  Alters the length of time a key is held down before being released during a keystroke.
  ## WinDelay                          Alters how long to pause after a successful window-related operation.
  ## WinWaitDelay                      Alters how long to pause during window wait operation.
  ## ================================  =============================================================
  let key = key.toLowerAscii

  table.withValue(key, value) do:
    result = value[]
  do:
    result = opt(key)

  table[key] = value
