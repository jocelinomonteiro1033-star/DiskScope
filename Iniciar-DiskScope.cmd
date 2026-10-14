@echo off
setlocal
where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo PowerShell 7 nao foi encontrado.
  echo Instale-o ou execute DiskScope.ps1 em um PowerShell com suporte a WPF.
  pause
  exit /b 1
)
pwsh.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0DiskScope.ps1" %*
