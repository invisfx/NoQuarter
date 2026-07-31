<#
.SYNOPSIS
    Creates shortcuts to txmake-sendto.cmd on the Desktop (as a drag-and-drop
    target) and in the Explorer "Send to" menu.

.DESCRIPTION
    Both shortcuts point directly at the .cmd file, which is what makes
    drag-and-drop work: Windows passes every dropped path to the batch file as
    %1, %2, %3 ... and the script loops over them.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install-shortcuts.ps1

.EXAMPLE
    # Custom menu name, Desktop only
    .\install-shortcuts.ps1 -Name "Make TX" -SkipSendTo

.EXAMPLE
    # Remove both shortcuts again
    .\install-shortcuts.ps1 -Uninstall
#>

[CmdletBinding()]
param(
    # The batch file to point at. Defaults to the copy sitting next to this script.
    [string] $ScriptPath = (Join-Path $PSScriptRoot 'txmake-sendto.cmd'),

    # Text shown under the icon and in the Send to menu.
    [string] $Name = 'Convert to .tx',

    # "path\to\file.dll,index" or a .ico file. Index meanings vary between
    # Windows builds, so adjust via Properties -> Change Icon if it looks odd.
    [string] $IconLocation = "$env:SystemRoot\System32\imageres.dll,68",

    [switch] $SkipDesktop,
    [switch] $SkipSendTo,
    [switch] $Uninstall
)

$ErrorActionPreference = 'Stop'

$desktopDir = [Environment]::GetFolderPath('Desktop')
$sendToDir  = [Environment]::GetFolderPath('SendTo')

$targets = @()
if (-not $SkipDesktop) { $targets += [pscustomobject]@{ Where = 'Desktop'; Path = Join-Path $desktopDir "$Name.lnk" } }
if (-not $SkipSendTo)  { $targets += [pscustomobject]@{ Where = 'Send to'; Path = Join-Path $sendToDir  "$Name.lnk" } }

if ($targets.Count -eq 0) {
    Write-Warning 'Both -SkipDesktop and -SkipSendTo were given; nothing to do.'
    return
}

if ($Uninstall) {
    foreach ($t in $targets) {
        if (Test-Path -LiteralPath $t.Path) {
            Remove-Item -LiteralPath $t.Path -Force
            Write-Host "Removed $($t.Where) shortcut: $($t.Path)"
        }
        else {
            Write-Host "No $($t.Where) shortcut found at: $($t.Path)"
        }
    }
    return
}

$ScriptPath = (Resolve-Path -LiteralPath $ScriptPath).ProviderPath
if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    throw "Not a file: $ScriptPath"
}

$shell = New-Object -ComObject WScript.Shell
try {
    foreach ($t in $targets) {
        $lnk = $shell.CreateShortcut($t.Path)
        $lnk.TargetPath       = $ScriptPath
        $lnk.WorkingDirectory = Split-Path -Parent $ScriptPath
        $lnk.Description      = 'Convert dropped images to RenderMan .tx textures'
        $lnk.WindowStyle      = 1   # normal window, so txmake output is visible

        if ($IconLocation) {
            try { $lnk.IconLocation = $IconLocation }
            catch { Write-Warning "Could not apply icon '$IconLocation'; using the default." }
        }

        $lnk.Save()
        Write-Host "Created $($t.Where) shortcut: $($t.Path)"
    }
}
finally {
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
}

Write-Host ''
Write-Host "Target: $ScriptPath"
Write-Host 'Drag images onto the Desktop shortcut, or use right-click > Send to.'
