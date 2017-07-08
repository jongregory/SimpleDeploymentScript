param (
    [string]$version = $(throw "-version to deploy is required."),
    [string]$environment = $(throw "-environment to deploy is required. (dev/uat/prod)")
 )

 function New-Symlink {
    <#
    .SYNOPSIS
        Creates a symbolic link.
    #>
    param (
        [Parameter(Position=0, Mandatory=$true)]
        [string] $Link,
        [Parameter(Position=1, Mandatory=$true)]
        [string] $Target
    )

    Write-Host "New-Symlink $Link to $Target"
    
    Invoke-MKLINK -Link $Link -Target $Target
}

function Invoke-MKLINK {
    <#
    .SYNOPSIS
        Creates a symbolic link.
    #>
    param (
        [Parameter(Position=0, Mandatory=$true)]
        [string] $Link,
        [Parameter(Position=1, Mandatory=$true)]
        [string] $Target
    )
    
    # Resolve the paths incase a relative path was passed in.
    $Link = (Force-Resolve-Path $Link)
    $Target = (Force-Resolve-Path $Target)

    # Ensure target exists.
    if (-not(Test-Path $Target)) {
        throw "Target does not exist.`nTarget: $Target"
    }

    # Ensure link does not exist.
    if (Test-Path $Link) {
        Write-Host "A file or directory already exists at the link path.`nLink: $Link"
        return
    }

    $isDirectory = (Get-Item $Target).PSIsContainer

    # Capture the MKLINK output so we can return it properly.
    # Includes a redirect of STDERR to STDOUT so we can capture it as well.
    $output = cmd /c mklink /D `"$Link`" `"$Target`" 2>&1
    
    Write-Host "output : $output"
    if ($lastExitCode -ne 0) {
        Write-Host "MKLINK failed. Exit code: $lastExitCode`n$output"
        throw "MKLINK failed. Exit code: $lastExitCode`n$output"
    }
    else {
        Write-Output $output
    }
}

function Force-Resolve-Path {
    <#
    .SYNOPSIS
        Calls Resolve-Path but works for files that don't exist.
    .REMARKS
        From http://devhawk.net/2010/01/21/fixing-powershells-busted-resolve-path-cmdlet/
    #>
    param (
        [string] $FileName
    )
    
    $FileName = Resolve-Path $FileName -ErrorAction SilentlyContinue `
                                       -ErrorVariable _frperror
    if (-not($FileName)) {
        $FileName = $_frperror[0].TargetObject
    }
    
    return $FileName
}

function createJunctionLink($junctionLinkName, $junctionTargetName)
{
    $symLink = join-path -path $physicalPath -childpath $junctionLinkName
    $junctionFolder = join-path -path $junctionLinkFolder -childpath $junctionTargetName

    if ((Test-Path $symLink  -PathType Container )){
        Remove-Item $symLink  -Force -Recurse
    }
    New-Symlink $symLink $junctionFolder
}

function formatWriteHost($message){
     write-output $message
     write-output ' '
}

function readConfigFile($configSetting){
    $tmp = $h.Get_Item($configSetting)
    return $tmp
}



#Start of the Main Script

formatWriteHost "Website Deployment Script" 
formatWriteHost "Deploying Version $version" 
formatWriteHost "To Environment $environment" 

# Read the configuration file
$configFileName = $environment + "-deployment.config"
$configFilePath = join-path -path (Get-Location) -childpath $configFileName

formatWriteHost "Reading configuration file $configFilePath" 

if (-Not (Test-Path $configFilePath  -PathType Leaf )){
    $(throw "No configuration file is present")
}

Get-Content $configFilePath | foreach-object -begin {$h=@{}} -process { $k = [regex]::split($_,'='); if(($k[0].CompareTo("") -ne 0) -and ($k[0].StartsWith("[") -ne $True)) { $h.Add($k[0], $k[1]); formatWriteHost ($k[0] + "=" +$k[1])  } }

#Variable Definition

$stagingFolder = readConfigFile("StagingFolder")
$deploymentTarget = readConfigFile("DeploymentTarget")
$junctionLinkFolder = readConfigFile("JunctionLinkFolder")
$stagingVersionPath = join-path -path $stagingFolder -childpath $version
$targetVersionPath = join-path -path $deploymentTarget -childpath $version
$SiteFolder = readConfigFile("SiteFolder")
$website = readConfigFile("website")
$applicationPool = readConfigFile("applicationPool")
$physicalPath = join-path -path $targetVersionPath -childpath $SiteFolder
$envWebConfigFileName = "Web.Config." + $environment
$envWebConfigFullPath = join-path -path $physicalPath -childpath $envWebConfigFileName

# Copy the Website from Staging to the Target Deployment Folder

formatWriteHost "Copying the new release over"
formatWriteHost "Copying $stagingVersionPath to $targetVersionPath" 

if (-Not (Test-Path $targetVersionPath  -PathType Container )) {
    Copy-Item $stagingVersionPath $targetVersionPath -Recurse
}
else
{
    $(throw "Deployment Target Already Exists Aborting Deployment")
}

# Update IIS
Import-Module WebAdministration


Stop-Website $website
Stop-WebAppPool $applicationPool
Start-Sleep -s 5

Set-ItemProperty IIS:\Sites\$website -name physicalPath -value $physicalPath

#Delete the Web.Config

if ((Test-Path $physicalPath\Web.Config  -PathType Leaf )){
    formatWriteHost "Deleting the included $physicalPath\Web.Config" yellow
    Remove-Item $physicalPath\Web.Config  -Force
}


#Copy the Environment Web.config over

if ((Test-Path $physicalPath\Web.Config  -PathType Leaf )){
    Remove-Item $physicalPath\Web.Config  -Force
}


if ((Test-Path $envWebConfigFullPath  -PathType Leaf )){
    formatWriteHost "Copying $envWebConfigFileName to $physicalPath\Web.Config" 
    Copy-Item $envWebConfigFullPath $physicalPath\Web.Config  -Force
}
else
{
    $(throw "Environment Web.Config Does Not Exist!")
}

#Create Junction Links

createJunctionLink "medialibraries" "medialibraries"

Start-Website $website
Start-WebAppPool $applicationPool


formatWriteHost "Deployment Complete" 