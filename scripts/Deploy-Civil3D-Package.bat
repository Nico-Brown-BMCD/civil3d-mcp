@echo off
REM Double-click entry point for installing the Civil 3D MCP plugin and server.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Deploy-Civil3D-Package.ps1" %*
if errorlevel 1 echo Installation failed. Review the PowerShell output above.
echo.
pause