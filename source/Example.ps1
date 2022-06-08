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
    lint = @{
        Chain1 = {
            Write-Information "linting script"
        }
    }

    clean = @{
        Chain1 = {
            Write-Information "Clean script"
        }
    }

    build = @{
        Chain1 = "lint", {
            Write-Information "build post script"
        }
    }

    build2 = @{
        Chain1 = "lint", {
            Write-Information "build post script"
        }
    }

    release = @{
        Chain1 = {
            Write-Information "release post script"
        }
    }

    commit_release = @{
        Chain1 = "lint"
        Chain2 = "clean", "build", "release", {
            Write-Information "post release commit"
        }
    }

    pr = @{
        #"build",
        Unordered = {
            Write-Information "pr post script"
        }
    }

    Base1 = @{
        Chain1 = {
            Write-Information "Base1"
        }
    }

    Base2 = @{
        Chain1 = {
            Write-Information "Base2"
        }
    }

    Base3 = @{
        Chain1 = {
            Write-Information "Base3"
        }
    }

    BaseCall = @{
        Chain1 = "Base1", {
            Write-Information "BaseCall1"
        }, "Base2"
        Chain2 = "Base1", {
            Write-Information "BaseCall2"
        }, "Base3"
    }

    error1 = @{
        Unordered = "error2", "release"
    }

    error2 = @{
        Unordered = "error1", "build", "release"
    }

    error3 = @{
        Unordered = "missing"
    }
}
