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
.INPUTS
	FeedUrl: The URL of the Azure Artifacts PowerShell feed to register. e.g. https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2

	RepositoryName: The name to use for the PSRepository if one must be created. If not provided, one will be generated. A PSRepository with the given name will only be created if one to the Feed URL does not already exist.

	PersonalAccessToken: A personal access token that has Read permissions to the Azure Artifacts feed. If not provided, the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable will be checked, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables

	Credential: The credential to use to connect to the Azure Artifacts feed.
.OUTPUTS
	System.String
	Returns the Name of the PSRepository that can be used to connect to the given Feed URL.
.NOTES
	You cannot provide both PersonalAccessToken (PAT) and Credential. You must provide only one, or none.
	If neither are provided, it will attempt to retrieve a PAT from the environment variables, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables
#>
function Register-AzureArtifactsPSRepository
{
	[CmdletBinding(DefaultParameterSetName = 'PAT')]
	param
	(
		[Parameter(Mandatory = $true, Position = 0, HelpMessage = 'The URL of the Azure Artifacts PowerShell feed to register. e.g. https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2')]
		[ValidateNotNullOrEmpty()]
		[string] $FeedUrl,

		[Parameter(Mandatory = $false, HelpMessage = 'The name to use for the PSRepository if one must be created. If not provided, one will be generated. A PSRepository with the given name will only be created if one to the Feed URL does not already exist.')]
		[string] $RepositoryName,

		[Parameter(Mandatory = $false, ParameterSetName = 'PAT', HelpMessage = 'A personal access token that has Read permissions to the Azure Artifacts feed. If not provided, the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable will be checked, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables')]
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

			[PSCustomObject] $existingPsRepositoryOfFeed = $psRepositories | Where-Object { $_.SourceLocation -ieq $feedUrl }
			[bool] $psRepositoryIsAlreadyRegistered = ($null -ne $existingPsRepositoryOfFeed)
			if ($psRepositoryIsAlreadyRegistered)
			{
				return $existingPsRepositoryOfFeed.Name
			}

			if ($null -eq $credential)
			{
				[string] $computerName = $Env:ComputerName
				throw "A personal access token was not found, so we cannot register a new PSRepository to connect to '$feedUrl' on '$computerName'."
			}

			[PSCustomObject] $existingPsRepositoryWithSameName = $psRepositories | Where-Object { $_.Name -ieq $repositoryName }
			[bool] $psRepositoryWithDesiredNameAlreadyExists = ($null -ne $existingPsRepositoryWithSameName)
			if ($psRepositoryWithDesiredNameAlreadyExists)
			{
				$repositoryName += '-' + (Get-RandomCharacters -length 3)
			}

			Register-PSRepository -Name $repositoryName -SourceLocation $feedUrl -InstallationPolicy Trusted -Credential $credential > $null

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

		[Parameter(Mandatory = $false, HelpMessage = 'The URL of the Azure Artifacts PowerShell feed the module is on. e.g. https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2')]
		[ValidateNotNullOrEmpty()]
		[string] $FeedUrl,

		[Parameter(Mandatory = $false, HelpMessage = 'The name to use for the PSRepository if one must be created. If not provided, one will be generated. A PSRepository with the given name will only be created if one to the Feed URL does not already exist.')]
		[string] $RepositoryName,

		[Parameter(Mandatory = $false, ParameterSetName = 'PAT', HelpMessage = 'A personal access token that has Read permissions to the Azure Artifacts feed. If not provided, the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable will be checked, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables')]
		[string] $PersonalAccessToken = $null,

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
			Register-AzureArtifactsPSRepository -RepositoryName $repositoryName -Credential $credential
			$Version = Install-ModuleVersion -powerShellModuleName $Name -versionToInstall $Version -credential $credential -force:$Force
		}
		Import-Module -Name $Name -RequiredVersion $Version -Force
	}

	Begin
	{
		function Install-ModuleVersion([string] $powerShellModuleName, [string] $versionToInstall, [string] $repositoryName, [System.Management.Automation.PSCredential] $credential, [switch] $force)
		{
			[string] $computerName = $Env:ComputerName

			[string[]] $currentModuleVersionsInstalled = (Get-Module -Name $powerShellModuleName -ListAvailable) | Select-Object -ExpandProperty 'Version' -Unique | Sort-Object -Descending }

			[bool] $latestVersionShouldBeInstalled = ($null -eq $versionToInstall)
			if ($latestVersionShouldBeInstalled)
			{
				$latestModuleVersionAvailable = (Find-Module -Name $powerShellModuleName -Repository $repositoryName -Credential $credential) | Select-Object -ExpandProperty 'Version' -First 1
				$versionToInstall = $latestModuleVersionAvailable
			}
			else
			{
				[bool] $specifiedVersionDoesNotExist = ($null -eq (Find-Module -Name $powerShellModuleName -RequiredVersion $versionToInstall -Repository $repositoryName -Credential $credential -ErrorAction SilentlyContinue))
				if ($specifiedVersionDoesNotExist)
				{
					[string] $existingLatestVersion = ($currentModuleVersionsInstalled | Select-Object -First 1)
					Write-Error "The specified version '$versionToInstall' of PowerShell module '$powerShellModuleName' does not exist, so it cannot be installed on computer '$computerName'. Version '$existingLatestVersion' will be imported instead."
					return $existingLatestVersion
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
