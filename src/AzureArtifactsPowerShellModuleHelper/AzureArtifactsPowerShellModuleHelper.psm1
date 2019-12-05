<#
.SYNOPSIS
	Registers a PSRepository to the given Azure Artifacts feed if one does not already exist.
	Also installs the latest NuGet Package Provider and PowerShellGet module if necessary, which are required by other cmdlets in the module.
.DESCRIPTION
	Registers a PSRepository to the given Azure Artifacts feed if one does not already exist.
	If a PSRepository to the provided feed already exists, it will return the existing PSRepository's name, rather than creating a new one and using the RepositoryName parameter (if provided).

	The cmdlet also installs the latest NuGet Package Provider and PowerShellGet module if necessary, which are required by other cmdlets in the module.
.EXAMPLE
	```
	[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2 -RepositoryName 'MyAzureArtifacts'
	```
	Attempts to create a PSRepository to the given FeedUrl if one doesn't exist.
	If one does not exist, one will be created with the name `MyAzureArtifacts`.
	If one already exists, it will simply return the name of the existing PSRepository, rather than the provided one.
	Since no Credential was provided, it will attempt to retrieve a PAT from the environmental variables.
	The name of the PSRepository to the FeedUrl is returned.

	```
	[System.Security.SecureString] $securePersonalAccessToken = 'YourPatGoesHere' | ConvertTo-SecureString -AsPlainText -Force
	[System.Management.Automation.PSCredential] $Credential = New-Object System.Management.Automation.PSCredential 'Username@DoesNotMatter.com', $securePersonalAccessToken
	[string] $feedUrl = 'https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2'
	[string] $repositoryName = Register-AzureArtifactsPSRepository -Credential $credential -FeedUrl $feedUrl
	```
	Attempts to create a PSRepository to the given FeedUrl if one doesn't exist, using the Credential provided.
.INPUTS
	FeedUrl: (Required) The URL of the Azure Artifacts PowerShell feed to register. e.g. https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2. Note: PowerShell does not yet support the "/v3" endpoint, so use v2.

	RepositoryName: The name to use for the PSRepository if one must be created. If not provided, one will be generated. A PSRepository with the given name will only be created if one to the Feed URL does not already exist.

	Credential: The credential to use to connect to the Azure Artifacts feed. This should be created from a personal access token that has at least Read permissions to the Azure Artifacts feed. If not provided, the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable will be checked, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables.

	Scope: If the NuGet Package Provider needs to be installed, this is the scope it will be installed in. Allowed values are "AllUsers" and "CurrentUser". Default is "CurrentUser".
.OUTPUTS
	System.String
	Returns the Name of the PSRepository that can be used to connect to the given Feed URL.
.NOTES
	If a Credential is not provided, it will attempt to retrieve a PAT from the environment variables, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables

	This function writes to the error, warning, and information streams in different scenarios, as well as may throw exceptions for catastrophic errors.
#>
function Register-AzureArtifactsPSRepository
{
	param
	(
		[Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, HelpMessage = 'The URL of the Azure Artifacts PowerShell feed to register. e.g. https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2. Note: PowerShell does not yet support the "/v3" endpoint, so use v2.')]
		[ValidateNotNullOrEmpty()]
		[string] $FeedUrl,

		[Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, HelpMessage = 'The name to use for the PSRepository if one must be created. If not provided, one will be generated. A PSRepository with the given name will only be created if one to the Feed URL does not already exist.')]
		[string] $RepositoryName,

		[Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, HelpMessage = 'The credential to use to connect to the Azure Artifacts feed. This should be created from a personal access token that has at least Read permissions to the Azure Artifacts feed. If not provided, the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable will be checked, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables')]
		[System.Management.Automation.PSCredential] $Credential = $null,

		[Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, HelpMessage = 'If the NuGet Package Provider needs to be installed, this is the scope it will be installed in. Allowed values are "AllUsers" and "CurrentUser". Default is "CurrentUser".')]
		[ValidateSet('AllUsers', 'CurrentUser')]
		[string] $Scope = 'CurrentUser'
	)

	Process
	{
		if ([string]::IsNullOrWhitespace($RepositoryName))
		{
			[string] $organizationAndFeed = Get-AzureArtifactOrganizationAndFeedFromUrl -feedUrl $FeedUrl
			$RepositoryName = ('AzureArtifacts-' + $organizationAndFeed).TrimEnd('-')
		}

		$Credential = Get-AzureArtifactsCredential -credential $Credential

		Install-NuGetPackageProvider -scope $Scope
		Install-PowerShellGet -scope $Scope

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

		function Install-NuGetPackageProvider([string] $scope)
		{
			[string] $computerName = $Env:ComputerName
			[string] $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

			$nuGetPackageProviderModule = Get-PackageProvider | Where-Object { $_.Name -ieq 'NuGet' }

			[bool] $nuGetPackageProviderIsNotInstalled = ($null -eq $nuGetPackageProviderModule)
			if ($nuGetPackageProviderIsNotInstalled)
			{
				Write-Information "Installing NuGet package provider for user '$currentUser' to scope '$scope' on computer '$computerName'."
				Install-PackageProvider NuGet -Scope $scope -Force > $null
			}
			else
			{
				$installedVersion = $nuGetPackageProviderModule.Version
				Write-Information "Skipping installing the NuGet Package Provider, as version '$installedVersion' is already installed on computer '$computerName'."
		}
		}

		function Install-PowerShellGet([string] $scope)
		{
			[string] $computerName = $Env:ComputerName
			[string] $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

			[System.Version] $minimumRequiredPowerShellGetVersion = '2.2.1'
			$latestPowerShellGetVersionInstalled =
				Get-Module -Name 'PowerShellGet' -ListAvailable |
				Select-Object -ExpandProperty 'Version' -Unique |
				Sort-Object -Descending |
				Select-Object -First 1

			[bool] $minimumPowerShellGetVersionIsNotInstalled = ($latestPowerShellGetVersionInstalled -lt $minimumRequiredPowerShellGetVersion)
			if ($minimumPowerShellGetVersionIsNotInstalled)
			{
				[string] $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
				Write-Information "Installing latest PowerShellGet version for user '$currentUser' to scope '$scope' on computer '$computerName'."
				Install-Module -Name PowerShellGet -Scope $scope -Force -AllowClobber
			}
			else
			{
				Write-Information "Skipping installing the PowerShellGet module, as version '$latestPowerShellGetVersionInstalled' is already installed on computer '$computerName', which satisfies the minimum required version '$minimumRequiredPowerShellGetVersion'."
			}

			# Explicitly import the latest version of PowerShellGet to ensure it gets used by later cmdlets instead of an earlier version.
			Import-Module -Name PowerShellGet -MinimumVersion $minimumRequiredPowerShellGetVersion -Global -Force
		}
	}
}

<#
.SYNOPSIS
	Install (if necessary) and import a module from the specified repository.
.DESCRIPTION
	Install (if necessary) and import a module from the specified repository.
.EXAMPLE
	```
	Import-AzureArtifactsModule -Name 'ModuleNameInYourFeed' -RepositoryName $repositoryName
	```
	Installs the 'ModuleNameInYourFeed' module from the specified Repository if necessary, and then imports it.
.INPUTS
	Name: (Required) The name of the PowerShell module to install (if necessary) and import.

	Version: The specific version of the PowerShell module to install (if necessary) and import. If not provided, the latest version will be used.

	AllowPrerelease: If provided, prerelease versions are allowed to be installed and imported. This must be provided if specifying a Prerelease version in the Version parameter.

	RepositoryName: (Required) The name to use for the PSRepository that contains the module to import. This should be obtained from the Register-AzureArtifactsPSRepository cmdlet.

	Credential: The credential to use to connect to the Azure Artifacts feed.

	Force: If provided, the specified PowerShell module will always be downloaded and installed, even if the version is already installed.

	Scope: If the PowerShell Module needs to be installed, this is the scope it will be installed in. Allowed values are "AllUsers" and "CurrentUser". Default is "CurrentUser".
.OUTPUTS
	No outputs are returned.
.NOTES
	If a Credential is not provided, it will attempt to retrieve a PAT from the environment variables, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables

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

		[Parameter(Mandatory = $false, HelpMessage = 'The credential to use to connect to the Azure Artifacts feed. This should be created from a personal access token that has at least Read permissions to the Azure Artifacts feed. If not provided, the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable will be checked, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables')]
		[System.Management.Automation.PSCredential] $Credential = $null,

		[Parameter(Mandatory = $false, HelpMessage = 'If provided, the specified PowerShell module will always be downloaded and installed, even if the version is already installed.')]
		[switch] $Force = $false,

		[Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, HelpMessage = 'If the PowerShell Module needs to be installed, this is the scope it will be installed in. Allowed values are "AllUsers" and "CurrentUser". Default is "CurrentUser".')]
		[ValidateSet('AllUsers', 'CurrentUser')]
		[string] $Scope = 'CurrentUser'
	)

	Process
	{
		$Credential = Get-AzureArtifactsCredential -credential $Credential

		if ($null -eq $credential)
		{
			[string] $computerName = $Env:ComputerName
			Write-Error "A personal access token was not found, so we cannot ensure a specific version (or the latest version) of PowerShell module '$Name' is installed on '$computerName'."
		}
		else
		{
			$Version = Install-ModuleVersion -powerShellModuleName $Name -versionToInstall $Version -allowPrerelease:$AllowPrerelease -repositoryName $RepositoryName -credential $credential -force:$Force -scope $Scope
		}

		Import-ModuleVersion -powerShellModuleName $Name -version $Version
	}

	Begin
	{
		function Install-ModuleVersion([string] $powerShellModuleName, [string] $versionToInstall, [switch] $allowPrerelease, [string] $repositoryName, [System.Management.Automation.PSCredential] $credential, [switch] $force, [string] $scope)
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
				[string] $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
				[string] $moduleVersionsInstalledString = $currentModuleVersionsInstalled -join ','
				Write-Information "Current installed versions of PowerShell module '$powerShellModuleName' on computer '$computerName' are '$moduleVersionsInstalledString'. Installing version '$versionToInstall' for user '$currentUser' to scope '$scope'."
				try
				{
					Install-Module -Name $powerShellModuleName -AllowPrerelease:$allowPrerelease -RequiredVersion $versionToInstall -Repository $repositoryName -Credential $credential -Scope $scope -Force -AllowClobber
				}
				catch
				{
					[string] $exceptionMessage = $_.Exception.ToString()
					[string] $errorMessage = "The following exception was thrown while trying to install PowerShell module '$powerShellModuleName' version '$versionToInstall' for user '$currentUser' to scope '$scope'."

					if ($moduleIsInstalledOnComputerAlready)
					{
						$errorMessage += "Version '$existingLatestVersion' will be used instead." +
							[System.Environment]::NewLine + $exceptionMessage
						Write-Error $errorMessage
						return $existingLatestVersion
					}
					else
					{
						$errorMessage += 'No other version of the PowerShell module is installed, so it cannot be imported.'
						throw ($errorMessage + [System.Environment]::NewLine + $exceptionMessage)
					}
				}
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

		function Import-ModuleVersion([string] $powerShellModuleName, [string] $version)
		{
			[bool] $isPrereleaseVersion = Test-PrereleaseVersion -version $version
			if (!$isPrereleaseVersion)
			{
				Import-Module -Name $powerShellModuleName -RequiredVersion $version -Global -Force
			}
			else
			{
				Import-ModulePrereleaseVersion -powerShellModuleName $powerShellModuleName -version $version
			}

			Write-ModuleVersionImported -powerShellModuleName $powerShellModuleName -version $version
		}

		function Test-PrereleaseVersion([string] $version)
		{
			[bool] $isPrereleaseVersion = $true
			[System.Version] $parsedVersion = $null
			if ([System.Version]::TryParse($Version, [ref]$parsedVersion))
			{
				$isPrereleaseVersion = $false
			}
			return $isPrereleaseVersion
		}

		function Import-ModulePrereleaseVersion([string] $powerShellModuleName, [string] $version)
		{
			[string] $computerName = $Env:ComputerName

			# PowerShell is weird about the way it supports prerelease versions.
			# The directory it installs to and the version it gives it is just the version with the prerelease postfix removed.
			# So really Import-Module has no way of telling if a module is a stable version or a prerelease version.
			# So we need to strip off the prerelease portion of the version number (i.e. what comes after the hyphen) to
			# 	get the stable version number, which Import-Module will use to find it.
			[string] $prereleaseVersionsStablePortion = ($ValidModulePrereleaseVersionThatExists -split '-')[0]

			[bool] $stableVersionWasExtractedFromPrereleaseVersion = ($prereleaseVersionsStablePortion -ne $version)
			if ($stableVersionWasExtractedFromPrereleaseVersion)
			{
				Import-Module -Name $powerShellModuleName -RequiredVersion $prereleaseVersionsStablePortion -Global -Force
			}
			else
			{
				Write-Warning "The prerelease version '$version' of module '$powerShellModuleName' was requested to be imported on computer '$computerName', but we could not determine where it was installed to. The module will be imported without specifying the version to import."
				Import-Module -Name $powerShellModuleName -Global -Force
			}
		}

		function Write-ModuleVersionImported([string] $powerShellModuleName, [string] $version)
		{
			[string] $computerName = $Env:ComputerName
			[string] $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

			$moduleImported = Get-Module -Name $powerShellModuleName

			[bool] $moduleWasImported = ($null -ne $moduleImported)
			if ($moduleWasImported)
			{
				[string] $moduleVersion = $moduleImported.Version
				Write-Information "Version '$moduleVersion' of module '$powerShellModuleName' was imported on computer '$computerName' for user '$currentUser'."
			}
			else
			{
				Write-Error "The module '$powerShellModuleName' was not imported on computer '$computerName' for user '$currentUser'."
			}
		}
	}
}

function Get-AzureArtifactsCredential([System.Management.Automation.PSCredential] $credential = $null)
{
	if ($null -ne $credential)
	{
		return $credential
	}

	[System.Security.SecureString] $personalAccessToken = Get-SecurePersonalAccessTokenFromEnvironmentVariable

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
