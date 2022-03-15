[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $false)]
    [Hashtable] $DynParameters,

    [Parameter(Mandatory = $false)]
    [string] $AzureAdminUpn,

    [Parameter(Mandatory = $false)]
    [string] $AzureAdminPassword,

    [Parameter(Mandatory = $false)]
    [string] $domainJoinPassword,
    
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string[]] $Apps = @('Mozilla.Firefox', '7zip.7zip', 'Foxit.FoxitReader', 'Notepad++.Notepad++')
)

#####################################

##########
# Helper #
##########
#region Functions
function LogInfo($message) {
    Log "Info" $message
}

function LogError($message) {
    Log "Error" $message
}

function LogSkip($message) {
    Log "Skip" $message
}
function LogWarning($message) {
    Log "Warning" $message
}

function Log {

    <#
    .SYNOPSIS
   Creates a log file and stores logs based on categories with tab seperation

    .PARAMETER category
    Category to put into the trace

    .PARAMETER message
    Message to be loged

    .EXAMPLE
    Log 'Info' 'Message'

    #>

    Param (
        $category = 'Info',
        [Parameter(Mandatory = $true)]
        $message
    )

    $date = get-date
    $content = "[$date]`t$category`t`t$message`n"
    Write-Verbose "$content" -verbose

    if (! $script:Log) {
        $File = Join-Path $env:TEMP "log.log"
        Write-Error "Log file not found, create new $File"
        $script:Log = $File
    }
    else {
        $File = $script:Log
    }
    Add-Content $File $content -ErrorAction Stop
}

function Set-Logger {
    <#
    .SYNOPSIS
    Sets default log file and stores in a script accessible variable $script:Log
    Log File name "executionCustomScriptExtension_$date.log"

    .PARAMETER Path
    Path to the log file

    .EXAMPLE
    Set-Logger
    Create a logger in
    #>

    Param (
        [Parameter(Mandatory = $true)]
        $Path
    )

    # Create central log file with given date

    $date = Get-Date -UFormat "%Y-%m-%d %H-%M-%S"

    $scriptName = (Get-Item $PSCommandPath ).Basename
    $scriptName = $scriptName -replace "-", ""

    Set-Variable logFile -Scope Script
    $script:logFile = "executionCustomScriptExtension_" + $scriptName + "_" + $date + ".log"

    if ((Test-Path $path ) -eq $false) {
        $null = New-Item -Path $path -type directory
    }

    $script:Log = Join-Path $path $logfile

    Add-Content $script:Log "Date`t`t`tCategory`t`tDetails"
}
#endregion

Set-Logger "C:\WindowsAzure\Logs\Plugins\Microsoft.Compute.CustomScriptExtension\executionLog\winget" # inside "executionCustomScriptExtension_$scriptName_$date.log"

function Test-WinGet
{
    $appPackage = Get-AppPackage -name "Microsoft.DesktopAppInstaller"
    
    if ($appPackage)
    {
        return $true
    }

    return $false
}

function Install-WinGet
{
	if (-not (Test-WinGet))
	{
        LogInfo("Installing WinGet and dependencies")
        Add-AppxPackage "$PSScriptRoot\Microsoft.UI.Xaml.2.7_7.2109.13004.0_x64__8wekyb3d8bbwe.appx"
        Add-AppxPackage "$PSScriptRoot\Microsoft.VCLibs.140.00.UWPDesktop_14.0.30704.0_x64__8wekyb3d8bbwe.appx"
        Add-AppxPackage "$PSScriptRoot\Microsoft.DesktopAppInstaller_2021.1207.634.0_neutral___8wekyb3d8bbwe.msixbundle"
	}
    else
    {
        LogInfo("WinGet is already installed")
    }
}

function Remove-WinGet
{
    $oldAppPackage = Get-AppPackage -Name "Microsoft.DesktopAppInstaller"

    if ($null -ne $oldAppPackage)
    {
        LogInfo("Removing old version of DesktopAppInstaller - $($oldAppPackage.Version)")
        Remove-AppPackage $oldAppPackage
    }
}

# Remove any version if already installed
Remove-WinGet
Install-WinGet

if (-not (Test-WinGet))
{
	LogError("winget could not be installed")
    throw "winget could not be installed"
}

foreach ($app in $apps)
{
    $listApp = winget list --exact -q $app

    if (![string]::Join("", $listApp).Contains($app))
    {
        LogInfo("Installing $app")
        winget install -e -h --accept-source-agreements --accept-package-agreements --id $app
    }
    else
    {
        LogInfo("$app is already installed, skipping")
    }
}

LogInfo("Finished installing $($apps.Count) app(s)")