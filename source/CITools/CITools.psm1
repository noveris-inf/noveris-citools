<#
#>

########
# Global settings
$InformationPreference = "Continue"
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

########
# Script variables
$script:BuildDirectories = New-Object 'System.Collections.Generic.HashSet[string]'
$semVerPattern = "^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$"

<#
#>
Function Get-BuildNumber {
    [OutputType('System.Int64')]
    [CmdletBinding()]
    param(
    )

    process
    {
        $MinDate = New-Object DateTime -ArgumentList 1970, 1, 1
        [Int64]([DateTime]::Now - $MinDate).TotalDays
    }
}

<#
#>
Function Select-ValidVersions
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Source,

        [Parameter(Mandatory=$false)]
        [switch]$First = $false,

        [Parameter(Mandatory=$false)]
        [switch]$Required = $false
    )

    begin
    {
        $MatchFound = $false
    }

    process
    {
        if ([string]::IsNullOrEmpty($Source))
        {
            Write-Verbose "Null or empty version supplied"
            return
        }

        if ($MatchFound -and $First)
        {
            Write-Verbose "Ignoring source ($Source) valid version already identified and -First specified"
            return
        }

        Write-Verbose "Processing Version Source: ${Source}"
        $working = $Source

        # Strip any refs/tags/ reference at the beginning of the version source
        $tagBranch = "refs/tags/"
        if ($working.StartsWith($tagBranch))
        {
            Write-Verbose "Version starts with refs/tags format - Removing"
            $working = $working.Substring($tagBranch.Length)
        }

        # Save a copy of the raw version, minus the leading refs/tags, if it existed, as the tag
        $tag = $working

        # Leading 'v' should be stripped for SemVer processing
        if ($working.StartsWith("v"))
        {
            Write-Verbose "Version starts with 'v' - Removing"
            $working = $working.Substring(1)
        }

        # Save a copy of this content as the full version, which is the tag, minus any leading 'v'
        $fullVersion = $working

        # Check if we match the semver regex pattern
        # Regex used directly from semver.org
        if ($working -notmatch $semVerPattern)
        {
            Write-Verbose "Version string not in correct format. skipping"
            return
        }

        # Extract components of version string
        $major = [Convert]::ToInt32($Matches[1])
        $minor = [Convert]::ToInt32($Matches[2])
        $patch = [Convert]::ToInt32($Matches[3])
        $Prerelease = $Matches[4]
        $Buildmetadata = $Matches[5]

        # Make sure prerelease and buildmetadata are at least an empty string
        if ($null -eq $Prerelease) {
            $Prerelease = ""
        }

        if ($null -eq $Buildmetadata) {
            $Buildmetadata = ""
        }

        # Check if we are a prerelease version
        $IsPrerelease = $false
        if (![string]::IsNullOrEmpty($Prerelease))
        {
            $IsPrerelease = $true
        }

        # Version is valid - Write to output stream
        Write-Verbose "Version is valid"
        $result = [PSCustomObject]@{
            Raw = $Source
            Tag = $tag
            Major = $major
            Minor = $minor
            Patch = $patch
            FullVersion = $fullVersion
            Prerelease = $Prerelease
            Buildmetadata = $Buildmetadata
            BuildVersion = ("{0}.{1}.{2}.{3}" -f $major, $minor, $patch, (Get-BuildNumber))
            AssemblyVersion = "${major}.0.0.0"
            PlainVersion = ("{0}.{1}.{2}" -f $major, $minor, $patch)
            IsPrerelease = $IsPrerelease
        }

        Write-Verbose ($result | ConvertTo-Json)
        $result

        $MatchFound = $true
    }

    end
    {
        if ($Required -and !$MatchFound)
        {
            # throw error as we didn't find a valid version source
            Write-Error "Could not find a valid version source"
        }
    }
}

<#
#>
Function Format-RecordAsString
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline)]
        $Input,

        [Parameter(Mandatory=$false)]
        [switch]$DisplaySummary = $false,

        [Parameter(Mandatory=$false)]
        [switch]$RethrowError = $false
    )

    begin
    {
        $errors = 0
        $warnings = 0
    }

    process
    {
        $timestamp = [DateTime]::Now.ToString("yyyyMMdd HH:mm")

        if ([System.Management.Automation.InformationRecord].IsAssignableFrom($_.GetType()))
        {
            ("{0} (INFO): {1}" -f $timestamp, $_.ToString())
        }
        elseif ([System.Management.Automation.VerboseRecord].IsAssignableFrom($_.GetType()))
        {
            ("{0} (VERBOSE): {1}" -f $timestamp, $_.ToString())
        }
        elseif ([System.Management.Automation.ErrorRecord].IsAssignableFrom($_.GetType()))
        {
            $errors++
            ("{0} (ERROR): {1}" -f $timestamp, $_.ToString())
            $Input | Out-String -Stream | ForEach-Object {
                ("{0} (ERROR): {1}" -f $timestamp, $_.ToString())
            }

            if ($RethrowError)
            {
                throw $Input
            }
        }
        elseif ([System.Management.Automation.DebugRecord].IsAssignableFrom($_.GetType()))
        {
            ("{0} (DEBUG): {1}" -f $timestamp, $_.ToString())
        }
        elseif ([System.Management.Automation.WarningRecord].IsAssignableFrom($_.GetType()))
        {
            $warnings++
            ("{0} (WARNING): {1}" -f $timestamp, $_.ToString())
        }
        elseif ([string].IsAssignableFrom($_.GetType()))
        {
            ("{0} (INFO): {1}" -f $timestamp, $_.ToString())
        }
        else
        {
            # Don't do ToString() here as this breaks things like Format-Table that
            # don't convert to string properly. Out-String (below) will handle this for us.
            $Input
        }
    }

    end
    {
        # Summarise the number of errors and warnings, if required
        if ($DisplaySummary)
        {
            $timestamp = [DateTime]::Now.ToString("yyyyMMdd HH:mm")
            ("{0} (INFO): Warnings: {1}" -f $timestamp, $warnings)
            ("{0} (INFO): Errors: {1}" -f $timestamp, $errors)
        }
    }
}

<#
#>
Function Reset-LogFileState
{
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogPath,

        [Parameter(Mandatory=$false)]
        [int]$PreserveCount = 5,

        [Parameter(Mandatory=$false)]
        [int]$RotateSizeKB = 0
    )

    process
    {
        # Check if the target is a directory
        if (Test-Path -PathType Container $LogPath)
        {
            Write-Error "Target is a directory"
        }

        # Create the log file, if it doesn't exist
        if (!(Test-Path $LogPath))
        {
            Write-Verbose "Log Path doesn't exist. Attempting to create."
            if ($PSCmdlet.ShouldProcess($LogPath, "Create Log"))
            {
                New-Item -Type File $LogPath -EA SilentlyContinue | Out-Null
            } else {
                return
            }
        }

        # Get the attributes of the target log file
        $logInfo = Get-Item $LogPath
        $logSize = ($logInfo.Length/1024)
        Write-Verbose "Current log file size: $logSize KB"

        # Check the size of the log file and rotate if greater than
        # the desired maximum
        if ($logSize -gt $RotateSizeKB)
        {
            Write-Verbose "Rotation required due to log size"
            Write-Verbose "PreserveCount: $PreserveCount"

            # Shuffle all of the logs along
            [int]$count = $PreserveCount
            while ($count -gt 0)
            {
                # If count is 1, we're working on the active log
                if ($count -le 1)
                {
                    $source = $LogPath
                } else {
                    $source = ("{0}.{1}" -f $LogPath, ($count-1))
                }
                $destination = ("{0}.{1}" -f $LogPath, $count)

                # Check if there is an actual log to move and rename
                if (Test-Path -Path $source)
                {
                    Write-Verbose "Need to rotate $source"
                    if ($PSCmdlet.ShouldProcess($source, "Rotate"))
                    {
                        Move-Item -Path $source -Destination $destination -Force
                    }
                }

                $count--
            }

            # Create the log path, if it doesn't exist (i.e. was renamed/rotated)
            if (!(Test-Path $LogPath))
            {
                if ($PSCmdlet.ShouldProcess($LogPath, "Create Log"))
                {
                    New-Item -Type File $LogPath -EA SilentlyContinue | Out-Null
                } else {
                    return
                }
            }

            # Clear the content of the log path (only applies if no rotation was done
            # due to 0 PreserveCount, but the log is over the RotateSizeKB maximum)
            if ($PSCmdlet.ShouldProcess($LogPath, "Truncate"))
            {
                Clear-Content -Path $LogPath -Force
            }
        }
    }
}

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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
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
Function Add-CIStepDependency
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
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
        [string]$Dependency
    )

    process
    {
        # Add the step, if it doesn't exist
        if ($DependencyMap.Keys -notcontains $StepName)
        {
            $DependencyMap[$StepName] = New-Object 'System.Collections.Generic.HashSet[string]'
        }

        # Add the dependency
        if ($PSBoundParameters.Keys -contains "Dependency")
        {
            $DependencyMap[$StepName].Add($Dependency) | Out-Null
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
        # dependencyMap maps the step name to a set of dependencies that the step has accumulated
        $dependencyMap = @{}

        # scopeSteps represents all of the steps that have been reached from the initial step,
        # along with script blocks for any autogenerated step names
        $scopeSteps = @{}

        # Find all of the steps that can be reached by the initial step (i.e. steps in scope)
        # and populate scopeSteps.
        $components = New-Object 'System.Collections.Generic.Stack[string]'
        $components.Push($Name)
        while ($components.Count -gt 0)
        {
            $stepName = $components.Pop()

            # Make sure we don't have empty content
            if ([string]::IsNullOrEmpty($stepName))
            {
                Write-Error "Found null step name in list"
            }

            # Make sure the step name is formatted correctly
            if ($stepName -notmatch "^[a-zA-Z0-9_-]+$")
            {
                Write-Error "Step name ($stepName) has invalid characters. Should be [a-zA-Z0-9_-]+"
            }

            # Anchors for this step
            $beginAnchor = $stepName + ":begin"
            $endAnchor = $stepName + ":end"

            # Check if we've processed this name before
            # Check this before 'Steps.Keys' below as autogenerated steps
            # will appear in scopeSteps, but not Steps.Keys
            if ($scopeSteps.Keys -contains $beginAnchor)
            {
                continue
            }

            # Check if this step exists
            if ($Steps.Keys -notcontains $stepName)
            {
                Write-Error "Missing step ($stepName) in definition"
            }

            # Ensure the step is defined in scopeSteps to prevent reevaluating the step
            Set-CIStepDefinition -ScopeSteps $scopeSteps -StepName $beginAnchor
            Set-CIStepDefinition -ScopeSteps $scopeSteps -StepName $endAnchor

            # Add anchor dependencies for this step
            Add-CIStepDependency -DependencyMap $dependencyMap -StepName $beginAnchor
            Add-CIStepDependency -DependencyMap $dependencyMap -StepName $endAnchor -Dependency $beginAnchor

            # Iterate through all dependency entries for this step
            $Steps[$stepName].Keys | ForEach-Object {
                $key = $_
                $stepChain = $Steps[$stepName][$key]

                # Each entry can be a single string or ScriptBlock or a collection of
                # strings or ScriptBlocks
                # Collections are also treated as a chain of dependencies

                $previousDependency = $beginAnchor
                $stepChain | ForEach-Object {
                    $dependency = $_

                    switch ($dependency.GetType().FullName)
                    {
                        "System.Management.Automation.ScriptBlock" {
                            $script = $dependency
                            $dependency = ("{0}:script_{1}" -f $stepName, [Guid]::NewGuid().ToString())

                            # Add the step dependency, without any dependencies of it's own
                            Add-CIStepDependency -DependencyMap $dependencyMap -StepName $dependency

                            # Adding the scope step also means that the step won't be processed
                            # as a dependency in the main loop
                            Set-CIStepDefinition -ScopeSteps $scopeSteps -StepName $dependency -Script $script

                            # Add a dependency for this script on the previous dependency
                            Add-CIStepDependency -DependencyMap $dependencyMap -StepName $dependency -Dependency $previousDependency

                            # Scripts don't have a begin and end anchor, so just reference the script step name directly
                            $previousDependency = $dependency
                        }

                        "System.String" {
                            $dependencyBeginAnchor = ($dependency + ":begin")
                            $dependencyEndAnchor = ($dependency + ":end")

                            # Define a dependency for this step on the previous dependency
                            Add-CIStepDependency -DependencyMap $dependencyMap -StepName $dependencyBeginAnchor -Dependency $previousDependency

                            # This dependency should be evaluated in the main loop
                            $components.Push($dependency)

                            # The end anchor for this step should be the dependency for the next step
                            $previousDependency = $dependencyEndAnchor
                        }

                        default {
                            Write-Error ("Invalid type in step definition: " + $dependency.GetType().FullName)
                        }
                    }
                }

                # The current step end anchor should depend on the last dependency in the chain being completed
                Add-CIStepDependency -DependencyMap $dependencyMap -StepName $endAnchor -Dependency $previousDependency
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

<#
#>
Function Invoke-EnvironmentPlaybook
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$BaseDirectory = "deploy",

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$EnvName,

        [Parameter(Mandatory=$true)]
        [ValidateSet("diff", "apply")]
        [string]$Action,

        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [string[]]$Inventories = $(),

        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [string[]]$VaultFiles = $(),

        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [string[]]$OtherArgs
    )

    process
    {
        $plays = Get-ChildItem $BaseDirectory |
            Where-Object { $_.Attributes -like "*Directory*" -and $_.Name -match "^_exec_*" } |
            Sort-Object -Property Name |
            ForEach-Object {
                Write-Information ("Found exec directory: " + $_.FullName)
                Get-ChildItem $_.FullName |
                    Where-Object { $_.Name -match "^_${Action}_pre_.*\.(yml|yaml)$"} |
                    Sort-Object -Property Name

                Get-ChildItem $_.FullName |
                    Where-Object { $_.Name -match "^_${Action}_${EnvName}_.*\.(yml|yaml)$"} |
                    Sort-Object -Property Name

                Get-ChildItem $_.FullName |
                    Where-Object { $_.Name -match "^_${Action}_post_.*\.(yml|yaml)$"} |
                    Sort-Object -Property Name
            }

        Write-Information ""
        Write-Information "Plays to execute: "
        $plays | ForEach-Object { Write-Information $_ }

        $plays | ForEach-Object {
            Write-Information ""
            Write-Information ("Executing: " + $_.FullName)
            [string[]]$callArgs = $()

            # Add inventories
            if (($Inventories | Measure-Object).Count -gt 0)
            {
                $Inventories | ForEach-Object {
                    $callArgs += "-i"
                    $callArgs += $_
                }
            }

            # Add vaults
            if (($VaultFiles | Measure-Object).Count -gt 0)
            {
                $VaultFiles | ForEach-Object {
                    $callArgs += "--vault-password-file"
                    $callArgs += $_
                }
            }

            # Add Other Args
            if (($OtherArgs | Measure-Object).Count -gt 0)
            {
                $OtherArgs | ForEach-Object {
                    $callArgs += $_
                }
            }

            $callArgs += $_.FullName

            Write-Information ("Invoking ansible-playbook with args: " + ($callArgs -join " "))
            Invoke-Native ansible-playbook -CmdArgs $callArgs
        }
    }
}

<#
#>
Function Add-AZDEnvironmentPromotePR
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceBranch,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetBranch
    )

    process
    {
        Write-Information "Installing Azure Devops Extension"
        Invoke-Native "az" @("extension", "add", "--name", "azure-devops") -EA Continue

        Write-Information "PR creation"
        $result = Invoke-Native "az" @("repos", "pr", "list", "-s", $SourceBranch, "-t", $TargetBranch)
        if (($result | ConvertFrom-Json | Measure-Object).Count -eq 0)
        {
            Write-Information "No existing PR. Creating a new one."
            Invoke-Native "az" @("repos", "pr", "create", "--source-branch", $SourceBranch, "--target-branch", $TargetBranch, "--title",
                "'Promote from $SourceBranch to $TargetBranch'", "--detect")
        } else {
            Write-Information "PR already exists for source to target"
        }
    }
}

<#
#>
Function ConvertTo-DecryptedStringv1
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Value,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Password
    )

    process
    {
        # Value must be composed of two parts, metadata and the content,
        # separated by a '.'
        $valueParts = $Value.Split(".")

        # Check that we have the two parts
        if (($valueParts | Measure-Object).Count -ne 3)
        {
            Write-Error "Value must be composed of version, metadata and content, separated by periods"
        }

        # Check the version
        $version = $valueParts[0]

        if ($version -ne "v1")
        {
            Write-Error "Invalid version in string. Expected `"v1`", received `"$version`""
        }

        # Decode the metadata
        $metadata = [System.Text.Encoding]::UTF8.GetString(([System.Convert]::FromBase64String($valueParts[1]))) | ConvertFrom-Json

        # Read the IV
        $ivBytes = [System.Convert]::FromBase64String($metadata.iv)
        $ivLength = ($ivBytes | Measure-Object).Count

        if ($ivLength -gt 256)
        {
            Write-Error "IV byte length too large: $ivLength"
        }

        # Read the salt
        $saltBytes = [System.Convert]::FromBase64String($metadata.salt)
        $saltLength = ($saltBytes | Measure-Object).Count

        if ($saltLength -gt 256)
        {
            Write-Error "Salt byte length too large: $saltLength"
        }

        # Read the iterations
        $iterations = [int]$metadata.iter

        # Read the data
        $dataBytes = [System.Convert]::FromBase64String($valueParts[2])

        # Generate a key from the password
        $passBytes = [System.Text.Encoding]::UTF8.GetBytes($Password)
        $derive = [System.Security.Cryptography.Rfc2898DeriveBytes]::New($passBytes, $saltBytes, $iterations)

        $aes = $null
        $cryptoStream = $null
        $stream = $null
        try {
            # Create the AES object
            $aes = [System.Security.Cryptography.Aes]::Create()

            # Configure the AES key and IV
            $aes.Key = $derive.GetBytes(32)
            $aes.IV = $ivBytes

            # Memory stream for storing result data
            $stream = New-Object 'System.IO.MemoryStream'

            # Create a CryptoStream to write encrypted data to
            $cryptoStream = [System.Security.Cryptography.CryptoStream]::New($stream, $aes.CreateDecryptor(),
                [System.Security.Cryptography.CryptoStreamMode]::Write)

            # Write the remainder of the content to the crypto stream
            $cryptoStream.Write($dataBytes, 0, $dataBytes.Length)
            $cryptoStream.FlushFinalBlock()

            # Generate a base64 representation of the bytes
            $payload = [System.Text.Encoding]::UTF8.GetString($stream.ToArray()) | ConvertFrom-Json
            $value = [System.Text.Encoding]::UTF8.GetString(([System.Convert]::FromBase64String($payload.Value)))

            $cryptoStream.Close()
            $stream.Close()

            # Pass output back
            $value
        } finally {
            if ($null -ne $cryptoStream)
            {
                $cryptoStream.Dispose()
            }

            if ($null -ne $stream)
            {
                $stream.Dispose()
            }

            if ($null -ne $aes)
            {
                $aes.Dispose()
            }
        }
    }
}

<#
#>
Function ConvertTo-EncryptedStringv1
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Value,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Password,

        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [int]$Iterations = 10000
    )

    process
    {
        # Create the metadata object for the encrypted string
        $metadata = [PSCustomObject]@{
            salt = $null
            iv = $null
            iter = $Iterations
        }

        # Generate a salt to use
        $rng = $null
        $saltBytes = [byte[]]::New(8)
        try {
            $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::New()
            $rng.GetBytes($saltBytes)
            $metadata.salt = [System.Convert]::ToBase64String($saltBytes)
        } finally{
            if ($null -ne $rng)
            {
                $rng.Dispose()
            }
        }

        # Generate a key from the password
        $passBytes = [System.Text.Encoding]::UTF8.GetBytes($Password)
        $derive = [System.Security.Cryptography.Rfc2898DeriveBytes]::New($passBytes, $saltBytes, $Iterations)

        # Encrypt and generate base64 output
        $aes = $null
        $stream = $null
        $cryptoStream = $null
        $encValueBase64 = $null
        try {
            # Create the AES object
            $aes = [System.Security.Cryptography.Aes]::Create()

            # Configure the AES key
            $aes.Key = $derive.GetBytes(32)

            # Save the initialisation vector
            $metadata.iv = [System.Convert]::ToBase64String($aes.IV)

            # Memory stream for storing encrypted data
            $stream = New-Object 'System.IO.MemoryStream'

            # Create a CryptoStream to write to the memory stream
            $cryptoStream = [System.Security.Cryptography.CryptoStream]::New($stream, $aes.CreateEncryptor(),
                [System.Security.Cryptography.CryptoStreamMode]::Write)

            # Write the value to the crypto stream, wrapped in json
            $valueBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Value))
            $payloadBytes = [System.Text.Encoding]::UTF8.GetBytes(([PSCustomObject]@{ Value = $valueBase64 } | ConvertTo-Json))

            $cryptoStream.Write($payloadBytes, 0, $payloadBytes.Length)
            $cryptoStream.FlushFinalBlock()

            # Generate a base64 representation of the bytes
            $encValueBase64 = [System.Convert]::ToBase64String($stream.ToArray())
            $cryptoStream.Close()
            $stream.Close()
        } finally {
            if ($null -ne $cryptoStream)
            {
                $cryptoStream.Dispose()
            }

            if ($null -ne $stream)
            {
                $stream.Dispose()
            }

            if ($null -ne $aes)
            {
                $aes.Dispose()
            }
        }

        # Generate Base64 version of metadata
        $metadataBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($metadata | ConvertTo-Json)))

        # Output whole value
        "v1.{0}.{1}" -f $metadataBase64, $encValueBase64
    }
}

<#
#>
Function ConvertTo-DecryptedString
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Value,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Password
    )

    process
    {
        # Find the version for the incoming value
        $version = $Value.Split(".")[0]

        switch ($version)
        {
            "v1" {
                ConvertTo-DecryptedStringv1 -Value $Value -Password $Password
            }

            default {
                Write-Error "Unknown version: $version"
            }
        }
    }
}


<#
#>
Function ConvertTo-EncryptedString
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$Value,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Password,

        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [int]$Iterations = 10000,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("v1")]
        [string]$Version = "v1"
    )

    begin
    {
        Write-Verbose "Encrypting with version: $Version"
    }

    process
    {
        switch ($Version)
        {
            "v1" {
                ConvertTo-EncryptedStringv1 -Value $Value -Password $Password -Iterations $Iterations
            }

            default {
                Write-Error "Unknown version: $Version"
            }
        }
    }
}
