
# ============================================================
# ADMIN-TOOLBOX
# ============================================================

$ErrorActionPreference = "Stop"


# ============================================================
# AUTOMATISCHES UPDATE DER ADMIN-TOOLBOX
# ============================================================

$UpdateFile = $null
$HelperPath = $null

try {

    # Nur bei gestarteter EXE ausführen
    $ExePath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

    if ([System.IO.Path]::GetFileName($ExePath) -ieq "Admin-Toolbox.exe") {

        # GitHub-Einstellungen
        $ApiUrl = "https://api.github.com/repos/tue-computer/Admin-Toolbox/contents/Admin-Toolbox.exe?ref=main"

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
            throw "Ungültige Datei-Informationen von GitHub erhalten."
        }

        # GitHub-Blob-Hash berechnen
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

            # Temporäre Update-Datei
            $UpdateFile = "$ExePath.update"

            if (Test-Path -LiteralPath $UpdateFile) {
                Remove-Item -LiteralPath $UpdateFile -Force
            }

            # Update herunterladen
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
                throw "Hash-Prüfung fehlgeschlagen. Das Update wird nicht installiert."
            }

            Write-Host "Download erfolgreich überprüft." -ForegroundColor Green
            Write-Host "Installiere Update..." -ForegroundColor Cyan

            # Prozess-ID der aktuellen EXE
            $ParentPid = [Diagnostics.Process]::GetCurrentProcess().Id

            # Pfade kodieren
            $UpdateFileEncoded = [Convert]::ToBase64String(
                [Text.Encoding]::UTF8.GetBytes($UpdateFile)
            )

            $ExePathEncoded = [Convert]::ToBase64String(
                [Text.Encoding]::UTF8.GetBytes($ExePath)
            )

            # Temporäres Hilfsskript
            $HelperPath = Join-Path $env:TEMP "AdminToolbox_Update_$ParentPid.ps1"

            $HelperScript = @'
$ParentPid = __PARENT_PID__
$UpdateFile = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__UPDATE_FILE__'))
$TargetExe = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__TARGET_EXE__'))

try {

    # Warten, bis die alte EXE beendet ist
    $ParentProcess = Get-Process -Id $ParentPid -ErrorAction SilentlyContinue

    if ($ParentProcess) {
        $ParentProcess.WaitForExit()
    }

    Start-Sleep -Seconds 2

    $BackupExe = "$TargetExe.bak"

    if (-not (Test-Path -LiteralPath $UpdateFile -PathType Leaf)) {
        throw "Update-Datei wurde nicht gefunden."
    }

    # Alte EXE sichern
    if (Test-Path -LiteralPath $TargetExe -PathType Leaf) {

        if (Test-Path -LiteralPath $BackupExe) {
            Remove-Item -LiteralPath $BackupExe -Force
        }

        [System.IO.File]::Move($TargetExe, $BackupExe)

        try {
            # Neue EXE installieren
            [System.IO.File]::Move($UpdateFile, $TargetExe)
        }
        catch {

            # Alte EXE wiederherstellen
            if (
                (Test-Path -LiteralPath $BackupExe) -and
                -not (Test-Path -LiteralPath $TargetExe)
            ) {
                [System.IO.File]::Move($BackupExe, $TargetExe)
            }

            throw
        }

        # Backup entfernen
        Remove-Item -LiteralPath $BackupExe -Force -ErrorAction SilentlyContinue
    }
    else {
        [System.IO.File]::Move($UpdateFile, $TargetExe)
    }

    # Neue Version starten
    Start-Process -FilePath $TargetExe -ErrorAction Stop

}
catch {

    $ErrorText = $_.Exception.Message

    Add-Type -AssemblyName System.Windows.Forms

    [System.Windows.Forms.MessageBox]::Show(
        "Das Update konnte nicht installiert werden:`n`n$ErrorText",
        "Admin-Toolbox - Updatefehler",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}
finally {

    # Übrig gebliebene Update-Datei entfernen
    if (Test-Path -LiteralPath $UpdateFile) {
        Remove-Item -LiteralPath $UpdateFile -Force -ErrorAction SilentlyContinue
    }

    # Übrig gebliebenes Backup entfernen
    if (Test-Path -LiteralPath "$TargetExe.bak") {
        Remove-Item -LiteralPath "$TargetExe.bak" -Force -ErrorAction SilentlyContinue
    }

    # Hilfsskript selbst löschen
    $OwnScript = $MyInvocation.MyCommand.Path

    if ($OwnScript -and (Test-Path -LiteralPath $OwnScript)) {
        Remove-Item -LiteralPath $OwnScript -Force -ErrorAction SilentlyContinue
    }
}
'@

            $HelperScript = $HelperScript.Replace('__PARENT_PID__', [string]$ParentPid)
            $HelperScript = $HelperScript.Replace('__UPDATE_FILE__', $UpdateFileEncoded)
            $HelperScript = $HelperScript.Replace('__TARGET_EXE__', $ExePathEncoded)

            # Hilfsskript speichern
            [System.IO.File]::WriteAllText(
                $HelperPath,
                $HelperScript,
                [System.Text.Encoding]::UTF8
            )

            $PowerShellExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"

            # Hilfsprozess starten
            $HelperProcess = Start-Process `
                -FilePath $PowerShellExe `
                -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$HelperPath`"" `
                -WindowStyle Hidden `
                -PassThru `
                -ErrorAction Stop

            if (-not $HelperProcess) {
                throw "Der Update-Hilfsprozess konnte nicht gestartet werden."
            }

            # Alte EXE beenden
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

    # Temporäre Dateien entfernen
    if ($UpdateFile -and (Test-Path -LiteralPath $UpdateFile)) {
        Remove-Item -LiteralPath $UpdateFile -Force -ErrorAction SilentlyContinue
    }

    if ($HelperPath -and (Test-Path -LiteralPath $HelperPath)) {
        Remove-Item -LiteralPath $HelperPath -Force -ErrorAction SilentlyContinue
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

        if (-not $UseADCredentials -or -not $SecureAdminPassword) {
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
    param(
        [string]$ComputerName
    )

    Clear-Host

    try {
        $CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name

        Write-Host "LAPS-Abfrage mit Windows-Benutzer: $CurrentUser" -ForegroundColor Yellow
        Write-Host ""

        Import-Module LAPS -ErrorAction Stop
        Get-Command Get-LapsADPassword -ErrorAction Stop | Out-Null

        Write-Host "Rufe LAPS-Kennwort für $ComputerName ab ..." -ForegroundColor Cyan

        $LapsResult = Get-LapsADPassword `
            -Identity $ComputerName `
            -AsPlainText `
            -ErrorAction Stop

        if (-not $LapsResult) {
            throw "Keine LAPS-Daten für $ComputerName gefunden."
        }

        Write-Host "LAPS-Abfrage erfolgreich!" -ForegroundColor Green
        $LapsResult | Format-List ComputerName, Account, Password, PasswordUpdateTime, ExpirationTimestamp
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
# ACTIVE DIRECTORY - DYNAMISCHE OU-AUSWAHL
# ============================================================

function Select-ADOrganizationalUnit {

    Import-Module ActiveDirectory -ErrorAction Stop

    # Bereits ermittelte Domäne verwenden
    $DomainDN = (Get-ADDomain -Identity $CurrentDomain -ErrorAction Stop).DistinguishedName

    # Feste Einstiegs-OU suchen
    $RootOU = Get-ADOrganizationalUnit `
        -Identity "OU=ORGANISATION,$DomainDN" `
        -ErrorAction Stop

    # Navigationspfad
    $Path = @($RootOU)

    while ($true) {

        $CurrentOU = $Path[-1]

        Clear-Host

        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host "              ACTIVE DIRECTORY OU-AUSWAHL" -ForegroundColor Cyan
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Domäne: $CurrentDomain" -ForegroundColor Yellow
        Write-Host ""

        Write-Host "Aktueller Pfad:" -ForegroundColor Cyan

        foreach ($Entry in $Path) {
            Write-Host "  \ $($Entry.Name)" -ForegroundColor Yellow
        }

        Write-Host ""
        Write-Host "------------------------------------------------------------"

        # Untergeordnete OUs dynamisch auslesen
        $OUs = @(
            Get-ADOrganizationalUnit `
                -Filter * `
                -SearchBase $CurrentOU.DistinguishedName `
                -SearchScope OneLevel `
                -ErrorAction Stop |
            Sort-Object Name
        )

        if ($OUs.Count -gt 0) {

            for ($i = 0; $i -lt $OUs.Count; $i++) {

                Write-Host "[$($i + 1)] $($OUs[$i].Name)" -ForegroundColor White
            }
        }
        else {
            Write-Host "Keine weiteren Unter-OUs vorhanden." -ForegroundColor Gray
        }

        Write-Host ""
        Write-Host "------------------------------------------------------------"
        Write-Host "[A] Diese OU inklusive Unter-OUs auswählen" -ForegroundColor Green
        Write-Host "[D] Nur diese OU auswählen" -ForegroundColor Green

        if ($Path.Count -gt 1) {
            Write-Host "[Z] Eine Ebene zurück" -ForegroundColor Yellow
        }

        Write-Host "[0] Abbrechen" -ForegroundColor Red
        Write-Host ""

        $Selection = (Read-Host "Auswahl").Trim()

        switch -Regex ($Selection) {

            '^0$' {
                return $null
            }

            '^[Aa]$' {

                return [PSCustomObject]@{
                    DistinguishedName = $CurrentOU.DistinguishedName
                    SearchScope       = "Subtree"
                    OUName            = $CurrentOU.Name
                }
            }

            '^[Dd]$' {

                return [PSCustomObject]@{
                    DistinguishedName = $CurrentOU.DistinguishedName
                    SearchScope       = "OneLevel"
                    OUName            = $CurrentOU.Name
                }
            }

            '^[Zz]$' {

                if ($Path.Count -gt 1) {
                    $Path = @($Path | Select-Object -First ($Path.Count - 1))
                }
                else {
                    Write-Host "Du befindest dich bereits in der obersten OU." -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                }
            }

            '^\d+$' {

                $Index = [int]$Selection - 1

                if ($Index -ge 0 -and $Index -lt $OUs.Count) {

                    # Eine Ebene tiefer navigieren
                    $Path += $OUs[$Index]
                }
                else {
                    Write-Host "Ungültige Auswahl!" -ForegroundColor Red
                    Start-Sleep -Seconds 1
                }
            }

            default {
                Write-Host "Ungültige Auswahl!" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }
}

# ============================================================
# REMOTE-GPUPDATE
# EINZEL-PC / MEHRERE PCS / OU / GESAMTE DOMÄNE
# PARALLELE AUSFÜHRUNG
# ============================================================

function Invoke-RemoteGPUpdate {

    Clear-Host

    $Credential = $null
    $RemoteJob = $null

    try {

        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host "             ZENTRALES GROUP POLICY UPDATE" -ForegroundColor Cyan
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Domäne: $CurrentDomain" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "ZIELAUSWAHL" -ForegroundColor Cyan
        Write-Host "------------------------------------------------------------"
        Write-Host "[1] Einzelnen PC aktualisieren"
        Write-Host "[2] Mehrere PCs manuell eingeben"
        Write-Host "[3] Computer aus Active Directory OU auswählen"
        Write-Host "[4] Alle Computer der Domäne aktualisieren"
        Write-Host ""
        Write-Host "[0] Zurück"
        Write-Host ""

        $TargetChoice = Read-Host "Auswahl"

        $TargetComputers = @()

        switch ($TargetChoice) {

            # ------------------------------------------------
            # EINZELNER PC
            # ------------------------------------------------

            "1" {

                $TargetPC = (Read-Host "Computername").Trim()

                if ([string]::IsNullOrWhiteSpace($TargetPC)) {
                    throw "Kein Computername angegeben."
                }

                $TargetComputers = @($TargetPC)
            }

            # ------------------------------------------------
            # MEHRERE PCS MANUELL
            # ------------------------------------------------

            "2" {

                Write-Host ""
                Write-Host "Mehrere Computer kommasepariert eingeben." -ForegroundColor Cyan
                Write-Host "Beispiel: PC01, PC02, PC03"
                Write-Host ""

                $InputPCs = Read-Host "Computer"

                $TargetComputers = @(
                    $InputPCs -split '[,;]' |
                    ForEach-Object { $_.Trim() } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                )
            }

            # ------------------------------------------------
            # ACTIVE DIRECTORY OU-AUSWAHL
            # ------------------------------------------------

            "3" {

                $SelectedOU = Select-ADOrganizationalUnit

                if (-not $SelectedOU) {
                    return
                }

                Write-Host ""
                Write-Host "Lese Computer aus der ausgewählten OU..." -ForegroundColor Cyan

                Import-Module ActiveDirectory -ErrorAction Stop

                $TargetComputers = @(
                    Get-ADComputer `
                        -SearchBase $SelectedOU.DistinguishedName `
                        -SearchScope $SelectedOU.SearchScope `
                        -Filter 'Enabled -eq $true' `
                        -ErrorAction Stop |
                    Select-Object -ExpandProperty Name
                )

                Write-Host ""
                Write-Host "Ausgewählte OU: $($SelectedOU.OUName)" -ForegroundColor Yellow
            }

            # ------------------------------------------------
            # GESAMTE DOMÄNE
            # ------------------------------------------------

            "4" {

                Write-Host ""
                Write-Host "Lese alle aktivierten Domänencomputer..." -ForegroundColor Cyan

                Import-Module ActiveDirectory -ErrorAction Stop

                $DomainDN = (Get-ADDomain -Identity $CurrentDomain).DistinguishedName

                $TargetComputers = @(
                    Get-ADComputer `
                        -SearchBase $DomainDN `
                        -SearchScope Subtree `
                        -Filter 'Enabled -eq $true' `
                        -ErrorAction Stop |
                    Select-Object -ExpandProperty Name
                )
            }

            "0" {
                return
            }

            default {
                throw "Ungültige Auswahl."
            }
        }

        # ----------------------------------------------------
        # ZIELCOMPUTER PRÜFEN
        # ----------------------------------------------------

        $TargetComputers = @(
            $TargetComputers |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
        )

        if ($TargetComputers.Count -eq 0) {
            throw "Keine Computer für das GPUpdate gefunden."
        }

        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host "                  AUSGEWÄHLTE COMPUTER" -ForegroundColor Cyan
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host ""

        foreach ($PC in $TargetComputers) {
            Write-Host "  $PC" -ForegroundColor Gray
        }

        Write-Host ""
        Write-Host "Anzahl Computer: $($TargetComputers.Count)" -ForegroundColor Yellow

        # ----------------------------------------------------
        # BENUTZER FÜR REMOTE-GPUPDATE
        # GILT AUCH BEI EINEM EINZELNEN PC!
        # ----------------------------------------------------

        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host "             BENUTZER FÜR REMOTE-GPUPDATE" -ForegroundColor Cyan
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host "[1] Aktueller Server-Benutzer"
        Write-Host "[2] Hinterlegter AD-Benutzer"
        Write-Host "[3] Anderen Benutzer angeben"
        Write-Host "------------------------------------------------------------"

        $UserChoice = Read-Host "Auswahl"

        $InvokeParams = @{
            ErrorAction = "Stop"
        }

        switch ($UserChoice) {

            # Aktueller Windows-Benutzer

            "1" {

                $SelectedUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
            }

            # Hinterlegter AD-Benutzer

            "2" {

                if ($AdminCredential) {

                    $Credential = $AdminCredential
                    $InvokeParams.Credential = $Credential

                    $SelectedUser = $AdminUser
                }
                else {

                    $SelectedUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name

                    Write-Host ""
                    Write-Host "Kein separates AD-Konto hinterlegt." -ForegroundColor Yellow
                    Write-Host "Verwende angemeldeten Benutzer." -ForegroundColor Green
                }
            }

            # Anderer Benutzer

            "3" {

                $CustomUser = (Read-Host "Benutzername (DOMÄNE\Benutzer oder Benutzer@Domäne)").Trim()

                if ([string]::IsNullOrWhiteSpace($CustomUser)) {
                    throw "Kein Benutzer angegeben."
                }

                $Credential = Get-Credential `
                    -UserName $CustomUser `
                    -Message "Kennwort für Remote-GPUpdate eingeben"

                if (-not $Credential) {
                    throw "Keine Zugangsdaten angegeben."
                }

                $InvokeParams.Credential = $Credential
                $SelectedUser = $Credential.UserName
            }

            default {
                throw "Ungültige Benutzerauswahl."
            }
        }

        Write-Host ""
        Write-Host "Verwendeter Benutzer: $SelectedUser" -ForegroundColor Yellow

        # ----------------------------------------------------
        # PARALLELITÄT FESTLEGEN
        # ----------------------------------------------------

        $ThrottleLimit = 10

        # ----------------------------------------------------
        # REMOTE-SCRIPTBLOCK
        # ----------------------------------------------------

        $RemoteScriptBlock = {
            try {

                $GpUpdateExe = Join-Path $env:WINDIR "System32\gpupdate.exe"

                $GpOutput = & $GpUpdateExe /force 2>&1
                $GpExitCode = $LASTEXITCODE

                $OutputText = @(
                    $GpOutput | ForEach-Object { $_.ToString() }
                ) -join "`n"

                if ($GpExitCode -ne 0) {

                    [PSCustomObject]@{
                        Computer = $env:COMPUTERNAME
                        Status   = "Fehlgeschlagen"
                        Ausgabe  = $OutputText
                        Fehler   = "gpupdate.exe wurde mit Fehlercode $GpExitCode beendet."
                    }
                }
                else {

                    [PSCustomObject]@{
                        Computer = $env:COMPUTERNAME
                        Status   = "Erfolgreich"
                        Ausgabe  = $OutputText
                        Fehler   = ""
                    }
                }
            }
            catch {

                [PSCustomObject]@{
                    Computer = $env:COMPUTERNAME
                    Status   = "Fehlgeschlagen"
                    Ausgabe  = ""
                    Fehler   = $_.Exception.Message
                }
            }
        }

        # ----------------------------------------------------
        # PARALLELE AUSFÜHRUNG STARTEN
        # ----------------------------------------------------

        $InvokeParams.ComputerName = $TargetComputers
        $InvokeParams.ScriptBlock = $RemoteScriptBlock
        $InvokeParams.AsJob = $true
        $InvokeParams.ThrottleLimit = $ThrottleLimit

        $RemoteJob = Invoke-Command @InvokeParams

        Write-Host "GPUpdate wurde auf den Zielcomputern gestartet." -ForegroundColor Green
        Write-Host "Warte auf Rückmeldungen..." -ForegroundColor Cyan
        Write-Host ""

        # Auf alle Jobs warten
        Wait-Job -Job $RemoteJob | Out-Null

        # ----------------------------------------------------
        # ERGEBNISSE EINSAMMELN
        # ----------------------------------------------------

        $Results = @()

        foreach ($ChildJob in $RemoteJob.ChildJobs) {

            $RemoteResult = @(
                Receive-Job -Job $ChildJob -ErrorAction SilentlyContinue
            ) | Where-Object {
                $_.PSObject.Properties.Name -contains "Status"
            } | Select-Object -Last 1

            if ($RemoteResult) {

                $Results += $RemoteResult
            }
            else {

                $JobError = ""

                if ($ChildJob.JobStateInfo.Reason) {
                    $JobError = $ChildJob.JobStateInfo.Reason.Message
                }

                if ([string]::IsNullOrWhiteSpace($JobError)) {
                    $JobError = "Keine Rückmeldung erhalten. Verbindungsfehler oder Remote-Ausführung fehlgeschlagen."
                }

                $Results += [PSCustomObject]@{
                    Computer = $ChildJob.Location
                    Status   = "Fehlgeschlagen"
                    Ausgabe  = ""
                    Fehler   = $JobError
                }
            }
        }

        # ----------------------------------------------------
        # ABSCHLUSSAUSWERTUNG
        # ----------------------------------------------------

        $SuccessCount = @(
            $Results | Where-Object { $_.Status -eq "Erfolgreich" }
        ).Count

        $FailedCount = @(
            $Results | Where-Object { $_.Status -eq "Fehlgeschlagen" }
        ).Count

        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host "                 GPUPDATE ZUSAMMENFASSUNG" -ForegroundColor Cyan
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host ""

        $Results |
            Select-Object Computer, Status, Fehler |
            Format-Table -Wrap -AutoSize

        Write-Host ""
        Write-Host "Gesamt:          $($TargetComputers.Count)" -ForegroundColor Cyan
        Write-Host "Erfolgreich:     $SuccessCount" -ForegroundColor Green
        Write-Host "Fehlgeschlagen:  $FailedCount" -ForegroundColor Red

        Write-Host ""

        if ($FailedCount -eq 0) {
            Write-Host "Alle GPUpdates wurden erfolgreich ausgeführt!" -ForegroundColor Green
        }
        else {
            Write-Host "Einige Computer konnten nicht aktualisiert werden." -ForegroundColor Yellow
        }
    }
    catch {

        Write-Host ""
        Write-Host "GPUpdate fehlgeschlagen!" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Yellow
    }
    finally {

        if ($RemoteJob) {
            Remove-Job -Job $RemoteJob -Force -ErrorAction SilentlyContinue
        }

        # Nur lokal verwendete Zugangsdaten freigeben.
        # Das globale AdminCredential bleibt erhalten.

        if ($Credential -and $Credential -ne $AdminCredential) {
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

# Domäne und angemeldeten Benutzer automatisch ermitteln
$CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$CurrentDomain = (Get-CimInstance Win32_ComputerSystem).Domain
$CurrentUser = $CurrentIdentity.Name

Write-Host "Aktuelle Windows-Anmeldung:" -ForegroundColor Cyan
Write-Host "Benutzer: $CurrentUser" -ForegroundColor Yellow
Write-Host "Domäne:   $CurrentDomain" -ForegroundColor Yellow
Write-Host ""

# AD-Benutzer optional abfragen
Write-Host "Anmeldedaten für Active Directory eingeben. Leer lassen, um aktuell angemeldeten Benutzer zu verwenden." -ForegroundColor Gray
Write-Host "AD-Administrator (ohne Domäne): " -ForegroundColor Magenta -NoNewline
$AdminName = Read-Host

if ([string]::IsNullOrWhiteSpace($AdminName)) {

    # Angemeldeten Benutzer als AD-Benutzer übernehmen
    $AdminUser = $CurrentUser
    $AdminCredential = $null
    $SecureAdminPassword = $null

    Write-Host ""
    Write-Host "Kein separater AD-Administrator hinterlegt." -ForegroundColor Yellow
    Write-Host "Verwende angemeldeten Benutzer: $AdminUser" -ForegroundColor Green
}
else {

    $AdminUser = "$CurrentDomain\$($AdminName.Trim())"

    Write-Host "AD-Kennwort: " -ForegroundColor Magenta -NoNewline
    $SecureAdminPassword = Read-Host -AsSecureString

    $AdminCredential = [PSCredential]::new(
        $AdminUser,
        $SecureAdminPassword
    )

    Write-Host ""
    Write-Host "AD-Verwaltung wird mit folgendem Konto gestartet:" -ForegroundColor Green
    Write-Host "AD-Konto: $AdminUser" -ForegroundColor Green
}

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
        Write-Host " AD-Konto:     $AdminUser" -ForegroundColor Green
    }
    else {
        Write-Host " AD-Konto:     Aktueller Benutzer" -ForegroundColor Green
    }

    Write-Host " Server-Konto: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)" -ForegroundColor Green
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

    Write-Host "Bitte Auswahl treffen: " -ForegroundColor Magenta -NoNewline
    $Auswahl = Read-Host

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
                    Start-AdminProcess -Name "Server-Manager" `
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
            Write-Host ""
            Write-Host "DFS-VERWALTUNG STARTEN" -ForegroundColor Cyan
            Write-Host "------------------------------------------------------------"
            Write-Host "[1] Mit AD-Benutzer starten"
            Write-Host "[2] Mit aktuellem Server-Benutzer starten"
            Write-Host "------------------------------------------------------------"

            $DFSChoice = Read-Host "Auswahl"

            switch ($DFSChoice) {

                "1" {
                    Start-MmcTool -Name "DFS-Verwaltung" `
                        -SnapIn "dfsmgmt.msc" `
                        -UseADCredentials $true
                }

                "2" {
                    Start-MmcTool -Name "DFS-Verwaltung" `
                        -SnapIn "dfsmgmt.msc"
                }

                default {
                    Write-Host "Ungültige Auswahl!" -ForegroundColor Red
                    Start-Sleep -Seconds 1
                }
            }
        }

        "80" {
            $TargetPC = (Read-Host "PC-Name").Trim()

            if (-not [string]::IsNullOrWhiteSpace($TargetPC)) {
                Get-WindowsLapsPassword -ComputerName $TargetPC
            }
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
