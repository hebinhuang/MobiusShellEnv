# Copyright (c) Microsoft. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

<#
.SYNOPSIS
    Sets up and initialize the developer Shell Environment for Mobius
.DESCRIPTION
    Sets up the proper PATH and ENV to use Posh-Git shell and build environment
#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false)]
    [switch]$SetupEnv,

    [Parameter(Mandatory = $false)]
    [string] $repoRoot = "",

    [Parameter(Mandatory = $false)]
    [string] $repoName = "Mobius",

    [Parameter(Mandatory = $false)]
    [string] $githubUser = ""
)

process
{
    $latestVs = $null
    $Global:Root = $repoRoot

    function Create-ShortCut {
        try
        {
            $linkFileName = [IO.Path]::ChangeExtension($repoName, "lnk")
            $linkFile = [IO.Path]::Combine("$env:USERPROFILE\Desktop", $linkFileName)
            if (Test-Path $linkFile)
            {
                Write-Warning "The shortcut of $repoName already be created in your desktop. Skipped to create shortcut."
                return
            }

            # create ShortCut
            $wshshell = New-Object -ComObject WScript.Shell
            $shortCut = $wshShell.CreateShortCut($LinkFile)
            $shortCut.TargetPath = "cmd.exe"
            $shortCut.WorkingDirectory = $Root
            $shortCut.IconLocation = "PowerShell.exe"
            $shortCut.Arguments = "/k """"%$latestVs%\VsDevCmd.bat"" & PowerShell.exe -NoExit -Command "". $PSScriptRoot\Init.ps1 $Root"""""
            $shortCut.Save()

            # Change Elevation Flag
            $bytes = [IO.File]::ReadAllBytes($linkFile)
            $bytes[0x15] = $bytes[0x15] -bor 0x20 #set byte 21 (0x15) bit 6 (0x20) ON
            [IO.File]::WriteAllBytes($linkFile, $bytes)
        }
        catch
        {
            Write-Error "Failed to create shortcut for $repoName. The error was '$_'."
        }
    }

    function Create-Alias {
        # pull together all the args and then split on =
        $alias,$cmd = [string]::join(" ",$args).split("=",2) | % { $_.trim()}
        $func = @"
function global:Alias$alias {
    `$expr = ('$cmd ' + (( `$args | % { if (`$_.GetType().FullName -eq "System.String") { "``"`$(`$_.Replace('``"','````"').Replace("'","``'"))``"" } else { `$_ } } ) -join ' '))
    write-debug "Expression: `$expr"
    Invoke-Expression `$expr
}
"@
        write-debug "Defined function:`n$func"
        $func | iex
        $newAlias = Set-Alias -Name $alias -Value "Alias$alias" -Description "$cmd" -Option AllScope -scope Global -passThru
    }

    if ($SetupEnv) {
        if (!$repoRoot)
        {
            $repoRoot = Read-Host -Prompt "Enter directory path that will be the root of $repoName (e.g. c:\dev\$repoName)"
            $Global:Root = $repoRoot
        }

        # Check if the GitHub for Windows is installed
        if (!(Test-Path "$env:LOCALAPPDATA\GitHub"))
        {
            $Host.UI.WriteErrorLine("The development enviroment requires ""GitHub Desktop"" be installed. You can download from https://desktop.github.com/")
            return
        }

        # Check if Visual Studio in installed
        $vsEnvVars = (dir Env:).Name -match "VS[0-9]{1,3}COMNTOOLS"
        $latestVs = $vsEnvVars | Sort-Object | Select -Last 1
        if (!$latestVs)
        {
            $Host.UI.WriteErrorLine("The development enviroment requires ""Visual Studio"" be installed. Please install it first.")
            return
        }

        # Create shortcut for Mobius
        Create-ShortCut

        # Download build tool
        & $Root\build\localmode\downloadtools.ps1 build
        & $Root\build\tools\updatebuildtoolenv.cmd
        return
    }

    # Import Github Shell environment
    . (Resolve-Path "$env:LOCALAPPDATA\GitHub\shell.ps1")
    . (Resolve-Path "$env:github_posh_git\profile.example.ps1")
    cd $Root

    # Create aliases
    if (Test-Path "$PSScriptRoot\aliases")
    {
        Get-Content "$PSScriptRoot\aliases\*.txt" -Force | % {
            if ($_ -ne "") {
                Create-Alias $_
            }
        }
    }
}