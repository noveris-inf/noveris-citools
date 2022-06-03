[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$Name
)

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"
Set-StrictMode -Version 2

Remove-Module CITools -EA SilentlyContinue
Import-Module .\CITools\CITools.psm1

Invoke-CIProfile -Name $Name -Verbose -steps @{
    lint = @(
        {
            Write-Information "linting script"
        }
    )

    clean = @(
        {
            Write-Information "Clean script"
        }
    )

    build = @(
        "lint",
        {
            Write-Information "build post script"
        }
    )

    release = @(
        {
            Write-Information "release post script"
        }
    )

    commit_release = @(
        "lint",
        @("clean", "build", "release", {
            Write-Information "post release commit"
        })
    )

    pr = @(
        #"build",
        {
            Write-Information "pr post script"
        }
    )

    error1 = @(
        "error2",
        "release"
    )

    error2 = @(
        "error1",
        "build",
        "release"
    )

    error3 = @(
        "missing"
    )

}
