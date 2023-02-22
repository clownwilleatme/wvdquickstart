[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Web

function Get-CWControlServerInfo
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [Uri]$Uri
    )

    $Builder = New-Object "System.UriBuilder" $Uri
    $Builder.Path = "/Script.ashx"
    $Info = @{}
    $UriString = $Builder.ToString()
    Write-Verbose "Fetching $UriString"
    $Response = Invoke-WebRequest -UseBasicParsing -Uri $UriString
    
    if ($Response.Content -match '\"h"\:\"(.+?)\"')
    {
        $Info.Host = $matches[1]
    }
    else
    {
        $Info.Host = $Builder.Host
    }

    if ($Response.Content -match '\"k"\:\"(.+?)\"')
    {
        $Info.PublicKey = $matches[1]
    }

    if ($Response.Content -match '\"instanceUrlScheme"\:\"sc-(.+?)\"')
    {
        $Info.InstanceId = $matches[1]
    }

    if ($Response.Content -match '\"p"\:(\d+)')
    {
        $Info.Port = $matches[1]
    }

    if ($Builder.Host.EndsWith("screenconnect.com"))
    {
        Write-Verbose "Finding Relay Uri from $Uri"
        $InstanceResponse = Invoke-WebRequest -UseBasicParsing $Uri 
        $InstanceID = $InstanceResponse.RawContent.Substring($InstanceResponse.RawContent.IndexOf("Instance=") + 9, 6)
        $RelayUri = "instance-$InstanceID-relay.screenconnect.com"    
        Write-Verbose $RelayUri
    }

    $Info.RelayUri = $RelayUri
    return (New-Object PSObject -Property $Info)
}

function Get-CWControlParams
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]
        [string]$CompanyName,
        [Parameter(Mandatory=$true)]
        [Uri]$HostName,
        [int]$Port = 443
    )

    $ControlUriBuilder = New-Object "System.UriBuilder" $HostName
    $ControlUriBuilder.Scheme = "https"

    if($Port)
    {
        $ControlUriBuilder.Port = $Port
    } else
    {
        if($ControlUriBuilder.Port -eq 80)
        {
            $ControlUriBuilder.Port = 443
        }
    }

    $ControlUri = $ControlUriBuilder.ToString()
    Write-Verbose "ControlUri: $ControlUri"
    $ControlInstanceInfo = Get-CWControlServerInfo -Uri $ControlUri
    $ServiceName = "ScreenConnect Client ($($ControlInstanceInfo.InstanceId))"

    $DesiredParameters = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
    $DesiredParameters['e'] = "Access"
    $DesiredParameters['y'] = "Guest"
    $DesiredParameters['h'] = $ControlInstanceInfo.Host

    if($ControlInstanceInfo.RelayUri)
    {
        Write-Host "Replacing Host with RelayUri: $($ControlInstanceInfo.RelayUri)"
        $DesiredParameters['h'] = $ControlInstanceInfo.RelayUri
        $DesiredParameters['t'] = ""
    }

    $DesiredParameters['p'] = $ControlInstanceInfo.Port
    $DesiredParameters['c'] = $CompanyName
    $DesiredParameters['k'] = $ControlInstanceInfo.PublicKey

    if (!$ControlInstanceInfo.PublicKey)
    {
        Write-Error "Unable to retrieve publickey from $HostName`:$Port"
        return $null
    }

    $Info = @{}
    $Info.Params = $DesiredParameters.ToString()
    $Info.ServiceName = $ServiceName
    $Info.ControlUriBuilder = $ControlUriBuilder
    return (New-Object PSObject -Property $Info)
}

function Test-CWControlInstalled
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [Uri] $HostName,
        [int] $Port = 443
    )

    $info = Get-CWControlParams -HostName $HostName -Port $Port
    $ServiceName = $info.ServiceName

    Write-Verbose "Checking for $ServiceName"
    $ControlService = Get-Service $ServiceName -ErrorAction SilentlyContinue

    if ($ControlService)
    {
        return $true
    }

    $ImagePath = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName" -Name ImagePath -ErrorAction SilentlyContinue | Foreach-Object { $_.ImagePath }
    
    if (!$ImagePath)
    {
        Write-Warning "Unable to find $ServiceName"
        return $false
    }

    $CWControlEncodedParameters = Invoke-Expression "echo $ImagePath" | Select-Object -Skip 1
    $CurrentParameters = [System.Web.HttpUtility]::ParseQueryString($CWControlEncodedParameters)
    $ParametersToTest = @('e','y','h','p','k')
    $DebugPreference = 'Continue'
    Write-Verbose "Testing parameters"
    $IncorrectParameters = $ParametersToTest | Where-Object {
        $CompareResult = [string]$CurrentParameters[$_] -like [string]$DesiredParameters[$_]  
        Write-Verbose "$([string]$CurrentParameters[$_]) -like $([string]$DesiredParameters[$_]): $CompareResult"
        return !$CompareResult
    }
        
    foreach($IncorrectParameter in $IncorrectParameters)
    {
        Write-Warning "'$($CurrentParameters[$IncorrectParameter])' should be '$($DesiredParameters[$IncorrectParameter])'"
    }
    return ($null -eq $IncorrectParameters -and $null -ne $ControlService -and $ControlService.Status -eq "Running")
}

function Install-CWControl
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string] $CompanyName,
        [Parameter(Mandatory=$true)]
        [Uri] $HostName,
        [int] $Port = 443
    )

    $info = Get-CWControlParams -CompanyName $CompanyName -HostName $HostName -Port $Port
    $ControlUriBuilder = $info.ControlUriBuilder

    $InstallerLogFile = [IO.Path]::GetTempFileName()
    $ControlUriBuilder.Path = "/Bin/ConnectWiseControl.ClientSetup.msi"
    $ControlUriBuilder.Query = $info.Params

    $InstallerUri = $ControlUriBuilder.ToString()
    $InstallerFile = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(),".msi")
    $Params = $info.Params
    Get-Package "ScreenConnect Client ($($ControlInstanceInfo.InstanceId))" -ErrorAction SilentlyContinue | Select-Object -First 1 | Uninstall-Package -Force

    Write-Verbose "Downloading CWControl from $InstallerUri to $InstallerFile"
    (New-Object System.Net.WebClient).DownloadFile($InstallerUri, $InstallerFile)
    $Arguments = @"
/c msiexec /i "$InstallerFile" /qn /norestart /l*v "$InstallerLogFile" REBOOT=REALLYSUPPRESS SERVICE_CLIENT_LAUNCH_PARAMETERS="$Params"
"@
    Write-Verbose "CWControl Arguments: $Arguments"
    Write-Verbose "CWControl InstallerLogFile: $InstallerLogFile"        
    
    $Process = Start-Process -Wait cmd -ArgumentList $Arguments -Passthru

    if ($Process.ExitCode -ne 0)
    {
        Get-Content $InstallerLogFile -ErrorAction SilentlyContinue | Select-Object -Last 100
    }
    
    Write-Verbose "CWControl Exit Code: $($Process.ExitCode)";
    $ControlService = Get-Service -Name $info.ServiceName

    if($ControlService.Status -ne "Running")
    {
        $ControlService | Start-Service -Passthru
    }
}