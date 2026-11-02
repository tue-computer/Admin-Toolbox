
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
# KONSOLENFENSTER DYNAMISCH AUF 80 % SETZEN
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

        $ComputerName = Read-Host "PC-Name"

        if ([string]::IsNullOrWhiteSpace($ComputerName)) {
            throw "Kein PC-Name angegeben."
        }

        $ComputerName = $ComputerName.Trim()

        Write-Host ""
        Write-Host "Rufe LAPS-Kennwort für $ComputerName ab ..." -ForegroundColor Cyan

        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

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
# BENUTZERWAHL:
# 1 = AKTUELLER SERVER-BENUTZER
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
    $SecurePassword = $null

    try {

        # Zielcomputer
        $TargetPC = (Read-Host "Ziel-PC").Trim()

        if ([string]::IsNullOrWhiteSpace($TargetPC)) {
            Write-Host "Kein Computername angegeben!" -ForegroundColor Red
            return
        }

        # Benutzerwahl
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
            ErrorAction  = "Stop"
            ScriptBlock  = {

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
                # Kein -Credential:
                # Invoke-Command verwendet den aktuellen Prozessbenutzer.

                $SelectedUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
                Write-Host ""
                Write-Host "Verbindung als Server-Benutzer: $SelectedUser" -ForegroundColor Yellow
            }

            "2" {
                if ([string]::IsNullOrWhiteSpace($AdminUser) -or
                    [string]::IsNullOrWhiteSpace($AdminPassword)) {

                    throw "Es wurde bei der Startkonfiguration kein AD-Konto mit Kennwort hinterlegt."
                }

                $SecurePassword = ConvertTo-SecureString $AdminPassword -AsPlainText -Force
                $Credential = [PSCredential]::new($AdminUser, $SecurePassword)

                $SelectedUser = $AdminUser
                $InvokeParams.Credential = $Credential

                Write-Host ""
                Write-Host "Verbindung als AD-Benutzer: $SelectedUser" -ForegroundColor Yellow
            }

            "3" {
                $CustomUser = (Read-Host "Benutzername (DOMÄNE\Benutzer oder Benutzer@Domäne)").Trim()

                if ([string]::IsNullOrWhiteSpace($CustomUser)) {
                    throw "Kein Benutzer angegeben."
                }

                $Credential = Get-Credential -UserName $CustomUser -Message "Kennwort für GPUpdate eingeben"

                if (-not $Credential) {
                    throw "Keine Zugangsdaten angegeben."
                }

                $SelectedUser = $Credential.UserName
                $InvokeParams.Credential = $Credential

                Write-Host ""
                Write-Host "Verbindung als eigener Benutzer: $SelectedUser" -ForegroundColor Yellow
            }

            default {
                Write-Host "Ungültige Auswahl!" -ForegroundColor Red
                return
            }
        }

        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host "Zielcomputer: $TargetPC" -ForegroundColor Yellow
        Write-Host "Benutzer:     $SelectedUser" -ForegroundColor Yellow
        Write-Host "============================================================" -ForegroundColor Cyan

        Write-Host ""
        $Confirm = Read-Host "GPUpdate jetzt ausführen? (J/N)"

        if ($Confirm -notmatch '^(J|JA)$') {
            Write-Host "Vorgang abgebrochen." -ForegroundColor Yellow
            return
        }

        Write-Host ""
        Write-Host "Verbinde mit $TargetPC ..." -ForegroundColor Cyan

        # Direkter Aufruf von gpupdate.exe auf dem Ziel-PC.
        # Kein GroupPolicy-Modul und kein zusätzlicher Invoke-GPUpdate-Aufruf.

        $RemoteResult = Invoke-Command @InvokeParams

        Write-Host ""
        foreach ($Line in $RemoteResult) {
            Write-Host $Line
        }

        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Green
        Write-Host "             GPUPDATE ERFOLGREICH AUSGEFÜHRT" -ForegroundColor Green
        Write-Host "============================================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Zielcomputer: $TargetPC" -ForegroundColor Yellow
        Write-Host "Benutzer:     $SelectedUser" -ForegroundColor Yellow
    }
    catch {

        Write-Host ""
        Write-Host "GPUPDATE FEHLGESCHLAGEN!" -ForegroundColor Red
        Write-Host ""
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Bitte WinRM, Firewall und Berechtigungen prüfen." -ForegroundColor Yellow
    }
    finally {
        $Credential = $null
        $SecurePassword = $null
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

$DomainInput = Read-Host "Domäne"

if ([string]::IsNullOrWhiteSpace($DomainInput)) {

    $AdminUser = ""
}
else {

    $DomainInput = $DomainInput.Trim()

    $AdminName = Read-Host "AD-Administrator"

    if ([string]::IsNullOrWhiteSpace($AdminName)) {
        Write-Host "Kein AD-Administrator angegeben!" -ForegroundColor Red
        Read-Host "Weiter mit Enter"
        exit
    }

    $AdminName = $AdminName.Trim()
    $AdminUser = "$DomainInput\$AdminName"

    $SecurePassword = Read-Host "Kennwort" -AsSecureString

    $BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)

    try {
        $AdminPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        $SecurePassword.Dispose()
    }

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

        # ACTIVE DIRECTORY

        "10" {
            Start-MmcTool "Benutzer und Computer" "dsa.msc" $true
        }

        "11" {
            Start-ADProcess "PowerShell" $PowerShellExe '-NoExit -Command "Import-Module ActiveDirectory"'
        }


        # DNS & DHCP

        "30" {

            $DnsServer = Read-Host "DNS-Server eingeben"

            if (-not [string]::IsNullOrWhiteSpace($DnsServer)) {

                $DnsServer = $DnsServer.Trim()
                $DnsPath = Join-Path $System32 "dnsmgmt.msc"

                Start-ADProcess `
                    -Name "DNS-Verwaltung" `
                    -File $MMC `
                    -Arguments "`"$DnsPath`" /computername $DnsServer"
            }
        }

        "31" {

            $DhcpServer = Read-Host "DHCP-Server eingeben"

            if (-not [string]::IsNullOrWhiteSpace($DhcpServer)) {

                $DhcpPath = Join-Path $System32 "dhcpmgmt.msc"

                Start-ADProcess `
                    -Name "DHCP-Verwaltung" `
                    -File $MMC `
                    -Arguments "`"$DhcpPath`" /ComputerName $DhcpServer"
            }
        }


        # GRUPPENRICHTLINIEN

        "40" {

            $GpoPath = Join-Path $System32 "gpmc.msc"

            Start-ADProcess `
                -Name "Gruppenrichtlinienverwaltung" `
                -File $MMC `
                -Arguments "`"$GpoPath`""
        }

        "41" {
            Invoke-RemoteGPUpdate
        }


        # SERVER

        "50" {

            $TargetPC = Read-Host "Ziel-PC eingeben"

            if (-not [string]::IsNullOrWhiteSpace($TargetPC)) {

                $SnapInPath = Join-Path $System32 "compmgmt.msc"
                $Arguments = "`"$SnapInPath`" /computer=$TargetPC"

                Start-Tool "Computerverwaltung" $MMC $Arguments
            }
        }

        "51" {

            $TargetPC = Read-Host "Ziel-PC"

            if (-not [string]::IsNullOrWhiteSpace($TargetPC)) {

                $EventViewerExe = Join-Path $System32 "eventvwr.exe"

                Start-Tool `
                    -Name "Ereignisanzeige" `
                    -File $EventViewerExe `
                    -Arguments $TargetPC
            }
        }

        "52" {
            Start-Tool "Server-Manager" (Join-Path $System32 "ServerManager.exe")
        }

        "53" {
            Start-MmcTool "Druckverwaltung" "printmanagement.msc"
        }

        "54" {
            Start-MmcTool "Hyper-V-Manager" "virtmgmt.msc"
        }

        "55" {
            Start-MmcTool "DFS-Verwaltung" "dfsmgmt.msc"
        }


        # SICHERHEIT

        "80" {
            Get-WindowsLapsPassword
        }


        # BEENDEN

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
