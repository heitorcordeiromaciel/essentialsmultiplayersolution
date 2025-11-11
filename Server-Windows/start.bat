@echo off
setlocal
set DIR=%~dp0
"%DIR%ruby\bin.real\ruby.exe" "%DIR%server.rb"
pause

