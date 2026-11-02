@echo off
setlocal

set "URL=https://github.com/tue-computer/Admin-Toolbox/blob/main/Admin-Toolbox.exe?raw=true"
set "ZIEL="%USERPROFILE%\Desktop\Admin-Toolbox.exe"

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

pause
```