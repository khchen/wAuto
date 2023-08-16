#====================================================================
#
#               wAuto - Windows Automation Module
#               Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

## This module contains misc. functions for wAuto.

import os, strutils
import winim/lean, winim/inc/shellapi
import wNim/[wDataObject, wUtils]

proc isAdmin*(): bool =
  ## Checks if the current user has full administrator privileges.
  var sid: PSID
  defer:
    if sid != nil:
      FreeSid(sid)

  var authority = SID_IDENTIFIER_AUTHORITY(Value: SECURITY_NT_AUTHORITY)
  if AllocateAndInitializeSid(&authority, 2, SECURITY_BUILTIN_DOMAIN_RID,
      DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0, 0, &sid) == 0:
    return false

  var isMember: BOOL
  if CheckTokenMembership(0, sid, &isMember) != 0:
    return bool isMember

proc requireAdmin*(raiseError = true) =
  ## Elevate the current process during runtime by restarting it.
  ## Raise an error if the user cancel it if `raiseError` is true.
  if not isAdmin():
    var
      path = T(getAppFilename())
      parameters = T(quoteShellCommand(commandLineParams()))
      sei = SHELLEXECUTEINFO(
        cbSize: cint sizeof(SHELLEXECUTEINFO),
        lpVerb: T"runas",
        lpFile: &path,
        lpParameters: &parameters,
        fMask: SEE_MASK_NO_CONSOLE,
        nShow: SW_NORMAL)

    if ShellExecuteEx(&sei) == 0:
      if not raiseError: quit()

      var
        code = GetLastError()
        buffer: LPTSTR

      defer:
        LocalFree(cast[HLOCAL](buffer))

      # English only, because --app:gui use the ansi version messagebox for error message
      FormatMessage(FORMAT_MESSAGE_ALLOCATE_BUFFER or
        FORMAT_MESSAGE_FROM_SYSTEM or
        FORMAT_MESSAGE_IGNORE_INSERTS,
        nil, code, DWORD MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_US),
        cast[LPTSTR](&buffer), 0, nil)

      var error = newException(OSError, $buffer)
      error.errorCode = code
      raise error

    else:
      quit()

proc clipGet*(allowFiles = false): string =
  ## Retrieves text from the clipboard.
  ## When *allowFiles* is true and multiple selecting file/dir are stored in the
  ## clipboard, the filename/dirname are returned as texts separated by @LF.
  let data = wGetClipboard()
  if data.isText():
    result = data.getText()

  elif data.isFiles() and allowFiles:
    result = data.getFiles.join("\n")

proc clipPut*(text: string) =
  ## Writes text to the clipboard. An empty string "" will empty the clipboard.
  if text == "":
    wClearClipboard()
  else:
    wSetClipboard(DataObject(text))
    wFlushClipboard()
