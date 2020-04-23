#====================================================================
#
#               wAuto - Windows Automation Module
#                   (c) Copyright 2020 Ward
#
#====================================================================

##  wAuto is the Windows automation module for nim based on
## `winim <https://github.com/khchen/winim>`_ and
## `wNim <https://github.com/khchen/wNim>`_.
## It contains support to simulate keystrokes and mouse movements, manipulate windows,
## processes, and registry. Some functions are inspired by
## `AutoIt Script <https://www.autoitscript.com>`_.
##
## The getters and setters in wAuto, just like in wNim, can be simplized.
## For example:
##
## .. code-block:: Nim
##   assert getPosition(getActiveWindow()) == activeWindow().position
##
## wAuto contains following submodules.
##
##  - `common <common.html>`_
##  - `window <window.html>`_
##  - `mouse <mouse.html>`_
##  - `keyboard <keyboard.html>`_
##  - `process <process.html>`_
##  - `registry <registry.html>`_
##
## Modules can be imoprted all in one, or be imported one by one.
## For example:
##
## .. code-block:: Nim
##   import wAuto # import all
##   import wAuto/window # import window module only

{.deadCodeElim: on.}

import wAuto/[common, window, mouse, keyboard, process, registry]
export common, window, mouse, keyboard, process, registry
