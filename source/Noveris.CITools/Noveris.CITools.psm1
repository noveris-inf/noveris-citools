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
Function Set-CIStepDefinition
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [HashTable]$ScopeSteps,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$StepName,

        [Parameter(Mandatory=$false)]
        [AllowNull()]
        [ScriptBlock]$Script
    )

    process
    {
        # Add the step, if it doesn't exist
        if ($scopeSteps.Keys -notcontains $StepName)
        {
            $ScopeSteps[$StepName] = [PSCustomObject]@{
                Name = $StepName
                Script = $null
            }
        }

        # Update the script, if specified
        if ($PSBoundParameters.Keys -contains "Script")
        {
            $ScopeSteps[$StepName].Script = $Script
        }
    }
}

<#
#>
Function Set-CIStepDependencies
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [HashTable]$DependencyMap,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$StepName,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Dependencies,

        [Parameter(Mandatory=$false)]
        [switch]$MergeDependencies = $false
    )

    process
    {
        # Add the step, if it doesn't exist
        if ($DependencyMap.Keys -notcontains $StepName)
        {
            $DependencyMap[$StepName] = New-Object 'System.Collections.Generic.HashSet[string]'
        }

        # Update the dependencies, if specified
        if ($PSBoundParameters.Keys -contains "Dependencies")
        {
            # Clear the dependencies, if we're not merging
            if (!$MergeDependencies)
            {
                $DependencyMap[$StepName].Clear()
            }

            # Add the new dependencies
            $Dependencies | ForEach-Object {
                $DependencyMap[$StepName].Add($_) | Out-Null
            }
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
        $components = New-Object 'System.Collections.Generic.Stack[string]'

        # ScopeSteps represents the steps within scope and dependencies is a map
        # of step names to dependent steps
        $scopeSteps = @{}
        $dependencyMap = @{}

        # Find all of the steps that can be reached by the initial step (i.e. steps in scope)
        # and populate scopeSteps.
        $components.Push($Name)
        while ($components.Count -gt 0)
        {
            $stepName = $components.Pop()

            # Make sure we don't have empty content
            if ([string]::IsNullOrEmpty($stepName))
            {
                Write-Error "Found null entry in list"
                continue
            }

            # Check if this step exists
            if ($Steps.Keys -notcontains $stepName)
            {
                Write-Error "Missing step ($stepName) in definition"
            }

            # Check if we've processed this name before
            if ($scopeSteps.Keys -contains $stepName)
            {
                continue
            }

            # Ensure the step is defined in scopeSteps
            Set-CIStepDefinition -ScopeSteps $scopeSteps -StepName $stepName

            # Get the step associated with this name
            $step = [HashTable]($Steps[$stepName])

            # Validate Script, if it exists
            if ($step.Keys -contains "Script")
            {
                $stepScript = [ScriptBlock]($step["Script"])
                Set-CIStepDefinition -ScopeSteps $scopeSteps -StepName $stepName -Script $stepScript
            }

            # Validate dependencies, if they exist
            Set-CIStepDependencies -DependencyMap $dependencyMap -StepName $stepName
            if ($step.Keys -contains "Dependencies")
            {
                $step["Dependencies"] | ForEach-Object {
                    $dep = [string]$_

                    if ([string]::IsNullOrEmpty($dep)) {
                        return
                    }

                    # Use ":" to allow definition of a dependency chain with the current step dependent on
                    # the last entry in the chain
                    $split = $dep.Split(":")
                    $current = $split[0]

                    $components.Push($current)
                    for ($i = 1; $i -lt $split.Length; $i++)
                    {
                        $previous = $current
                        $current = $split[$i]

                        $components.Push($current)
                        Set-CIStepDependencies -DependencyMap $dependencyMap -StepName $current -Dependencies $($previous) -MergeDependencies
                    }

                    Set-CIStepDependencies -DependencyMap $dependencyMap -StepName $stepName -Dependencies $($current) -MergeDependencies
                }
            }
        }

        # Create an execution order
        $processedNames = New-Object 'System.Collections.Generic.HashSet[string]'
        $executionOrder = New-Object 'System.Collections.Generic.List[PSCustomObject]'
        Write-Verbose ("Dumping dependency map: " + ($dependencyMap | ConvertTo-Json))
        while ($scopeSteps.Count -gt 0)
        {
            # Find a step that has its dependencies met or has no dependencies
            $candidate = $null
            foreach ($key in $scopeSteps.Keys)
            {
                $step = $scopeSteps[$key]

                # Collect a list of blockers for this step
                if ($dependencyMap.Keys -notcontains $key)
                {
                    Write-Error "Missing dependencies for step: $key"
                }

                $blockers = $dependencyMap[$key] | Where-Object {
                    !$processedNames.Contains($_)
                }

                if (($blockers | Measure-Object).Count -gt 0)
                {
                    # Step has blockers, so can't be run yet
                    continue
                }

                # Step has no blockers, so could be scheduled here
                $candidate = $step
                break
            }

            # If we couldn't find anything, abort
            if ($null -eq $candidate)
            {
                $msg = "Possible cyclical dependencies. Unable to determine execution order."
                Write-Information $msg
                Write-Information ("Dumping dependency map: " + ($dependencyMap | ConvertTo-Json))
                Write-Error $msg
            }

            # Remove the step from the scope steps
            $scopeSteps.Remove($candidate.Name)

            # Add the step to the processed steps list
            $processedNames.Add($candidate.Name) | Out-Null

            # Add the item to the execution order
            $executionOrder.Add($candidate)
        }

        Write-Information ("Execution order: " + ($executionOrder | ForEach-Object { $_.Name } | Join-String -Separator ", "))

        foreach ($step in $executionOrder)
        {
            Write-Information ("******** Processing " + $step.Name)
            try {

                if ($null -ne $step.Script)
                {
                    & $step.Script *>&1 |
                        Format-RecordAsString -DisplaySummary |
                        Out-String -Stream
                }
                Write-Information ("******** Finished " + $step.Name)
                Write-Information ""
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
        $Script,

        [Parameter(Mandatory=$false)]
        [AllowNull()]
        $CmdArgs = $null,

        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [int[]]$ValidExitCodes = @(0),

        [Parameter(Mandatory=$false)]
        [switch]$IgnoreExitCode = $false,

        [Parameter(Mandatory=$false)]
        [switch]$NoRedirectStderr = $false
    )

    process
    {
        $global:LASTEXITCODE = 0
        if ($NoRedirectStderr)
        {
            & $Script $CmdArgs | Out-String -Stream
        } else {
            & $Script $CmdArgs 2>&1 | Out-String -Stream
        }
        $exitCode = $global:LASTEXITCODE

        # reset LASTEXITCODE
        $global:LASTEXITCODE = 0

        Write-Verbose "Script exited with code: $exitCode"
        if (!$IgnoreExitCode -and $ValidExitCodes -notcontains $exitCode)
        {
            Write-Error "Invalid exit code returned: $exitCode"
        }
    }
}
