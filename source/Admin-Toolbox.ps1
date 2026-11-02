
# ============================================================
# ADMIN-TOOLBOX
# PowerShell-Version
# ============================================================

$ErrorActionPreference = "Stop"

chcp 65001 | Out-Null

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$AdminUser = ""
$AdminPassword = $null

$MMC = Join-Path $env:WINDIR "System32\mmc.exe"
$PowerShellExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
$System32 = Join-Path $env:WINDIR "System32"

$Host.UI.RawUI.WindowTitle = "Admin Toolbox"

# ============================================================
# KONSOLENFENSTER DYNAMISCH AUF 80 % DER BILDSCHIRMFLÄCHE SETZEN
# ============================================================

Add-Type -AssemblyName System.Windows.Forms

$Screen = [System.Windows.Forms.Screen]::PrimaryScreen
$ScreenWidth  = $Screen.Bounds.Width
$ScreenHeight = $Screen.Bounds.Height

$WindowWidth  = [int]($ScreenWidth * 0.80)
$WindowHeight = [int]($ScreenHeight * 0.80)

if (-not ("ConsoleWindowSizer" -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;

public class ConsoleWindowSizer {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SetWindowPos(
        IntPtr hWnd, IntPtr hWndInsertAfter,
        int X, int Y, int cx, int cy, uint uFlags
    );
}
'@
}

$Handle = [ConsoleWindowSizer]::GetConsoleWindow()

if ($Handle -ne [IntPtr]::Zero) {
    $X = [int](($ScreenWidth - $WindowWidth) / 2)
    $Y = [int](($ScreenHeight - $WindowHeight) / 2)

    [void][ConsoleWindowSizer]::SetWindowPos(
        $Handle,
        [IntPtr]::Zero,
        $X, $Y,
        $WindowWidth, $WindowHeight,
        0x0004
    )
}

# ============================================================
# WINDOWS API: NETZWERK-ANMELDUNG MIT AD-KONTO
# ============================================================

if (-not ("NetOnlyLauncher" -as [type])) {

Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public class NetOnlyLauncher {

    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize;
        public int dwXCountChars, dwYCountChars;
        public int dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2;
        public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess, hThread;
        public int dwProcessId, dwThreadId;
    }

    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool CreateProcessWithLogonW(
        string user, string domain, string password, int logonFlags,
        string applicationName, StringBuilder commandLine, int creationFlags,
        IntPtr environment, string currentDirectory,
        ref STARTUPINFO startupInfo, out PROCESS_INFORMATION processInfo);

    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr handle);
}
'@
}

# ============================================================
# FUNKTION: AD-PROGRAMME MIT NETZWERK-ANMELDUNG STARTEN
# ============================================================

function Start-ADProcess {
    param(
        [string]$Name,
        [string]$File,
        [string]$Arguments = ""
    )

    Write-Host ""
    Write-Host "Starte $Name ..." -ForegroundColor Cyan

    try {
        if (-not (Test-Path $File)) {
            throw "Datei wurde nicht gefunden: $File"
        }

        if ([string]::IsNullOrWhiteSpace($AdminUser)) {
            if ([string]::IsNullOrWhiteSpace($Arguments)) {
                Start-Process -FilePath $File -WorkingDirectory $System32
            }
            else {
                Start-Process -FilePath $File -ArgumentList $Arguments -WorkingDirectory $System32
            }
            return
        }

        if ($AdminUser -match '\\') {
            $Parts = $AdminUser.Split('\', 2)
            $Domain = $Parts[0]
            $User = $Parts[1]
        }
        elseif ($AdminUser -match '@') {
            $Domain = $null
            $User = $AdminUser
        }
        else {
            $Domain = "."
            $User = $AdminUser
        }

        $SI = New-Object NetOnlyLauncher+STARTUPINFO
        $SI.cb = [Runtime.InteropServices.Marshal]::SizeOf($SI)

        $PI = New-Object NetOnlyLauncher+PROCESS_INFORMATION

        $CommandLine = New-Object System.Text.StringBuilder
        [void]$CommandLine.Append('"' + $File + '" ' + $Arguments)

        # LOGON_NETCREDENTIALS_ONLY = 2
        $Success = [NetOnlyLauncher]::CreateProcessWithLogonW(
            $User,
            $Domain,
            $AdminPassword,
            2,
            $File,
            $CommandLine,
            0,
            [IntPtr]::Zero,
            $System32,
            [ref]$SI,
            [ref]$PI
        )

        if (-not $Success) {
            $ErrorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "Windows-Fehler $ErrorCode beim Starten von $Name."
        }

        # Prozess läuft unabhängig weiter.
        # Handles schließen, ohne auf das Programm zu warten.
        [void][NetOnlyLauncher]::CloseHandle($PI.hThread)
        [void][NetOnlyLauncher]::CloseHandle($PI.hProcess)
    }
    catch {
        Write-Host ""
        Write-Host "Fehler beim Starten von $Name" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        Read-Host "Weiter mit Enter"
    }
}

# ============================================================
# FUNKTION: MMC MIT OPTIONALEN AD-ZUGANGSDATEN STARTEN
# ============================================================

function Start-MmcTool {
    param(
        [string]$Name,
        [string]$SnapIn,
        [bool]$UseADCredentials = $false
    )

    $SnapInPath = Join-Path $System32 $SnapIn

    if (-not (Test-Path $SnapInPath)) {
        Write-Host ""
        Write-Host "Snap-in nicht gefunden: $SnapInPath" -ForegroundColor Red
        Read-Host "Weiter mit Enter"
        return
    }

    if ($UseADCredentials) {
        Start-ADProcess $Name $MMC "`"$SnapInPath`""
    }
    else {
        Write-Host ""
        Write-Host "Starte $Name ..." -ForegroundColor Cyan

        try {
            Start-Process -FilePath $MMC -ArgumentList "`"$SnapInPath`"" -WorkingDirectory $System32
        }
        catch {
            Write-Host "Fehler: $($_.Exception.Message)" -ForegroundColor Red
            Read-Host "Weiter mit Enter"
        }
    }
}

# ============================================================
# FUNKTION: SERVER-TOOLS STARTEN
# ============================================================

function Start-Tool {
    param(
        [string]$Name,
        [string]$File,
        [string]$Arguments = ""
    )

    Write-Host ""
    Write-Host "Starte $Name ..." -ForegroundColor Cyan

    try {
        if (-not (Test-Path $File)) {
            throw "Programm wurde nicht gefunden: $File"
        }

        # ArgumentList nur übergeben, wenn Argumente vorhanden sind.
        if ([string]::IsNullOrWhiteSpace($Arguments)) {
            Start-Process -FilePath $File -WorkingDirectory $System32
        }
        else {
            Start-Process -FilePath $File -ArgumentList $Arguments -WorkingDirectory $System32
        }
    }
    catch {
        Write-Host ""
        Write-Host "Fehler beim Starten von $Name" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        Read-Host "Weiter mit Enter"
    }
}

# ============================================================
# FUNKTION: WINDOWS LAPS KENNWORT ABFRAGEN
# VERWENDET DEN AKTUELLEN WINDOWS-BENUTZER
# ============================================================

function Get-WindowsLapsPassword {

    Clear-Host

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "                 WINDOWS LAPS" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    try {

        # Tatsächlich angemeldeten Windows-Benutzer anzeigen
        $CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name

        Write-Host "LAPS-Abfrage mit Windows-Benutzer:" -ForegroundColor Green
        Write-Host $CurrentUser -ForegroundColor Yellow
        Write-Host ""

        # LAPS-Modul laden
        Import-Module LAPS -ErrorAction Stop

        Get-Command Get-LapsADPassword -ErrorAction Stop | Out-Null

        $ComputerName = Read-Host "PC-Name"

        if ([string]::IsNullOrWhiteSpace($ComputerName)) {
            throw "Kein PC-Name angegeben."
        }

        $ComputerName = $ComputerName.Trim()

        Write-Host ""
        Write-Host "Rufe LAPS-Kennwort für $ComputerName ab ..." -ForegroundColor Cyan

        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Ausschließlich aktuelle Windows-Anmeldung verwenden
        $LapsResult = Get-LapsADPassword `
            -Identity $ComputerName `
            -AsPlainText `
            -ErrorAction Stop

        $Stopwatch.Stop()

        if (-not $LapsResult) {
            throw "Keine LAPS-Daten für $ComputerName gefunden."
        }

        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Green
        Write-Host "                 LAPS-ERGEBNIS" -ForegroundColor Green
        Write-Host "============================================================" -ForegroundColor Green
        Write-Host ""

        $LapsResult | Format-List *

        Write-Host ""
        Write-Host "Abfragedauer: $([math]::Round($Stopwatch.Elapsed.TotalSeconds,2)) Sekunden" -ForegroundColor Gray

    }
    catch {

        Write-Host ""
        Write-Host "LAPS-Abfrage fehlgeschlagen!" -ForegroundColor Red
        Write-Host ""
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Bitte Windows-Benutzerrechte, AD-Verbindung und LAPS-Modul prüfen." -ForegroundColor Yellow

    }

    Write-Host ""
    Read-Host "Weiter mit Enter"
}


# ============================================================
# FUNKTION: ZENTRALES GPUPDATE AUF REMOTE-PC
# ============================================================

function Invoke-RemoteGPUpdate {

    Clear-Host

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "             ZENTRALES GROUP POLICY UPDATE" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    # Zielcomputer abfragen
    $TargetPC = Read-Host "PC-Name"

    if ([string]::IsNullOrWhiteSpace($TargetPC)) {
        Write-Host "Kein Computername angegeben!" -ForegroundColor Red
        Read-Host "Weiter mit Enter"
        return
    }

    $TargetPC = $TargetPC.Trim()

    # Benutzer abfragen
    Write-Host ""
    Write-Host "Verwendete Domäne: $DomainInput" -ForegroundColor Cyan

    $TargetUser = Read-Host "Lokaler Administrator"

    if ([string]::IsNullOrWhiteSpace($TargetUser)) {
        Write-Host "Kein Benutzer angegeben!" -ForegroundColor Red
        Read-Host "Weiter mit Enter"
        return
    }

    $TargetUser = $TargetUser.Trim()

    # Vorhandene Domäne mit Benutzer kombinieren
    if ($TargetUser -match '\\' -or $TargetUser -match '@') {
        $DomainUser = $TargetUser
    }
    elseif (-not [string]::IsNullOrWhiteSpace($DomainInput)) {
        $DomainUser = "$DomainInput\$TargetUser"
    }
    else {
        throw "Keine Domäne in der Startkonfiguration vorhanden."
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "Zielcomputer:    $TargetPC" -ForegroundColor Yellow
    Write-Host "Domänenbenutzer: $DomainUser" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan

    Write-Host ""
    $Confirm = Read-Host "GPUpdate jetzt ausführen? (J/N)"

    if ($Confirm -notmatch '^(J|JA)$') {
        Write-Host "Vorgang abgebrochen." -ForegroundColor Yellow
        Read-Host "Weiter mit Enter"
        return
    }

    try {

        Write-Host ""
        Write-Host "Prüfe Verbindung zu $TargetPC ..." -ForegroundColor Cyan

        if (-not (Test-Connection -ComputerName $TargetPC -Count 1 -Quiet)) {
            throw "Computer $TargetPC ist nicht erreichbar."
        }

        Write-Host "Computer erreichbar." -ForegroundColor Green

        # GroupPolicy-Modul laden
        Import-Module GroupPolicy -ErrorAction Stop

        Write-Host ""
        Write-Host "Starte zentrales GPUpdate ..." -ForegroundColor Cyan

        Invoke-GPUpdate `
            -Computer $TargetPC `
            -Force `
            -RandomDelayInMinutes 0 `
            -ErrorAction Stop

        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Green
        Write-Host "          GPUPDATE ERFOLGREICH ANGESTOSSEN" -ForegroundColor Green
        Write-Host "============================================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Zielcomputer: $TargetPC" -ForegroundColor Yellow
        Write-Host "Benutzer:     $DomainUser" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Die Gruppenrichtlinienaktualisierung wurde remote angestoßen." -ForegroundColor Green
        Write-Host ""
        Write-Host "Hinweis: Invoke-GPUpdate aktualisiert die Computer-" -ForegroundColor Gray
        Write-Host "und die auf dem Ziel-PC angemeldeten Benutzersitzungen." -ForegroundColor Gray

    }
    catch {

        Write-Host ""
        Write-Host "GPUPDATE FEHLGESCHLAGEN!" -ForegroundColor Red
        Write-Host ""
        Write-Host $_.Exception.Message -ForegroundColor Yellow

    }

    Write-Host ""
    Read-Host "Weiter mit Enter"
}

# ============================================================
# STARTKONFIGURATION
# ============================================================

Clear-Host

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "                    ADMIN TOOLBOX" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "AD-Administratorkonto eingeben"
Write-Host "Leer lassen = aktueller Windows-Benutzer"
Write-Host ""

# Domäne abfragen
$DomainInput = Read-Host "Domäne"

if ([string]::IsNullOrWhiteSpace($DomainInput)) {
    $AdminUser = ""
}
else {
    $DomainInput = $DomainInput.Trim()

    # AD-Administrator abfragen
    $AdminName = Read-Host "AD-Administrator"

    if ([string]::IsNullOrWhiteSpace($AdminName)) {
        Write-Host "Kein AD-Administrator angegeben!" -ForegroundColor Red
        Read-Host "Weiter mit Enter"
        exit
    }

    $AdminName = $AdminName.Trim()

    # Domäne und Benutzer zusammensetzen
    $AdminUser = "$DomainInput\$AdminName"

    # Kennwort abfragen
    $SecurePassword = Read-Host "Kennwort" -AsSecureString

    $BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
    $AdminPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    $SecurePassword.Dispose()

    Write-Host ""
    Write-Host "AD-Verwaltung wird mit folgendem Konto gestartet:" -ForegroundColor Green
    Write-Host "AD-Konto: $AdminUser" -ForegroundColor Green
}

if (-not $AdminUser) {
    Write-Host "AD-Verwaltung verwendet das aktuelle Windows-Konto." -ForegroundColor Yellow
}

Start-Sleep -Seconds 2


# ============================================================
# HAUPTMENUE
# ============================================================

do {

    Clear-Host

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "                    ADMIN TOOLBOX" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    if ($AdminUser) {
        Write-Host "AD-Konto:       $AdminUser"
    }
    else {
        Write-Host "AD-Konto:       Aktueller Benutzer"
    }

    Write-Host "Server-Konto:   $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    Write-Host ""

    Write-Host "------------------------------------------------------------"
    Write-Host "  ACTIVE DIRECTORY"
    Write-Host "------------------------------------------------------------"
    Write-Host ""
    Write-Host "  [1]  AD Benutzer und Computer"
    Write-Host "  [2]  AD PowerShell"
    Write-Host "  [3]  DNS-Verwaltung"
    Write-Host "  [4]  DHCP-Verwaltung"
    Write-Host "  [5]  Gruppenrichtlinienverwaltung (GPO)"
    Write-Host "  [6]  Zentrales GPUpdate auf Remote-PC"
    Write-Host ""

    Write-Host "------------------------------------------------------------"
    Write-Host "  SERVER UND INFRASTRUKTUR"
    Write-Host "------------------------------------------------------------"
    Write-Host ""
    Write-Host "  [7]  Windows LAPS Kennwortabfrage"
    Write-Host "  [8]  DFS-Verwaltung"
    Write-Host "  [9]  Computerverwaltung"
    Write-Host "  [10] Ereignisanzeige"
    Write-Host "  [11] Hyper-V-Manager"
    Write-Host "  [12] Server-Manager"
    Write-Host "  [13] Druckverwaltung"
    Write-Host ""

    Write-Host "------------------------------------------------------------"
    Write-Host ""
    Write-Host "  [0]  Beenden"
    Write-Host ""
    Write-Host "============================================================"
    Write-Host ""

    $Auswahl = Read-Host "Bitte Auswahl treffen"

    switch ($Auswahl) {

        # ACTIVE DIRECTORY

        "1" {
            Start-MmcTool "AD Benutzer und Computer" "dsa.msc" $true
        }

        "2" {
            Start-ADProcess "AD PowerShell" $PowerShellExe '-NoExit -Command "Import-Module ActiveDirectory"'
        }

        "3" {
            Start-MmcTool "DNS-Verwaltung" "dnsmgmt.msc" $true
        }

        "4" {
            $DhcpServer = Read-Host "DHCP-Server eingeben"

            if (-not [string]::IsNullOrWhiteSpace($DhcpServer)) {
                $DhcpPath = Join-Path $System32 "dhcpmgmt.msc"

                Start-ADProcess -Name "DHCP-Verwaltung" -File $MMC -Arguments "`"$DhcpPath`" /ComputerName $DhcpServer"
            }
        }

        "5" {
            $GpoPath = Join-Path $System32 "gpmc.msc"

            Start-ADProcess -Name "Gruppenrichtlinienverwaltung" -File $MMC -Arguments "`"$GpoPath`""
        }

        "6" {
            Invoke-RemoteGPUpdate
        }

        # SERVER UND INFRASTRUKTUR

        "7" {
            Get-WindowsLapsPassword
        }

        "8" {
            Start-MmcTool "DFS-Verwaltung" "dfsmgmt.msc"
        }

        "9" {
            $TargetPC = Read-Host "Ziel-PC eingeben"

            if (-not [string]::IsNullOrWhiteSpace($TargetPC)) {
                $SnapInPath = Join-Path $System32 "compmgmt.msc"
                $Arguments = "`"$SnapInPath`" /computer=$TargetPC"

                Start-Tool "Computerverwaltung" $MMC $Arguments
            }
        }

        "10" {
            $TargetPC = Read-Host "Ziel-PC eingeben (z.B. PC-001)"

            if (-not [string]::IsNullOrWhiteSpace($TargetPC)) {
                $EventViewerExe = Join-Path $System32 "eventvwr.exe"

                Start-Tool -Name "Ereignisanzeige" -File $EventViewerExe -Arguments $TargetPC
            }
        }

        "11" {
            Start-MmcTool "Hyper-V-Manager" "virtmgmt.msc"
        }

        "12" {
            Start-Tool "Server-Manager" (Join-Path $System32 "ServerManager.exe")
        }

        "13" {
            Start-MmcTool "Druckverwaltung" "printmanagement.msc"
        }

        "0" {
            Write-Host ""
            Write-Host "Admin Toolbox wird beendet." -ForegroundColor Cyan
        }

        default {
            Write-Host ""
            Write-Host "Ungültige Auswahl!" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }

} while ($Auswahl -ne "0")


# ============================================================
# AUFRÄUMEN
# ============================================================

$AdminPassword = $null
$SecurePassword = $null

Write-Host ""
Write-Host "Programm beendet."
Start-Sleep -Seconds 1
