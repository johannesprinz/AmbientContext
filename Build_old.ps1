#==============================================================
# SETUP FUNCTIONS used to define what to do with projects
#==============================================================
function Project{Param([Parameter(Position=0,Mandatory=$true)][String] $path)return [System.Tuple]::Create($path,"Project")}
function Nuget{Param([Parameter(Position=0,Mandatory=$true)][String] $path)return [System.Tuple]::Create($path,"Nuget")}
function Test{Param([Parameter(Position=0,Mandatory=$true)][String] $path)return [System.Tuple]::Create($path,"Test")}

#==============================================================
# SETUP (EDIT ME) used to define what projects package and test
# + Project - `restore` & `build` run but not `pack` to nuget
# + Nuget - `restore` & `build` run and nuget artifact created
# + Test - `restore` & `build` & `test` run but not `pack`
#==============================================================
$projects = @(
    (Nuget ".\src\AmbientContext"), 
    (Test ".\test\AmbientContext.Tests")
)

if (Test-Path -Path .\global.json)
{
    $conf = Get-Content -Path .\global.json -Raw | ConvertFrom-Json
    Write-Verbose "Using dotnet core version $($conf.sdk.version)"
}
else
{
    throw "No global.json found in project directory"
}

#==============================================================
# INSTALL of Dotnet CLI if it is not installed
#==============================================================
function EnsureDotnetCliInstalled{  
    [cmdletbinding()]
    param(
        [string]$dotnetCliInstallUri = 'https://raw.githubusercontent.com/dotnet/cli/rel/1.0.0/scripts/obtain/dotnet-install.ps1',
        [string]$dotnetVersion = $conf.sdk.version
    )
    if(-not (Get-Command "dotnet.exe" -errorAction SilentlyContinue)){
        'Installing dotnet cli from [{0}]' -f $dotnetCliInstallUri | Write-Verbose
        Invoke-WebRequest -Uri $dotnetCliInstallUri -UseBasicParsing -OutFile "$($env:TEMP)\dotnet-install.ps1"
        . "$($env:TEMP)\dotnet-install.ps1" -Version $dotnetVersion
        $env:Path += "$($env:Path);$($env:USERPROFILE)\AppData\Local\Microsoft\dotnet\"
    }
    else{
        'dotnet cli already loaded, skipping download' | Write-Verbose
    }

    # make sure it's loaded and throw if not
    if(-not (Get-Command "dotnet.exe" -errorAction SilentlyContinue)){
        throw ('Unable to install/load dotnet cli from [{0}]' -f $dotnetCliInstallUri)
    }
}

#==============================================================
# INSTALL of PsBuild if it is not installed
#==============================================================
function EnsurePsbuildInstalled{  
    [cmdletbinding()]
    param(
        [string]$psbuildInstallUri = 'https://raw.githubusercontent.com/ligershark/psbuild/master/src/GetPSBuild.ps1'
    )
    if(-not (Get-Command "Invoke-MsBuild" -errorAction SilentlyContinue)){
        'Installing psbuild from [{0}]' -f $psbuildInstallUri | Write-Verbose
        Invoke-WebRequest -Uri $psbuildInstallUri -UseBasicParsing -OutFile "$($env:TEMP)\psbuild-install.ps1"
        . "$($env:TEMP)\psbuild-install.ps1"
    }
    else{
        'psbuild already loaded, skipping download' | Write-Verbose
    }

    # make sure it's loaded and throw if not
    if(-not (Get-Command "Invoke-MsBuild" -errorAction SilentlyContinue)){
        throw ('Unable to install/load psbuild from [{0}]' -f $psbuildInstallUri)
    }
}

#==============================================================
# Execute commands and show error if fails
#==============================================================
function Exec  
{
    [CmdletBinding()]
    param(
        [Parameter(Position=0,Mandatory=1)][scriptblock]$cmd,
        [Parameter(Position=1,Mandatory=0)][string]$errorMessage = ($msgs.error_bad_command -f $cmd)
    )
    & $cmd
    if ($lastexitcode -ne 0) {
        throw ("Exec: " + $errorMessage)
    }
}

#==============================================================
# FORMAT the output
#==============================================================
function Yellow{Param([Parameter(Position=0,Mandatory=$true)][String] $text) Write-Host $text -ForegroundColor Yellow}
function Header{
    Param([Parameter(Position=0,Mandatory=$true)][String] $text) 
    Yellow "=============================================================="
    Yellow $text
    Yellow "=============================================================="
}

#==============================================================
# SCRIPT execution starts here
#==============================================================
if(Test-Path .\artifacts) { Remove-Item .\artifacts -Force -Recurse }

EnsureDotnetCliInstalled
EnsurePsbuildInstalled

# Package and Build
foreach ($project in $projects) {
    Header " RESTORING $project"
    Exec { & dotnet restore $project.Item1 }

    Header " BUILDING $project"
    Exec { & dotnet build $project.Item1 }
}

# Get Revision
Header " CHECK REVISION"
if  ($env:APPVEYOR_REPO_BRANCH -ne "Release")
{
    $revision = @{ $true = $env:APPVEYOR_BUILD_NUMBER; $false = 1 }[$env:APPVEYOR_BUILD_NUMBER -ne $NULL];
    $revision = "-CI{0:D4}" -f [convert]::ToInt32($revision, 10)
    "REVISION: " + $revision
    Exec {
        & ./tools/dnv --avpat "{{Same}}.{{Same}}.{{Same}}-pre{{UtcNow}}" --read .\src\AmbientContext\project.json --what av --verbose --write .\src\AmbientContext\project.json
    }
}


# Run tests
foreach ($project in $projects) {
    if($project.Item2 -eq "Test")
    {
        Header " RUNNING TESTS FOR $project"
        Exec { & dotnet test $project.Item1 -c Release }
    }
}

foreach ($project in $projects) {
    if($project.Item2 -eq "Nuget")
    {
        Header " PACKAGING FOR $project"
        Exec { & dotnet pack $project.Item1 -c Release -o .\artifacts --version-suffix=$revision } 
    }
}

Header "++++++++++++++++++++++++++++ DONE ++++++++++++++++++++++++++++"
Yellow "=============================================================="