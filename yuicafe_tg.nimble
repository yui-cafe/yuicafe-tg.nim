# Package

version       = "0.1.0"
author        = "Yui Cafe"
description   = "A Nim Telegram Bot API library and bot utility"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["yuicafe"]

requires "nim >= 2.2.12"
requires "db_connector >= 0.1.0"

switch("define", "ssl")
