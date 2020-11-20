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
    [string] $ExecutableName = "Teams_windows_x64.msi"

    #[Parameter(Mandatory = $false)]
    #[ValidateNotNullOrEmpty()]
    #[string] $Switches = "/S /D=${Env:ProgramFiles(x86)}\Notepad++\"
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

function Install-MSI ($file, $logFile, $additionalArgs)
{
	$path = Join-Path $PSScriptRoot $file
	LogInfo("Installing $path")

	if ([string]::IsNullOrEmpty($logFile))
	{
		$dataStamp = Get-Date -Format "yyyyMMddTHHmmss"
		$logFile = '{0}-{1}.log' -f $file, $DataStamp
	}
	
    $arguments = @("/i", ('"{0}"' -f $path), "/qn", "/norestart", "/L*v", $logFile)
	
	if ($additionalArgs)
	{
		$arguments += $additionalArgs
	}
	
    Start-Process "msiexec.exe" -ArgumentList $arguments -Wait -NoNewWindow
}

Set-Logger "C:\WindowsAzure\Logs\Plugins\Microsoft.Compute.CustomScriptExtension\executionLog\Teams" # inside "executionCustomScriptExtension_$scriptName_$date.log"

LogInfo("Setting registry key Teams")
if ((Test-Path "HKLM:\Software\Microsoft\Teams") -eq $false) {
    New-Item -Path "HKLM:\Software\Microsoft\Teams" -Force
}
New-ItemProperty "HKLM:\Software\Microsoft\Teams" -Name "IsWVDEnvironment" -Value 1 -PropertyType DWord -Force
LogInfo("Set IsWVDEnvironment DWord to value 1 successfully.")

#Install-MSI "VC_redist.x64.exe" "C:\WindowsAzure\Logs\Plugins\Microsoft.Compute.CustomScriptExtension\executionLog\Teams\VC_redist_InstallLog.txt"
Install-MSI "MsRdcWebRTCSvc_HostSetup_1.0.2006.11001_x64.msi" "C:\WindowsAzure\Logs\Plugins\Microsoft.Compute.CustomScriptExtension\executionLog\Teams\MsRdcWebRTCSvc_HostSetup_InstallLog.txt"
Install-MSI $ExecutableName "C:\WindowsAzure\Logs\Plugins\Microsoft.Compute.CustomScriptExtension\executionLog\Teams\Teams_InstallLog.txt" @("ALLUSER=1", "ALLUSERS=1")

LogInfo("Install logs can be found in the InstallLog.txt file in this folder.")
LogInfo("Teams was successfully installed")
