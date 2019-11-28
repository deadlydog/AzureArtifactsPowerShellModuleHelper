function Register-AzureArtifactsPSRepository
{
	[CmdletBinding(DefaultParameterSetName = 'PAT')]
	param
	(
		[Parameter(Mandatory = $true, Position = 0, HelpMessage = 'The URL of the Azure Artifacts PowerShell feed to register. e.g. https://pkgs.dev.azure.com/YourOrg/_packaging/YourFeed/nuget/v2')]
		[ValidateNotNullOrEmpty()]
		[string] $FeedUrl,

		[Parameter(Mandatory = $false, HelpMessage = 'The name to use for the PSRepository. If not provided, one will be generated.')]
		[string] $RepositoryName,

		[Parameter(Mandatory = $false, ParameterSetName = 'PAT', HelpMessage = 'A personal access token that has Read permissions to the Azure Artifacts feed. If not provided, the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable will be checked, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables')]
		[string] $PersonalAccessToken = $null,

		[Parameter(Mandatory = $false, ParameterSetName = 'Credential', HelpMessage = 'The credential to use to connect to the Azure Artifacts feed.')]
		[System.Management.Automation.PSCredential] $Credential = $null
	)

	Process
	{
		if ([string]::IsNullOrWhitespace($RepositoryName))
		{
			$RepositoryName = Get-RandomCharacters
		}

		[System.Management.Automation.PSCredential] $Credential = Get-AzureArtifactsCredentials -personalAccessToken $PersonalAccessToken -credential $Credential

		Register-AzureArtifactsPowerShellRepository -feedUrl $FeedUrl -repositoryName $RepositoryName -credential $Credential
		return $RepositoryName
	}

	Begin
	{
		function Register-AzureArtifactsPowerShellRepository([string] $feedUrl, [string] $repositoryName, [System.Management.Automation.PSCredential] $credential)
		{
			if ($null -eq (Get-PackageProvider NuGet -ErrorAction SilentlyContinue))
			{
				Write-Information 'Installing NuGet package provider.'
				Install-PackageProvider NuGet -Scope CurrentUser -Force > $null
			}

			$psRepositories = Get-PSRepository

			[bool] $psRepositoryIsAlreadyRegistered = ($null -ne ($psRepositories | Where-Object { $_.Name -ieq $repositoryName -and $_.SourceLocation -ieq $feedUrl -and $_.InstallationPolicy -ieq 'Trusted' }))
			if ($psRepositoryIsAlreadyRegistered)
			{
				return
			}

			if ($null -eq $credential)
			{
				[string] $computerName = $Env:ComputerName
				Write-Error "A personal access token was not found, so we cannot register a PSRepository to connect to '$feedUrl' on '$computerName'."
			}

			Remove-PsRepositoriesWithSameNameOrFeed -Name $repositoryName -feedUrl $feedUrl -psRepositories $psRepositories

			Register-PSRepository -Name $repositoryName -SourceLocation $feedUrl -InstallationPolicy Trusted -Credential $credential > $null
		}

		function Remove-PsRepositoriesWithSameNameOrFeed([string] $name, [string] $feedUrl, $psRepositories)
		{
			# [bool] $psRepositoryWasRemoved = $false
			$psRepositories | ForEach-Object {
				$psRepository = $_
				[string] $psRepositoryName = $psRepository.Name
				[string] $psRepositoryFeed = $psRepository.SourceLocation

				if ($psRepositoryName -ieq $name -or $psRepositoryFeed -ieq $feedUrl)
				{
					Write-Warning "The existing PSRepository '$psRepositoryName' with feed '$psRepositoryFeed' has the same name or feed URL as the one requested to be added: '$name' '$feedUrl'. Removing PSRepository '$psRepositoryName'."
					Unregister-PSRepository -Name $psRepositoryName
					# $psRepositoryWasRemoved = $true
				}
			}
			# return $psRepositoryWasRemoved
		}

		function Get-RandomCharacters([int] $length = 8)
		{
			[string] $word = (-join ((65..90) + (97..122) | Get-Random -Count $length | ForEach-Object { [char]$_ }))
			return $word
		}
	}
}

function Import-AzureArtifactsModule
{
	[CmdletBinding(DefaultParameterSetName = 'PAT')]
	param
	(
		[Parameter(Mandatory = $true, Position = 0, HelpMessage = 'The name of the PowerShell module to install (if necessary) and import.')]
		[ValidateNotNullOrEmpty()]
		[string] $Name,

		[Parameter(Mandatory = $false, HelpMessage = 'The specific version of the PowerShell module to install (if necessary) and import. If not provided, the latest version will be used.')]
		[System.Version] $Version = $null,

		[Parameter(Mandatory = $false, ParameterSetName = 'PAT', HelpMessage = 'A personal access token that has Read permissions to the Azure Artifacts feed. If not provided, the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable will be checked, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables')]
		[string] $PersonalAccessToken = $null,

		[Parameter(Mandatory = $false, ParameterSetName = 'Credential', HelpMessage = 'The credential to use to connect to the Azure Artifacts feed.')]
		[System.Management.Automation.PSCredential] $Credential = $null,

		[Parameter(Mandatory = $false, HelpMessage = 'If provided, the specified PowerShell module will always be downloaded and installed, even if the version is already installed.')]
		[switch] $Force = $false
	)

	Process
	{
		[System.Management.Automation.PSCredential] $credential = Get-AzureArtifactsCredentials -personalAccessToken $PersonalAccessToken

		if ($null -eq $credential)
		{
			[string] $computerName = $Env:ComputerName
			Write-Error "A personal access token was not found, so we cannot ensure a specific version of PowerShell module '$Name' is installed on '$computerName'."
		}
		else
		{
			Register-AzureArtifactsPSRepository -RepositoryName $repositoryName -Credential $credential
			$Version = Install-ModuleVersion -powerShellModuleName $Name -versionToInstall $Version -credential $credential -force:$Force
		}
		Import-Module -Name $Name -RequiredVersion $Version -Force
	}

	Begin
	{
		function Install-ModuleVersion([string] $powerShellModuleName, [System.Version] $versionToInstall, [string] $repositoryName, [System.Management.Automation.PSCredential] $credential, [switch] $force)
		{
			[string] $computerName = $Env:ComputerName

			[System.Version[]] $currentModuleVersionsInstalled = (Get-Module -Name $powerShellModuleName -ListAvailable) | Select-Object -ExpandProperty 'Version' -Unique | Sort-Object -Descending | ForEach-Object { [System.Version]::Parse($_) }

			[bool] $latestVersionShouldBeInstalled = [string]::IsNullOrWhitespace($versionToInstall)
			if ($latestVersionShouldBeInstalled)
			{
				$latestModuleVersionAvailable = (Find-Module -Name $powerShellModuleName -Repository $repositoryName -Credential $credential) | Select-Object -ExpandProperty 'Version' -First 1
				$versionToInstall = [System.Version]::Parse($latestModuleVersionAvailable)
			}
			else
			{
				[bool] $specifiedVersionDoesNotExist = ($null -eq (Find-Module -Name $powerShellModuleName -RequiredVersion $versionToInstall -Repository $repositoryName -Credential $credential -ErrorAction SilentlyContinue))
				if ($specifiedVersionDoesNotExist)
				{
					[System.Version] $existingLatestVersion = ($currentModuleVersionsInstalled | Select-Object -First 1)
					Write-Error "The specified version '$versionToInstall' of PowerShell module '$powerShellModuleName' does not exist, so it cannot be installed on computer '$computerName'. Version '$existingLatestVersion' will be imported instead."
					return
				}
			}

			[bool] $versionNeedsToBeInstalled = ($versionToInstall -notin $currentModuleVersionsInstalled) -or $force
			if ($versionNeedsToBeInstalled)
			{
				[string] $moduleVersionsInstalledString = $currentModuleVersionsInstalled -join ','
				Write-Information "Current installed version of PowerShell module '$powerShellModuleName' on computer '$computerName' is '$moduleVersionsInstalledString'. Installing version '$versionToInstall'."
				Install-Module -Name $powerShellModuleName -RequiredVersion $versionToInstall -Repository $repositoryName -Credential $credential -Scope CurrentUser -Force -AllowClobber
			}
			return $versionToInstall
		}
	}
}

function Get-AzureArtifactsCredentials([string] $personalAccessToken = $null, [System.Management.Automation.PSCredential] $credential = $null)
{
	if ($null -ne $credential)
	{
		return $credential
	}

	if ([string]::IsNullOrWhiteSpace($personalAccessToken))
	{
		$personalAccessToken = Get-PersonalAccessTokenFromEnvironmentVariable
	}

	if (![string]::IsNullOrWhiteSpace($personalAccessToken))
	{
		$pat = ConvertTo-SecureString $PersonalAccessToken -AsPlainText -Force
		$credential = New-Object System.Management.Automation.PSCredential 'Username@DoesNotMatter.com', $pat
	}

	return $credential
}

# Microsoft recommends storing the PAT in an environment variable: https://github.com/Microsoft/artifacts-credprovider#environment-variables
function Get-PersonalAccessTokenFromEnvironmentVariable
{
	[string] $personalAccessToken = [string]::Empty
	[string] $computerName = $Env:ComputerName
	[string] $patJsonValue = $Env:VSS_NUGET_EXTERNAL_FEED_ENDPOINTS
	if (![string]::IsNullOrWhiteSpace($patJsonValue))
	{
		$patJson = ConvertFrom-Json $patJsonValue
		$personalAccessToken = $patJson.endpointCredentials.password

		if ([string]::IsNullOrWhitespace($personalAccessToken))
		{
			Write-Warning "Found the environmental variable 'VSS_NUGET_EXTERNAL_FEED_ENDPOINTS' on computer '$computerName', but could not retrieve the Personal Access Token from it."
		}
	}
	else
	{
		Write-Warning "Could not find the environment variable 'VSS_NUGET_EXTERNAL_FEED_ENDPOINTS' on computer '$computerName' to extract the Personal Access Token from it."
	}
	return $personalAccessToken
}

Export-ModuleMember -Function Import-AzureArtifactsModule
Export-ModuleMember -Function Register-AzureArtifactsPSRepository
