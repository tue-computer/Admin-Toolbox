@echo off
setlocal

set "URL=https://raw.githubusercontent.com/tue-computer/Admin-Toolbox/main/Admin-Toolbox.exe"
set "ZIEL=%USERPROFILE%\Desktop\Admin-Toolbox.exe"

echo =================================
echo       Programm aktualisieren
echo =================================

curl -L --fail "%URL%" -o "%ZIEL%.tmp"

if errorlevel 1 (
    echo Download fehlgeschlagen!
    del "%ZIEL%.tmp" 2>nul
    pause
    exit /b 1
)

move /Y "%ZIEL%.tmp" "%ZIEL%" >nul

echo.
echo Update erfolgreich!
echo Speicherort: %ZIEL%

timeout /t 2 >nul