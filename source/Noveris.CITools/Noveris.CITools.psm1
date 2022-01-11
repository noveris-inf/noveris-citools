<#
#>

#Requires -Modules @{"ModuleName"="Noveris.Logger";"RequiredVersion"="0.6.1"}
#Requires -Modules @{"ModuleName"="Noveris.Version";"RequiredVersion"="0.5.2"}
#Requires -Modules @{"ModuleName"="Noveris.GitHubApi";"RequiredVersion"="0.1.2"}

########
# Global settings
$InformationPreference = "Continue"
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

########
# Script variables
$script:BuildDirectories = New-Object 'System.Collections.Generic.HashSet[string]'

<#
#>
Function Use-EnvVar
{
    [CmdletBinding()]
    param(
        [Parameter(mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(mandatory=$false)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Default,

        [Parameter(mandatory=$false)]
        [ValidateNotNull()]
        [ScriptBlock]$Check
    )

    process
    {
        $val = $Default
        if (Test-Path "Env:\$Name")
        {
            $val = (Get-Item "Env:\$Name").Value
        } elseif ($PSBoundParameters.keys -notcontains "Default")
        {
            Write-Error "Missing environment variable ($Name) and no default specified"
        }

        if ($PSBoundParameters.keys -contains "Check")
        {
            $ret = $val | ForEach-Object -Process $Check
            if (!$ret)
            {
                Write-Error "Source string (${Name}) failed validation"
                return
            }
        }

        $val
    }
}

<#
#>
Function Assert-SuccessExitCode
{
	[CmdletBinding()]
	param(
		[Parameter(mandatory=$true)]
		[ValidateNotNull()]
		[int]$ExitCode,

		[Parameter(mandatory=$false)]
		[ValidateNotNull()]
		[int[]]$ValidCodes = @(0)
	)

	process
	{
		if ($ValidCodes -notcontains $ExitCode)
		{
			Write-Error "Invalid exit code: ${ExitCode}"
		}
	}
}

<#
#>
Function Invoke-CIProfile
{
    [CmdletBinding()]
    param(
        [Parameter(mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(mandatory=$true)]
        [ValidateNotNull()]
        [HashTable]$Steps
    )

    process
    {
        $scripts = New-Object 'System.Collections.Generic.LinkedList[PSCustomObject]'
        $components = New-Object 'System.Collections.Stack'

        $processedNames = New-Object 'System.Collections.Generic.HashSet[string]'
        $components.Push($Name)
        while ($components.Count -gt 0)
        {
            $content = $components.Pop()

            # Make sure we don't have empty content
            if ($null -eq $content)
            {
                Write-Error "Found null entry in list"
                continue
            }

            switch ($content.GetType().FullName)
            {
                "System.String" {
                    $name = [string]$content
                    if ($Steps.Keys -notcontains $name)
                    {
                        Write-Error "Missing step ($name) in definition"
                    }

                    # Check if we've processed this name before
                    if ($processedNames.Contains($name))
                    {
                        Write-Verbose ("Dependency ({0}) has already been processed" -f $name)
                        continue
                    }
                    $processedNames.Add($name) | Out-Null

                    Write-Verbose "Validating step $name"
                    $step = [HashTable]($Steps[$name])

                    # Add post scripts
                    if ($step.Keys -contains "PostScript")
                    {
                        $components.Push([PSCustomObject]@{
                            Name = "postscript_$name"
                            Script = [ScriptBlock]($step["PostScript"])
                        })
                    }

                    # Add names to stack (in reverse)
                    if ($step.Keys -contains "Dependencies")
                    {
                        $list = ([string[]]($step["Dependencies"])) | ForEach-Object { $_ }
                        [Array]::Reverse($list)
                        $list | ForEach-Object { $components.Push($_) }
                    }

                    # Add pre scripts
                    if ($step.Keys -contains "PreScript")
                    {
                        $components.Push([PSCustomObject]@{
                            Name = "prescript_$name"
                            Script = [ScriptBlock]($step["PreScript"])
                        })
                    }

                    break
                }

                "System.Management.Automation.PSCustomObject" {
                    $scripts.Add($content)
                    break
                }

                default {
                    Write-Error "Unknown type found in list"
                    break
                }
            }
        }

        $executions = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($script in $scripts)
        {
            # Check if we've already run this script
            if ($executions.Contains($script.Name))
            {
                Write-Verbose ("Script ({0}) already run" -f $script.Name)
                continue
            }

            Write-Information ("******** Processing " + $script.Name)
            try {

                & $script.Script *>&1 |
                    Format-RecordAsString -DisplaySummary |
                    Out-String -Stream
                Write-Information ("******** Finished " + $script.Name)
                Write-Information ""

                # Add the script to prevent further executions
                $executions.Add($script.Name) | Out-Null
            } catch {
                $ex = $_

                # Display as information - Some systems don't show the exception properly
                Write-Information "Invoke-CIProfile failed with exception"
                Write-Information "Exception Information: $ex"
                Write-Information ("Exception is null?: " + ($null -eq $ex).ToString())

                Write-Information "Exception Members:"
                $ex | Get-Member

                Write-Information "Exception Properties: "
                $ex | Format-List -property *

                # rethrow exception
                throw $ex
            }
        }
    }
}

<#
#>
Function Format-TemplateFile
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Template,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Target,

        [Parameter(Mandatory=$true)]
        [Hashtable]$Content,

        [Parameter(Mandatory=$false)]
        [switch]$Stream = $false
    )

    process
    {
        $dirPath = ([System.IO.Path]::GetDirectoryName($Target))
        if (![string]::IsNullOrEmpty($dirPath)) {
            New-Item -ItemType Directory -Path $dirPath -EA Ignore
        }

        if (!$Stream)
        {
            $data = Get-Content $Template -Encoding UTF8 | Format-TemplateString -Content $Content
            $data | Out-File -Encoding UTF8 $Target
        } else {
            Get-Content $Template -Encoding UTF8 | Format-TemplateString -Content $Content | Out-File -Encoding UTF8 $Target
        }
    }
}

<#
#>
Function Format-TemplateString
{
    [OutputType('System.String')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$TemplateString,

        [Parameter(Mandatory=$true)]
        [Hashtable]$Content
    )

    process
    {
        $working = $TemplateString

        $Content.Keys | ForEach-Object { $working = $working.Replace($_, $Content[$_]) }

        $working
    }
}

<#
#>
Function Use-BuildDirectories
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
	[CmdletBinding()]
	param(
		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[AllowEmptyCollection()]
		[string[]]$Directories
	)

	process
	{
		$Directories | ForEach-Object { Use-BuildDirectory $_ }
	}
}

<#
#>
Function Use-BuildDirectory
{
    [CmdletBinding()]
    param(
        [Parameter(mandatory=$true,ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    process
    {
        New-Item -ItemType Directory $Path -EA Ignore | Out-Null

        Write-Information "Using build directory: ${Path}"
        if (!(Test-Path $Path -PathType Container)) {
            Write-Error "Target does not exist or is not a directory"
        }

        try {
            Get-Item $Path -Force | Out-Null
        } catch {
            Write-Error $_
        }

        $script:BuildDirectories.Add($Path) | Out-Null
    }
}

<#
#>
Function Clear-BuildDirectory
{
    [CmdletBinding()]
    param(
        [Parameter(mandatory=$true,ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    process
    {
        Use-BuildDirectory -Path $Path | Out-Null
        Write-Information "Clearing directory: ${Path}"
        Get-ChildItem -Path $Path | ForEach-Object { Remove-Item -Path $_.FullName -Recurse -Force }
    }
}

<#
#>
Function Clear-BuildDirectories
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
	[CmdletBinding()]
	param(
	)

	process
	{
        Write-Information "Clearing build directories"
        Get-BuildDirectories
        Get-BuildDirectories | ForEach-Object { Clear-BuildDirectory $_ }
	}
}

<#
#>
Function Get-BuildDirectories
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    [CmdletBinding()]
    param(
    )

    process
    {
        $script:BuildDirectories | ForEach-Object { $_ }
    }
}

<#
#>
Function Invoke-Native
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ScriptBlock]$Script,

        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [int[]]$ValidExitCodes = @(0),

        [Parameter(Mandatory=$false)]
        [switch]$IgnoreExitCode = $false,

        [Parameter(Mandatory=$false)]
        [switch]$RedirectStderr = $false
    )

    process
    {
        $LASTEXITCODE = 0
        if ($RedirectStderr)
        {
            & $Script 2>&1 | Out-String -Stream
        } else {
            & $Script | Out-String -Stream
        }
        $exitCode = $LASTEXITCODE

        if (!$IgnoreExitCode -and $ValidExitCodes -notcontains $exitCode)
        {
            Write-Error "Invalid exit code returned: $exitCode"
        }
    }
}
