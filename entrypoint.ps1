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
Write-Information "Install/Update/Import Noveris.ModuleMgmt"
Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
Remove-Module Noveris.ModuleMgmt -EA SilentlyContinue
Install-Module Noveris.ModuleMgmt -Scope CurrentUser -EA SilentlyContinue
Update-Module Noveris.ModuleMgmt -Scope CurrentUser -EA SilentlyContinue
Import-Module Noveris.ModuleMgmt

Write-Information "Install/Import Noveris.CITools"
Remove-Module Noveris.CITools -EA SilentlyContinue
if ($UseLocalTools)
{
    Import-Module ./source/Noveris.CITools/Noveris.CITools.psm1
} else {
    Import-Module -Name Noveris.CITools -RequiredVersion (Install-PSModuleWithSpec -Name Noveris.CITools -Major 0 -Minor 2)
}

########
# Capture version information
$version = @($Env:GITHUB_REF, "v0.1.0") | Select-ValidVersions -First -Required

Write-Information "Version:"
$version

########
# Build stage
Invoke-CIProfile -Name $Profile -Steps @{
    lint = @{
        PostScript = {
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
        PostScript = {
            # Template PowerShell module definition
            Write-Information "Templating Noveris.CITools.psd1"
            Format-TemplateFile -Template source/Noveris.CITools.psd1.tpl -Target source/Noveris.CITools/Noveris.CITools.psd1 -Content @{
                __FULLVERSION__ = $version.PlainVersion
            }

            # Trust powershell gallery
            Write-Information "Setup for access to powershell gallery"
            Use-PowerShellGallery

            # Install any dependencies for the module manifest
            Write-Information "Installing required dependencies from manifest"
            Install-PSModuleFromManifest -ManifestPath source/Noveris.CITools/Noveris.CITools.psd1

            # Test the module manifest
            Write-Information "Testing module manifest"
            Test-ModuleManifest source/Noveris.CITools/Noveris.CITools.psd1

            # Import modules as test
            Write-Information "Importing module"
            Import-Module ./source/Noveris.CITools/Noveris.CITools.psm1
        }
    }
    pr = @{
        Dependencies = @("lint", "build")
    }
    release = @{
        Dependencies = @("build")
        PostScript = {
            $owner = "noveris-inf"
            $repo = "Noveris.CITools"

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

            Publish-Module -Path ./source/Noveris.CITools -NuGetApiKey $Env:NUGET_API_KEY
        }
    }
}
