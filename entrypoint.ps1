<#
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$Profile,

    [Parameter(Mandatory=$false)]
    [switch]$UseLocalTools = $false
)

################
# Global settings
$InformationPreference = "Continue"
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

################
# Modules
Write-Information "Install/Update/Import ModuleMgmt"
Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
Remove-Module ModuleMgmt -EA SilentlyContinue
Install-Module ModuleMgmt -Scope CurrentUser -EA SilentlyContinue
Update-Module ModuleMgmt -Scope CurrentUser -EA SilentlyContinue
Import-Module ModuleMgmt

Write-Information "Install/Import CITools"
Remove-Module CITools -EA SilentlyContinue
if ($UseLocalTools)
{
    Import-Module ./source/CITools/CITools.psm1
} else {
    Import-Module -Name CITools -RequiredVersion (Install-PSModuleWithSpec -Name CITools -Major 1 -Minor 0)
}

Import-Module -Name GitHubApiTools -RequiredVersion (Install-PSModuleWithSpec -Name GitHubApiTools -Major 1 -Minor 0)

########
# Capture version information
$version = @($Env:GITHUB_REF, "v0.1.0") | Select-ValidVersions -First -Required

Write-Information "Version:"
$version

########
# Build stage
Invoke-CIProfile -Name $Profile -Steps @{

    lint = @{
        Script = {
            Use-PowershellGallery
            Install-Module PSScriptAnalyzer -Scope CurrentUser
            Import-Module PSScriptAnalyzer
            $results = Invoke-ScriptAnalyzer -IncludeDefaultRules -Recurse .
            if ($null -ne $results)
            {
                $results
                Write-Error "Linting failure"
            }
        }
    }

    build = @{
        Script = {
            # Template PowerShell module definition
            Write-Information "Templating CITools.psd1"
            Format-TemplateFile -Template source/CITools.psd1.tpl -Target source/CITools/CITools.psd1 -Content @{
                __FULLVERSION__ = $version.PlainVersion
            }

            # Trust powershell gallery
            Write-Information "Setup for access to powershell gallery"
            Use-PowerShellGallery

            # Install any dependencies for the module manifest
            Write-Information "Installing required dependencies from manifest"
            Install-PSModuleFromManifest -ManifestPath source/CITools/CITools.psd1

            # Test the module manifest
            Write-Information "Testing module manifest"
            Test-ModuleManifest source/CITools/CITools.psd1

            # Import modules as test
            Write-Information "Importing module"
            Import-Module ./source/CITools/CITools.psm1
        }
    }

    pr = @{
        Dependencies = $("lint", "build")
    }

    latest = @{
        Dependencies = $("lint", "build")
    }

    release = @{
        Dependencies = $("build")
        Script = {
            $owner = "noveris-inf"
            $repo = "noveris-citools"

            $releaseParams = @{
                Owner = $owner
                Repo = $repo
                Name = ("Release " + $version.Tag)
                TagName = $version.Tag
                Draft = $false
                Prerelease = $version.IsPrerelease
                Token = $Env:GITHUB_TOKEN
            }

            Write-Information "Creating release"
            New-GithubRelease @releaseParams

            Publish-Module -Path ./source/CITools -NuGetApiKey $Env:NUGET_API_KEY
        }
    }
}
