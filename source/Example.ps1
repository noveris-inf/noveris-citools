[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$Name
)

Remove-Module Noveris.CITools
Import-Module .\Noveris.CITools\Noveris.CITools.psm1

Invoke-CIProfile -Name $Name -Verbose -steps @{
    build = @{
        PreScript = {
            Write-Information "build pre script"
        }
        PostScript = {
            Write-Information "build post script"
        }
    }
    release = @{
        PreScript = {
            Write-Information "release pre script"
        }
        PostScript = {
            Write-Information "release post script"
        }
        Dependencies = @("build", "other")
    }
    pr = @{
        PreScript = {
            Write-Information "pr pre script"
        }
        PostScript = {
            Write-Information "pr post script"
        }
        Dependencies = @("build")
    }
    other = @{
        PreScript = {
            Write-Information "second pre script"
        }
        PostScript = {
            Write-Information "second post script"
        }
        Dependencies = @("build", "release")
    }
}
