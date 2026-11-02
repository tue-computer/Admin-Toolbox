
# ============================================================
# ADMIN-TOOLBOX
# ============================================================

$ErrorActionPreference = "Stop"

# ============================================================
# AUTOMATISCHES UPDATE DER ADMIN-TOOLBOX
# ============================================================

try {

    # Nur bei gestarteter EXE ausführen
    $ExePath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

    if ([System.IO.Path]::GetFileName($ExePath) -ieq "Admin-Toolbox.exe") {

        # GitHub-Einstellungen
        $ApiUrl = "https://api.github.com/repos/tue-computer/Admin-Toolbox/contents/source/Admin-Toolbox.exe?ref=main"
        $DownloadUrl = "https://raw.githubusercontent.com/tue-computer/Admin-Toolbox/main/source/Admin-Toolbox.exe"

        # TLS 1.2 aktivieren
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        Write-Host ""
        Write-Host "Prüfe auf Updates..." -ForegroundColor Cyan

        # GitHub-Dateiinformationen abrufen
        $GitHubInfo = Invoke-RestMethod `
            -Uri $ApiUrl `
            -Headers @{
                "User-Agent" = "Admin-Toolbox-Updater"
                "Accept" = "application/vnd.github+json"
            } `
            -ErrorAction Stop

        if (-not $GitHubInfo.sha -or $GitHubInfo.type -ne "file") {
            throw "Ungültige Dateiinformationen von GitHub erhalten."
        }

        # Funktion zur Berechnung des GitHub-Datei-Hashes
        $GetGitHash = {
            param([string]$Path)

            $FileBytes = [System.IO.File]::ReadAllBytes($Path)
            $Header = [System.Text.Encoding]::UTF8.GetBytes("blob $($FileBytes.Length)`0")

            $GitBlob = New-Object byte[] ($Header.Length + $FileBytes.Length)

            [Array]::Copy($Header, 0, $GitBlob, 0, $Header.Length)
            [Array]::Copy($FileBytes, 0, $GitBlob, $Header.Length, $FileBytes.Length)

            $SHA = [System.Security.Cryptography.SHA1]::Create()

            try {
                $HashBytes = $SHA.ComputeHash($GitBlob)
                return ([BitConverter]::ToString($HashBytes)).Replace("-", "").ToLowerInvariant()
            }
            finally {
                $SHA.Dispose()
            }
        }

        # Lokale Version prüfen
        $LocalHash = & $GetGitHash $ExePath

        if ($LocalHash -eq $GitHubInfo.sha.ToLowerInvariant()) {

            Write-Host "Admin-Toolbox ist aktuell." -ForegroundColor Green

        }
        else {

            Write-Host "Neue Version gefunden!" -ForegroundColor Yellow
            Write-Host "Lade Update herunter..." -ForegroundColor Cyan

            # Temporäre Datei im gleichen Verzeichnis
            $UpdateFile = "$ExePath.update"

            if (Test-Path -LiteralPath $UpdateFile) {
                Remove-Item -LiteralPath $UpdateFile -Force
            }

            # Neue EXE herunterladen
            $BlobUrl = "https://api.github.com/repos/tue-computer/Admin-Toolbox/git/blobs/$($GitHubInfo.sha)"

            Invoke-WebRequest `
                -Uri $BlobUrl `
                -OutFile $UpdateFile `
                -UseBasicParsing `
                -Headers @{
                    "User-Agent" = "Admin Toolbox Updater"
                    "Accept" = "application/vnd.github.raw"
                } `
                -ErrorAction Stop

            # Download überprüfen
            $DownloadedHash = & $GetGitHash $UpdateFile

            if ($DownloadedHash -ne $GitHubInfo.sha.ToLowerInvariant()) {
                Write-Host ""
                Write-Host "Hash-Prüfung fehlgeschlagen!" -ForegroundColor Red
                Write-Host "GitHub SHA:     $($GitHubInfo.sha)"
                Write-Host "Download SHA:   $DownloadedHash"
                Write-Host "GitHub Größe:   $($GitHubInfo.size) Bytes"
                Write-Host "Download Größe: $((Get-Item $UpdateFile).Length) Bytes"
                Write-Host "Download URL:   $DownloadUrl"
                Write-Host ""
            }          

            Write-Host "Download erfolgreich überprüft." -ForegroundColor Green
            Write-Host "Installiere Update..." -ForegroundColor Cyan

            # Prozess-ID der aktuellen EXE
            $ParentPid = $PID

            # Pfade sicher kodieren
            $UpdateFileEncoded = [Convert]::ToBase64String(
                [Text.Encoding]::UTF8.GetBytes($UpdateFile)
            )

            $ExePathEncoded = [Convert]::ToBase64String(
                [Text.Encoding]::UTF8.GetBytes($ExePath)
            )

            # Hilfsskript mit fest eingebetteten Parametern
            $UpdateScript = @"
`$ParentPid = $ParentPid
`$UpdateFile = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$UpdateFileEncoded'))
`$TargetExe = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$ExePathEncoded'))

# Warten, bis die Admin-Toolbox vollständig beendet ist
while (Get-Process -Id `$ParentPid -ErrorAction SilentlyContinue) {
    Start-Sleep -Milliseconds 500
}

try {
    # Update-Datei an die Stelle der bisherigen EXE verschieben
    Move-Item -LiteralPath `$UpdateFile -Destination `$TargetExe -Force -ErrorAction Stop

    # Neue Version starten
    Start-Process -FilePath `$TargetExe -ErrorAction Stop
}
catch {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "Update konnte nicht installiert werden:`n`n`$(`$_.Exception.Message)`n`nDie Update-Datei liegt weiterhin unter:`n`$UpdateFile",
        "Admin-Toolbox - Updatefehler",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}
"@
            # Hilfsskript kodieren
            $EncodedScript = [Convert]::ToBase64String(
                [Text.Encoding]::Unicode.GetBytes($UpdateScript)
            )

            $PowerShellExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"

            # Hilfsprozess starten
            Start-Process `
                -FilePath $PowerShellExe `
                -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $EncodedScript" `
                -WindowStyle Hidden `
                -ErrorAction Stop

            # Aktuelles Programm beenden
            exit
        }
    }
}
catch {

    Write-Host ""
    Write-Host "Update-Prüfung fehlgeschlagen." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "Starte mit der vorhandenen Version." -ForegroundColor Yellow
    Write-Host ""

    if ($UpdateFile -and (Test-Path -LiteralPath $UpdateFile)) {
        Remove-Item -LiteralPath $UpdateFile -Force -ErrorAction SilentlyContinue
    }

    [Console]::WriteLine("")
    [Console]::WriteLine("Drücke Enter, um mit vorhandener Version fortzufahren.")
    [Console]::ReadLine()
}

# ============================================================
# ENDE AUTOMATISCHES UPDATE
# ============================================================

chcp 65001 | Out-Null
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$AdminUser = ""
$SecureAdminPassword = $null
$AdminCredential = $null

$MMC = Join-Path $env:WINDIR "System32\mmc.exe"
$PowerShellExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
$System32 = Join-Path $env:WINDIR "System32"

$Host.UI.RawUI.WindowTitle = "Admin-Toolbox"


# ============================================================
# KONSOLENFENSTER AUF 80 % SETZEN
# ============================================================

Add-Type -AssemblyName System.Windows.Forms

$Screen = [System.Windows.Forms.Screen]::PrimaryScreen
$ScreenWidth = $Screen.Bounds.Width
$ScreenHeight = $Screen.Bounds.Height
$WindowWidth = [int]($ScreenWidth * 0.80)
$WindowHeight = [int]($ScreenHeight * 0.80)

if (-not ("ConsoleWindowSizer" -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;

public class ConsoleWindowSizer {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
}
'@
}

$Handle = [ConsoleWindowSizer]::GetConsoleWindow()

if ($Handle -ne [IntPtr]::Zero) {
    $X = [int](($ScreenWidth - $WindowWidth) / 2)
    $Y = [int](($ScreenHeight - $WindowHeight) / 2)
    [void][ConsoleWindowSizer]::SetWindowPos($Handle, [IntPtr]::Zero, $X, $Y, $WindowWidth, $WindowHeight, 0x0004)
}


# ============================================================
# WINDOWS API - NETZWERK-ANMELDUNG
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
        public string lpReserved, lpDesktop, lpTitle;
        public int dwX, dwY, dwXSize, dwYSize;
        public int dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
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
        string user,
        string domain,
        IntPtr password,
        int logonFlags,
        string applicationName,
        StringBuilder commandLine,
        int creationFlags,
        IntPtr environment,
        string currentDirectory,
        ref STARTUPINFO startupInfo,
        out PROCESS_INFORMATION processInfo
    );

    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr handle);
}
'@
}


# ============================================================
# ZENTRALE HILFSFUNKTIONEN
# ============================================================

function Show-ToolError {
    param([string]$Name, [string]$Message)

    Write-Host ""
    Write-Host "Fehler bei $Name!" -ForegroundColor Red
    Write-Host $Message -ForegroundColor Yellow
    Read-Host "Weiter mit Enter"
}


# ============================================================
# PROGRAMME STARTEN
# ============================================================

function Start-AdminProcess {
    param(
        [string]$Name,
        [string]$File,
        [string]$Arguments = "",
        [string]$WorkingDirectory = $System32,
        [bool]$UseADCredentials = $false
    )

    Write-Host ""
    Write-Host "Starte $Name ..." -ForegroundColor Cyan

    $BSTR = [IntPtr]::Zero
    $PI = New-Object NetOnlyLauncher+PROCESS_INFORMATION
    $ProcessStarted = $false

    try {
        if (-not (Test-Path $File)) {
            throw "Programm wurde nicht gefunden: $File"
        }

        if (-not $UseADCredentials -or [string]::IsNullOrWhiteSpace($AdminUser)) {
            $StartParams = @{
                FilePath = $File
                WorkingDirectory = $WorkingDirectory
                ErrorAction = "Stop"
            }

            if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
                $StartParams.ArgumentList = $Arguments
            }

            Start-Process @StartParams
            return
        }

        if (-not $SecureAdminPassword) {
            throw "Kein AD-Kennwort in der Sitzung vorhanden."
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

        $CommandLine = New-Object System.Text.StringBuilder
        [void]$CommandLine.Append('"' + $File + '" ' + $Arguments)

        # SecureString nur für den API-Aufruf in BSTR umwandeln
        $BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureAdminPassword)

        # LOGON_NETCREDENTIALS_ONLY = 2
        $Success = [NetOnlyLauncher]::CreateProcessWithLogonW(
            $User, $Domain, $BSTR, 2, $File,
            $CommandLine, 0, [IntPtr]::Zero, $WorkingDirectory,
            [ref]$SI, [ref]$PI
        )

        if (-not $Success) {
            $ErrorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "Windows-Fehler $ErrorCode beim Starten von $Name."
        }

        $ProcessStarted = $true
    }
    catch {
        Show-ToolError -Name $Name -Message $_.Exception.Message
    }
    finally {
        # Klartext-BSTR sofort überschreiben und freigeben
        if ($BSTR -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        }

        if ($ProcessStarted) {
            [void][NetOnlyLauncher]::CloseHandle($PI.hThread)
            [void][NetOnlyLauncher]::CloseHandle($PI.hProcess)
        }
    }
}


# ============================================================
# MMC-VERWALTUNG
# ============================================================

function Start-MmcTool {
    param(
        [string]$Name,
        [string]$SnapIn,
        [bool]$UseADCredentials = $false
    )

    $SnapInPath = Join-Path $System32 $SnapIn

    if (-not (Test-Path $SnapInPath)) {
        Show-ToolError -Name $Name -Message "Snap-in nicht gefunden: $SnapInPath"
        return
    }

    Start-AdminProcess -Name $Name -File $MMC -Arguments "`"$SnapInPath`"" -UseADCredentials $UseADCredentials
}


# ============================================================
# WINDOWS LAPS
# ============================================================

function Get-WindowsLapsPassword {
    Clear-Host

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "                    WINDOWS LAPS" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    try {
        $CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name

        Write-Host "LAPS-Abfrage mit Windows-Benutzer:" -ForegroundColor Green
        Write-Host $CurrentUser -ForegroundColor Yellow
        Write-Host ""

        Import-Module LAPS -ErrorAction Stop
        Get-Command Get-LapsADPassword -ErrorAction Stop | Out-Null

        $ComputerName = (Read-Host "PC-Name").Trim()

        if ([string]::IsNullOrWhiteSpace($ComputerName)) {
            throw "Kein PC-Name angegeben."
        }

        Write-Host ""
        Write-Host "Rufe LAPS-Kennwort für $ComputerName ab ..." -ForegroundColor Cyan

        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $LapsResult = Get-LapsADPassword -Identity $ComputerName -AsPlainText -ErrorAction Stop
        $Stopwatch.Stop()

        if (-not $LapsResult) {
            throw "Keine LAPS-Daten für $ComputerName gefunden."
        }

        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Green
        Write-Host "                    LAPS-ERGEBNIS" -ForegroundColor Green
        Write-Host "============================================================" -ForegroundColor Green
        Write-Host ""

        $LapsResult | Format-List *

        Write-Host ""
        Write-Host "Abfragedauer: $([math]::Round($Stopwatch.Elapsed.TotalSeconds,2)) Sekunden" -ForegroundColor Gray
    }
    catch {
        Write-Host ""
        Write-Host "LAPS-Abfrage fehlgeschlagen!" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Bitte Windows-Benutzerrechte, AD-Verbindung und LAPS-Modul prüfen." -ForegroundColor Yellow
    }

    Write-Host ""
    Read-Host "Weiter mit Enter"
}


# ============================================================
# REMOTE-GPUPDATE
# 1 = AKTUELLER BENUTZER
# 2 = HINTERLEGTER AD-BENUTZER
# 3 = ANDERER BENUTZER
# ============================================================

function Invoke-RemoteGPUpdate {
    Clear-Host

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "             ZENTRALES GROUP POLICY UPDATE" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    $Credential = $null

    try {
        $TargetPC = (Read-Host "Ziel-PC").Trim()

        if ([string]::IsNullOrWhiteSpace($TargetPC)) {
            Write-Host "Kein Computername angegeben!" -ForegroundColor Red
            return
        }

        Write-Host ""
        Write-Host "BENUTZER FÜR REMOTE-GPUPDATE" -ForegroundColor Cyan
        Write-Host "------------------------------------------------------------"
        Write-Host "[1] Aktueller Server-Benutzer"
        Write-Host "[2] Hinterlegter AD-Benutzer"
        Write-Host "[3] Anderen Benutzer angeben"
        Write-Host "------------------------------------------------------------"

        $UserChoice = Read-Host "Auswahl"

        $InvokeParams = @{
            ComputerName = $TargetPC
            ErrorAction = "Stop"
            ScriptBlock = {
                $GpUpdateExe = Join-Path $env:WINDIR "System32\gpupdate.exe"

                Write-Output "Starte GPUpdate auf $env:COMPUTERNAME ..."

                $GpOutput = & $GpUpdateExe /force 2>&1
                $GpExitCode = $LASTEXITCODE

                foreach ($Line in $GpOutput) {
                    Write-Output $Line
                }

                if ($GpExitCode -ne 0) {
                    throw "gpupdate.exe wurde mit Fehlercode $GpExitCode beendet."
                }

                Write-Output "GPUpdate wurde auf $env:COMPUTERNAME ausgeführt."
            }
        }

        switch ($UserChoice) {
            "1" {
                $SelectedUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name

                Write-Host ""
                Write-Host "Verwendeter Benutzer: $SelectedUser" -ForegroundColor Yellow
            }

            "2" {
                if ([string]::IsNullOrWhiteSpace($AdminUser) -or -not $AdminCredential) {
                    throw "Es wurde bei der Startkonfiguration kein AD-Konto mit Kennwort hinterlegt."
                }

                $Credential = $AdminCredential
                $SelectedUser = $AdminUser
                $InvokeParams.Credential = $Credential

                Write-Host ""
                Write-Host "Verwendeter Benutzer: $SelectedUser" -ForegroundColor Yellow
            }

            "3" {
                $CustomUser = (Read-Host "Benutzername (DOMÄNE\Benutzer oder Benutzer@Domäne)").Trim()

                if ([string]::IsNullOrWhiteSpace($CustomUser)) {
                    throw "Kein Benutzer angegeben."
                }

                $Credential = Get-Credential -UserName $CustomUser -Message "Kennwort für Benutzer angeben"

                if (-not $Credential) {
                    throw "Keine Zugangsdaten angegeben."
                }

                $SelectedUser = $Credential.UserName
                $InvokeParams.Credential = $Credential

                Write-Host ""
                Write-Host "Verwendeter Benutzer: $SelectedUser" -ForegroundColor Yellow
            }

            default {
                Write-Host "Ungültige Auswahl!" -ForegroundColor Red
                return
            }
        }

        Write-Host "Starte gpupdate auf $TargetPC ..." -ForegroundColor Green

        $RemoteResult = Invoke-Command @InvokeParams

        Write-Host ""
        foreach ($Line in $RemoteResult) {
            Write-Host $Line
        }

        Write-Host "gpupdate erfolgreich" -ForegroundColor Green
    }
    catch {
        Write-Host ""
        Write-Host "gpupdate fehlgeschlagen!" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Bitte WinRM, Firewall und Berechtigungen prüfen." -ForegroundColor Yellow
    }
    finally {
        # Nur lokale Referenz freigeben.
        # Das globale AD-Credential bleibt für die Sitzung erhalten.
        if ($Credential -ne $AdminCredential) {
            $Credential = $null
        }
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
Write-Host "                    Admin-Toolbox" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Domäne automatisch aus der angemeldeten Sitzung ermitteln
$CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$CurrentDomain = (Get-CimInstance Win32_ComputerSystem).Domain

Write-Host "Aktuelle Windows-Anmeldung:" -ForegroundColor Cyan
Write-Host "Benutzer: $($CurrentIdentity.Name)" -ForegroundColor Yellow
Write-Host "Domäne:   $CurrentDomain" -ForegroundColor Yellow
Write-Host ""

# AD-Benutzer weiterhin abfragen
$AdminName = Read-Host "AD-Administrator (ohne Domäne)"

if ([string]::IsNullOrWhiteSpace($AdminName)) {
    Write-Host "Kein AD-Administrator angegeben!" -ForegroundColor Red
    Read-Host "Weiter mit Enter"
    exit
}

# Domäne automatisch mit Benutzer verbinden
$AdminUser = "$CurrentDomain\$($AdminName.Trim())"

# Kennwort weiterhin sicher abfragen
$SecureAdminPassword = Read-Host "AD-Kennwort" -AsSecureString

# PSCredential erstellen
$AdminCredential = [PSCredential]::new(
    $AdminUser,
    $SecureAdminPassword
)

Write-Host ""
Write-Host "AD-Verwaltung wird mit folgendem Konto gestartet:" -ForegroundColor Green
Write-Host "AD-Konto: $AdminUser" -ForegroundColor Green

Start-Sleep -Seconds 1

# ============================================================
# HAUPTMENÜ
# ============================================================

do {
    Clear-Host

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "                    Admin-Toolbox" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    if ($AdminUser) {
        Write-Host " AD-Konto:     $AdminUser"
    }
    else {
        Write-Host " AD-Konto:     Aktueller Benutzer"
    }

    Write-Host " Server-Konto: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host " ACTIVE DIRECTORY" -ForegroundColor Cyan
    Write-Host " [10] Benutzer und Computer     [11] PowerShell"
    Write-Host ""

    Write-Host " DNS & DHCP" -ForegroundColor Cyan
    Write-Host " [30] DNS-Verwaltung            [31] DHCP-Verwaltung"
    Write-Host ""

    Write-Host " GRUPPENRICHTLINIEN" -ForegroundColor Cyan
    Write-Host " [40] GPO-Verwaltung            [41] Remote-GPUpdate"
    Write-Host ""

    Write-Host " SERVER" -ForegroundColor Cyan
    Write-Host " [50] Computerverwaltung        [51] Ereignisanzeige"
    Write-Host " [52] Server-Manager            [53] Druckverwaltung"
    Write-Host " [54] Hyper-V-Manager           [55] DFS-Verwaltung"
    Write-Host ""

    Write-Host " SICHERHEIT" -ForegroundColor Cyan
    Write-Host " [80] LAPS-Kennwort auslesen"
    Write-Host ""

    Write-Host " [0] Beenden" -ForegroundColor Yellow
    Write-Host ""

    $Auswahl = Read-Host "Bitte Auswahl treffen"

    switch ($Auswahl) {
        "10" {
            Start-MmcTool -Name "Benutzer und Computer" -SnapIn "dsa.msc" -UseADCredentials $true
        }

        "11" {
            Start-AdminProcess -Name "PowerShell" -File $PowerShellExe -Arguments '-NoExit -Command "Import-Module ActiveDirectory"' -UseADCredentials $true
        }

        "30" {
            $DnsServer = (Read-Host "DNS-Server eingeben").Trim()

            if (-not [string]::IsNullOrWhiteSpace($DnsServer)) {
                $DnsPath = Join-Path $System32 "dnsmgmt.msc"
                Start-AdminProcess -Name "DNS-Verwaltung" -File $MMC -Arguments "`"$DnsPath`" /computername $DnsServer" -UseADCredentials $true
            }
        }

        "31" {
            $DhcpServer = (Read-Host "DHCP-Server eingeben").Trim()

            if (-not [string]::IsNullOrWhiteSpace($DhcpServer)) {
                $DhcpPath = Join-Path $System32 "dhcpmgmt.msc"
                Start-AdminProcess -Name "DHCP-Verwaltung" -File $MMC -Arguments "`"$DhcpPath`" /ComputerName $DhcpServer" -UseADCredentials $true
            }
        }

        "40" {
            $GpoPath = Join-Path $System32 "gpmc.msc"
            Start-AdminProcess -Name "Gruppenrichtlinienverwaltung" -File $MMC -Arguments "`"$GpoPath`"" -UseADCredentials $true
        }

        "41" {
            Invoke-RemoteGPUpdate
        }

        "50" {
            $TargetPC = (Read-Host "Ziel-PC eingeben").Trim()

            if (-not [string]::IsNullOrWhiteSpace($TargetPC)) {
                $SnapInPath = Join-Path $System32 "compmgmt.msc"
                Start-AdminProcess -Name "Computerverwaltung" -File $MMC -Arguments "`"$SnapInPath`" /computer=$TargetPC"
            }
        }

        "51" {
            $TargetPC = (Read-Host "Ziel-PC").Trim()

            if (-not [string]::IsNullOrWhiteSpace($TargetPC)) {
                $EventViewerExe = Join-Path $System32 "eventvwr.exe"
                Start-AdminProcess -Name "Ereignisanzeige" -File $EventViewerExe -Arguments $TargetPC
            }
        }

        "52" {
            Write-Host ""
            Write-Host "SERVER-MANAGER STARTEN" -ForegroundColor Cyan
            Write-Host "------------------------------------------------------------"
            Write-Host "[1] Mit AD-Benutzer starten"
            Write-Host "[2] Mit aktuellem Server-Benutzer starten"
            Write-Host "------------------------------------------------------------"

            $ServerManagerChoice = Read-Host "Auswahl"

            switch ($ServerManagerChoice) {
                "1" {
                    if (-not $AdminCredential) {
                        Write-Host "Kein AD-Konto hinterlegt!" -ForegroundColor Red
                        Read-Host "Weiter mit Enter"
                        break
                    }

                    Start-AdminProcess -Name "Server-Manager (AD)" `
                        -File (Join-Path $System32 "ServerManager.exe") `
                        -UseADCredentials $true
                }

                "2" {
                    Start-AdminProcess -Name "Server-Manager (Server-Benutzer)" `
                        -File (Join-Path $System32 "ServerManager.exe")
                }

                default {
                    Write-Host "Ungültige Auswahl!" -ForegroundColor Red
                    Start-Sleep -Seconds 1
                }
            }
        }   

        "53" {
            Start-MmcTool -Name "Druckverwaltung" -SnapIn "printmanagement.msc"
        }

        "54" {
            Start-MmcTool -Name "Hyper-V-Manager" -SnapIn "virtmgmt.msc"
        }

        "55" {
            Start-MmcTool -Name "DFS-Verwaltung" -SnapIn "dfsmgmt.msc"
        }

        "80" {
            Get-WindowsLapsPassword
        }

        "0" {
            Write-Host ""
            Write-Host "Admin-Toolbox wird beendet." -ForegroundColor Cyan
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

$AdminCredential = $null

if ($SecureAdminPassword) {
    $SecureAdminPassword.Dispose()
    $SecureAdminPassword = $null
}

Write-Host ""
Write-Host "Programm beendet."
Start-Sleep -Seconds 1
