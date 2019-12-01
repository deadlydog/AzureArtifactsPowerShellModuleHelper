<#
.SYNOPSIS
	Registers a PSRepository to the given Azure Artifacts feed if one does not already exist.
.DESCRIPTION
	Registers a PSRepository to the given Azure Artifacts feed if one does not already exist.
.EXAMPLE
	PS C:\> [string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2 -RepositoryName 'MyAzureArtifacts'
	Attempts to create a PSRepository to the given FeedUrl if one doesn't exist.
	If one does not exist, one will be created with the name `MyAzureArtifacts`.
	Since no PersonalAccessToken (PAT) or Credential were provided, it will attempt to retrieve a PAT from the environmental variables.
	The name of the PSRepository to the FeedUrl is returned.

	PS C:\> [string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2 -PersonalAccessToken 'YourPatAsASecureString'
	Attempts to create a PSRepository to the given FeedUrl if one doesn't exist, using the provided PAT.
.INPUTS
	FeedUrl: (Required) The URL of the Azure Artifacts PowerShell feed to register. e.g. https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2. Note: PowerShell does not yet support the "/v3" endpoint, so use v2.

	RepositoryName: The name to use for the PSRepository if one must be created. If not provided, one will be generated. A PSRepository with the given name will only be created if one to the Feed URL does not already exist.

	PersonalAccessToken: A personal access token that has Read permissions to the Azure Artifacts feed. If not provided, the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable will be checked, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables

	Credential: The credential to use to connect to the Azure Artifacts feed.
.OUTPUTS
	System.String
	Returns the Name of the PSRepository that can be used to connect to the given Feed URL.
.NOTES
	You cannot provide both PersonalAccessToken (PAT) and Credential. You must provide only one, or none.
	If neither are provided, it will attempt to retrieve a PAT from the environment variables, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables

	This function writes to the error, warning, and information streams in different scenarios, as well as may throw exceptions for catastrophic errors.
#>
function Register-AzureArtifactsPSRepository
{
	[CmdletBinding(DefaultParameterSetName = 'PAT')]
	param
	(
		[Parameter(Mandatory = $true, Position = 0, HelpMessage = 'The URL of the Azure Artifacts PowerShell feed to register. e.g. https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2. Note: PowerShell does not yet support the "/v3" endpoint, so use v2.')]
		[ValidateNotNullOrEmpty()]
		[string] $FeedUrl,

		[Parameter(Mandatory = $false, HelpMessage = 'The name to use for the PSRepository if one must be created. If not provided, one will be generated. A PSRepository with the given name will only be created if one to the Feed URL does not already exist.')]
		[string] $RepositoryName,

		[Parameter(Mandatory = $false, ParameterSetName = 'PAT', HelpMessage = 'A personal access token that has Read permissions to the Azure Artifacts feed. This must be provided as a [System.Security.SecureString]. If not provided, the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable will be checked, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables')]
		[System.Security.SecureString] $PersonalAccessToken = $null,

		[Parameter(Mandatory = $false, ParameterSetName = 'Credential', HelpMessage = 'The credential to use to connect to the Azure Artifacts feed.')]
		[System.Management.Automation.PSCredential] $Credential = $null
	)

	Process
	{
		if ([string]::IsNullOrWhitespace($RepositoryName))
		{
			[string] $organizationAndFeed = Get-AzureArtifactOrganizationAndFeedFromUrl -feedUrl $FeedUrl
			$RepositoryName = ('AzureArtifacts-' + $organizationAndFeed).TrimEnd('-')
		}

		$Credential = Get-AzureArtifactsCredential -personalAccessToken $PersonalAccessToken -credential $Credential

		Install-NuGetPackageProvider

		[string] $repositoryNameOfFeed = Register-AzureArtifactsPowerShellRepository -feedUrl $FeedUrl -repositoryName $RepositoryName -credential $Credential

		return $repositoryNameOfFeed
	}

	Begin
	{
		function Register-AzureArtifactsPowerShellRepository([string] $feedUrl, [string] $repositoryName, [System.Management.Automation.PSCredential] $credential)
		{
			$psRepositories = Get-PSRepository

			[PSCustomObject] $existingPsRepositoryForFeed = $psRepositories | Where-Object { $_.SourceLocation -ieq $feedUrl }
			[bool] $psRepositoryIsAlreadyRegistered = ($null -ne $existingPsRepositoryForFeed)
			if ($psRepositoryIsAlreadyRegistered)
			{
				return $existingPsRepositoryForFeed.Name
			}

			[PSCustomObject] $existingPsRepositoryWithSameName = $psRepositories | Where-Object { $_.Name -ieq $repositoryName }
			[bool] $psRepositoryWithDesiredNameAlreadyExists = ($null -ne $existingPsRepositoryWithSameName)
			if ($psRepositoryWithDesiredNameAlreadyExists)
			{
				$repositoryName += '-' + (Get-RandomCharacters -length 3)
			}

			if ($null -eq $credential)
			{
				[string] $computerName = $Env:ComputerName
				Write-Warning "Credentials were not provided, so we will attempt to register a new PSRepository to connect to '$feedUrl' on '$computerName' without credentials."
				Register-PSRepository -Name $repositoryName -SourceLocation $feedUrl -InstallationPolicy Trusted > $null
			}
			else
			{
				Register-PSRepository -Name $repositoryName -SourceLocation $feedUrl -InstallationPolicy Trusted -Credential $credential > $null
			}

			return $repositoryName
		}

		function Get-RandomCharacters([int] $length = 8)
		{
			[string] $word = (-join ((65..90) + (97..122) | Get-Random -Count $length | ForEach-Object { [char]$_ }))
			return $word
		}

		function Get-AzureArtifactOrganizationAndFeedFromUrl([string] $feedUrl)
		{
			# Azure Artifact feed URLs are of the format: 'https://pkgs.dev.azure.com/Organization/_packaging/Feed/nuget/v2'
			[bool] $urlMatchesRegex = $feedUrl -match 'https\:\/\/pkgs.dev.azure.com\/(?<Organization>.+?)\/_packaging\/(?<Feed>.+?)\/'
			if ($urlMatchesRegex)
			{
				return $Matches.Organization + '-' + $Matches.Feed
			}
			return [string]::Empty
		}

		function Install-NuGetPackageProvider
		{
			[bool] $nuGetPackageProviderIsNotInstalled = ($null -eq (Get-PackageProvider | Where-Object { $_.Name -ieq 'NuGet' }))
			if ($nuGetPackageProviderIsNotInstalled)
			{
				Write-Information 'Installing NuGet package provider.'
				Install-PackageProvider NuGet -Scope CurrentUser -Force > $null
			}
		}
	}
}

<#
.SYNOPSIS
	Install (if necessary) and import a module from the specified repository.
.DESCRIPTION
	Install (if necessary) and import a module from the specified repository.
.EXAMPLE
	PS C:\> <example usage>
	Explanation of what the example does
.INPUTS
	Name: (Required) The name of the PowerShell module to install (if necessary) and import.

	Version: The specific version of the PowerShell module to install (if necessary) and import. If not provided, the latest version will be used.

	AllowPrerelease: If provided, prerelease versions are allowed to be installed and imported. This must be provided if specifying a Prerelease version in the Version parameter.

	RepositoryName: (Required) The name to use for the PSRepository that contains the module to import. This should be obtained from the Register-AzureArtifactsPSRepository cmdlet.

	PersonalAccessToken: A personal access token that has Read permissions to the Azure Artifacts feed. This must be provided as a [System.Security.SecureString]. If not provided, the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable will be checked, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables.

	Credential: The credential to use to connect to the Azure Artifacts feed.

	Force: If provided, the specified PowerShell module will always be downloaded and installed, even if the version is already installed.
.OUTPUTS
	No outputs are returned.
.NOTES
	You cannot provide both PersonalAccessToken (PAT) and Credential. You must provide only one, or none.
	If neither are provided, it will attempt to retrieve a PAT from the environment variables, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables

	This function writes to the error, warning, and information streams in different scenarios, as well as may throw exceptions for catastrophic errors.
#>
function Import-AzureArtifactsModule
{
	[CmdletBinding(DefaultParameterSetName = 'PAT')]
	param
	(
		[Parameter(Mandatory = $true, Position = 0, HelpMessage = 'The name of the PowerShell module to install (if necessary) and import.')]
		[ValidateNotNullOrEmpty()]
		[string] $Name,

		[Parameter(Mandatory = $false, HelpMessage = 'The specific version of the PowerShell module to install (if necessary) and import. If not provided, the latest version will be used.')]
		[string] $Version = $null,

		[Parameter(Mandatory = $false, HelpMessage = 'If provided, prerelease versions are allowed to be installed and imported. This must be provided if specifying a Prerelease version in the Version parameter.')]
		[switch] $AllowPrerelease = $false,

		[Parameter(Mandatory = $true, HelpMessage = 'The name to use for the PSRepository that contains the module to import. This should be obtained from the Register-AzureArtifactsPSRepository cmdlet.')]
		[string] $RepositoryName,

		[Parameter(Mandatory = $false, ParameterSetName = 'PAT', HelpMessage = 'A personal access token that has Read permissions to the Azure Artifacts feed. This must be provided as a [System.Security.SecureString]. If not provided, the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable will be checked, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables')]
		[System.Security.SecureString] $PersonalAccessToken = $null,

		[Parameter(Mandatory = $false, ParameterSetName = 'Credential', HelpMessage = 'The credential to use to connect to the Azure Artifacts feed.')]
		[System.Management.Automation.PSCredential] $Credential = $null,

		[Parameter(Mandatory = $false, HelpMessage = 'If provided, the specified PowerShell module will always be downloaded and installed, even if the version is already installed.')]
		[switch] $Force = $false
	)

	Process
	{
		$Credential = Get-AzureArtifactsCredential -personalAccessToken $PersonalAccessToken -credential $Credential

		if ($null -eq $credential)
		{
			[string] $computerName = $Env:ComputerName
			Write-Error "A personal access token was not found, so we cannot ensure a specific version (or the latest version) of PowerShell module '$Name' is installed on '$computerName'."
		}
		else
		{
			$Version = Install-ModuleVersion -powerShellModuleName $Name -versionToInstall $Version -allowPrerelease:$AllowPrerelease -repositoryName $RepositoryName -credential $credential -force:$Force
		}
		Import-Module -Name $Name -RequiredVersion $Version -Global -Force
	}

	Begin
	{
		function Install-ModuleVersion([string] $powerShellModuleName, [string] $versionToInstall, [switch] $allowPrerelease, [string] $repositoryName, [System.Management.Automation.PSCredential] $credential, [switch] $force)
		{
			[string] $computerName = $Env:ComputerName

			[string[]] $currentModuleVersionsInstalled = (Get-Module -Name $powerShellModuleName -ListAvailable) | Select-Object -ExpandProperty 'Version' -Unique | Sort-Object -Descending

			[bool] $specificVersionWasRequestedAndIsAlreadyInstalled = ((![string]::IsNullOrWhitespace($versionToInstall)) -and $versionToInstall -in $currentModuleVersionsInstalled)
			if ($specificVersionWasRequestedAndIsAlreadyInstalled)
			{
				if (!$force)
				{
					return $versionToInstall
				}
			}

			[string] $existingLatestVersion = ($currentModuleVersionsInstalled | Select-Object -First 1)
			[bool] $moduleIsInstalledOnComputerAlready = ![string]::IsNullOrWhitespace($existingLatestVersion)

			[bool] $latestVersionShouldBeInstalled = [string]::IsNullOrWhitespace($versionToInstall)
			if ($latestVersionShouldBeInstalled)
			{
				[string] $latestModuleVersionAvailable = Get-LatestAvailableVersion -powerShellModuleName $powerShellModuleName -allowPrerelease:$allowPrerelease -repositoryName $repositoryName -credential $credential

				[bool] $moduleWasNotFoundInPsRepository = [string]::IsNullOrWhitespace($latestModuleVersionAvailable)
				if ($moduleWasNotFoundInPsRepository)
				{
					if ($moduleIsInstalledOnComputerAlready)
					{
						Write-Error "The PowerShell module '$powerShellModuleName' could not be found in the PSRepository '$repositoryName', so the latest version of the module could not be obtained. Perhaps the credentials used are not valid. The module version '$existingLatestVersion' is installed on computer '$computerName' though so it will be used."
						return $existingLatestVersion
					}
					else
					{
						throw "The PowerShell module '$powerShellModuleName' could not be found in the PSRepository '$repositoryName' so it cannot be downloaded and installed. Perhaps the credentials used are not valid. The module is not already installed on computer '$computerName', so it cannot be imported."
					}
				}

				$versionToInstall = $latestModuleVersionAvailable
			}
			else
			{
				[bool] $specifiedVersionDoesNotExist = ($null -eq (Find-Module -Name $powerShellModuleName -AllowPrerelease:$allowPrerelease -RequiredVersion $versionToInstall -Repository $repositoryName -Credential $credential -ErrorAction SilentlyContinue))
				if ($specifiedVersionDoesNotExist)
				{
					if ($moduleIsInstalledOnComputerAlready)
					{
						Write-Error "The specified version '$versionToInstall' of PowerShell module '$powerShellModuleName' does not exist in the PSRepository '$repositoryName', so it cannot be installed on computer '$computerName'. Version '$existingLatestVersion' is already installed and will be imported instead."
						return $existingLatestVersion
					}
					else
					{
						[string] $latestModuleVersionAvailable = Get-LatestAvailableVersion -powerShellModuleName $powerShellModuleName -allowPrerelease:$allowPrerelease -repositoryName $repositoryName -credential $credential

						[bool] $moduleWasNotFoundInPsRepository = [string]::IsNullOrWhitespace($latestModuleVersionAvailable)
						if ($moduleWasNotFoundInPsRepository)
						{
							throw "The PowerShell module '$powerShellModuleName' could not be found in the PSRepository '$repositoryName' so it cannot be downloaded and installed. Perhaps the credentials used are not valid. The module is not already installed on computer '$computerName', so it cannot be imported."
						}

						Write-Error "The specified version '$versionToInstall' of PowerShell module '$powerShellModuleName' does not exist in the PSRepository '$repositoryName'. Version '$latestModuleVersionAvailable' will be installed instead."

						$versionToInstall = $latestModuleVersionAvailable
					}
				}
			}

			[bool] $versionNeedsToBeInstalled = ($versionToInstall -notin $currentModuleVersionsInstalled) -or $force
			if ($versionNeedsToBeInstalled)
			{
				[string] $moduleVersionsInstalledString = $currentModuleVersionsInstalled -join ','
				Write-Information "Current installed versions of PowerShell module '$powerShellModuleName' on computer '$computerName' are '$moduleVersionsInstalledString'. Installing version '$versionToInstall'."
				Install-Module -Name $powerShellModuleName -AllowPrerelease:$allowPrerelease -RequiredVersion $versionToInstall -Repository $repositoryName -Credential $credential -Scope CurrentUser -Force -AllowClobber
			}
			return $versionToInstall
		}

		function Get-LatestAvailableVersion([string] $powerShellModuleName, [switch] $allowPrerelease, [string] $repositoryName, [System.Management.Automation.PSCredential] $credential)
		{
			[string] $latestModuleVersionAvailable =
				Find-Module -Name $powerShellModuleName -AllowPrerelease:$allowPrerelease -Repository $repositoryName -Credential $credential -ErrorAction SilentlyContinue |
				Select-Object -ExpandProperty 'Version' -First 1
			return $latestModuleVersionAvailable
		}
	}
}

function Get-AzureArtifactsCredential([System.Security.SecureString] $personalAccessToken = $null, [System.Management.Automation.PSCredential] $credential = $null)
{
	if ($null -ne $credential)
	{
		return $credential
	}

	if ($null -eq $personalAccessToken)
	{
		$personalAccessToken = Get-SecurePersonalAccessTokenFromEnvironmentVariable
	}

	if ($null -ne $personalAccessToken)
	{
		$credential = New-Object System.Management.Automation.PSCredential 'Username@DoesNotMatter.com', $personalAccessToken
	}

	return $credential
}

# Microsoft recommends storing the PAT in an environment variable: https://github.com/Microsoft/artifacts-credprovider#environment-variables
function Get-SecurePersonalAccessTokenFromEnvironmentVariable
{
	[System.Security.SecureString] $securePersonalAccessToken = $null
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
		else
		{
			$securePersonalAccessToken = ConvertTo-SecureString $personalAccessToken -AsPlainText -Force
		}
	}
	else
	{
		Write-Warning "Could not find the environment variable 'VSS_NUGET_EXTERNAL_FEED_ENDPOINTS' on computer '$computerName' to extract the Personal Access Token from it."
	}
	return $securePersonalAccessToken
}

Export-ModuleMember -Function Import-AzureArtifactsModule
Export-ModuleMember -Function Register-AzureArtifactsPSRepository
