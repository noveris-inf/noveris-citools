[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$Name
)

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"
Set-StrictMode -Version 2

Remove-Module Noveris.CITools -EA SilentlyContinue
Import-Module .\Noveris.CITools\Noveris.CITools.psm1

Invoke-CIProfile -Name $Name -Verbose -steps @{
    lint = @{
        Script = {
            Write-Information "linting script"
        }
    }
    clean = @{
        Script = {
            Write-Information "Clean script"
        }
    }
    build = @{
        Dependencies = $("lint")
        Script = {
            Write-Information "build post script"
        }
    }
    release = @{
        Script = {
            Write-Information "release post script"
        }
    }
    commit_release = @{
        Dependencies = $(
            "release",
            "lint",
            "clean:build:release")
        Script = {
            Write-Information "post release commit"
        }
    }
    pr = @{
        #Dependencies = $("build")
        Script = {
            Write-Information "pr post script"
        }
    }
    error1 = @{
        Dependencies = $("error2", "release")
    }
    error2 = @{
        Dependencies = $("error1", "build", "release")
    }
    error3 = @{
        Dependencies = $("missing")
    }
    error4 = @{
        Script = "test"
    }
}
