<#
.SYNOPSIS
	Registers a PSRepository to the given Azure Artifacts feed if one does not already exist.
	Also installs the latest NuGet Package Provider and PowerShellGet module if necessary, which are required by other cmdlets in the module.
.DESCRIPTION
	Registers a PSRepository to the given Azure Artifacts feed if one does not already exist.
	If a PSRepository to the provided feed already exists, it will return the existing PSRepository's name, rather than creating a new one and using the Repository parameter (if provided).

	The cmdlet also installs the latest NuGet Package Provider and PowerShellGet module if necessary, which are required by other cmdlets in the module.
.EXAMPLE
	```
	[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2 -Repository 'MyAzureArtifacts'
	```
	Attempts to create a PSRepository to the given FeedUrl if one doesn't exist.
	If one does not exist, one will be created with the name `MyAzureArtifacts`.
	If one already exists, it will simply return the name of the existing PSRepository, rather than the provided one.
	Since no Credential was provided, it will attempt to retrieve a PAT from the environmental variables.
	The name of the PSRepository to the FeedUrl is returned.

	```
	[System.Security.SecureString] $securePersonalAccessToken = 'YourPatGoesHere' | ConvertTo-SecureString -AsPlainText -Force
	[PSCredential] $Credential = New-Object System.Management.Automation.PSCredential 'Username@DoesNotMatter.com', $securePersonalAccessToken
	[string] $feedUrl = 'https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2'
	[string] $repository = Register-AzureArtifactsPSRepository -Credential $credential -FeedUrl $feedUrl
	```
	Attempts to create a PSRepository to the given FeedUrl if one doesn't exist, using the Credential provided.
.INPUTS
	[string] FeedUrl: (Required) The URL of the Azure Artifacts PowerShell feed to register. e.g. https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2. Note: PowerShell does not yet support the "/v3" endpoint, so use v2.

	[string] Repository: The name to use for the PSRepository if one must be created. If not provided, one will be generated. A PSRepository with the given name will only be created if one to the Feed URL does not already exist.

	[PSCredential] Credential: The credential to use to connect to the Azure Artifacts feed. This should be created from a personal access token that has at least Read permissions to the Azure Artifacts feed. If not provided, the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable will be checked, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables.

	[string] Scope: If the NuGet Package Provider or PowerShellGet module needs to be installed, this is the scope it will be installed in. Allowed values are "AllUsers" and "CurrentUser". Default is "CurrentUser".
.OUTPUTS
	System.String
	Returns the Name of the PSRepository that can be used to connect to the given Feed URL.
.NOTES
	If a Credential is not provided, it will attempt create one by retrieving a Personal Access Token (PAT) from the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables.

	This function writes to the error, warning, and information streams in different scenarios, as well as may throw exceptions for catastrophic errors.
#>
function Register-AzureArtifactsPSRepository
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, HelpMessage = 'The URL of the Azure Artifacts PowerShell feed to register. e.g. https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2. Note: PowerShell does not yet support the "/v3" endpoint, so use v2.')]
		[ValidateNotNullOrEmpty()]
		[string] $FeedUrl,

		[Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, HelpMessage = 'The name to use for the PSRepository if one must be created. If not provided, one will be generated. A PSRepository with the given name will only be created if one to the Feed URL does not already exist.')]
		[string] $Repository,

		[Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, HelpMessage = 'The credential to use to connect to the Azure Artifacts feed. This should be created from a personal access token that has at least Read permissions to the Azure Artifacts feed. If not provided, the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable will be checked, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables')]
		[PSCredential] $Credential = $null,

		[Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, HelpMessage = 'If the NuGet Package Provider or PowerShellGet module needs to be installed, this is the scope it will be installed in. Allowed values are "AllUsers" and "CurrentUser". Default is "CurrentUser".')]
		[ValidateSet('AllUsers', 'CurrentUser')]
		[string] $Scope = 'CurrentUser'
	)

	Process
	{
		if ([string]::IsNullOrWhitespace($Repository))
		{
			[string] $organizationAndFeed = Get-AzureArtifactOrganizationAndFeedFromUrl -feedUrl $FeedUrl
			$Repository = ('AzureArtifacts-' + $organizationAndFeed).TrimEnd('-')
		}

		$Credential = Get-AzureArtifactsCredential -credential $Credential

		Install-NuGetPackageProvider -scope $Scope
		Install-AndImportPowerShellGet -scope $Scope

		[string] $repositoryNameOfFeed = Register-AzureArtifactsPowerShellRepository -feedUrl $FeedUrl -Repository $Repository -credential $Credential

		# We must also register the Package Source to overcome a bug in PowerShellGet v2.
		# More info at:
		#	https://github.com/PowerShell/PowerShellGetv2/issues/619#issuecomment-718837449
		#	https://stackoverflow.com/questions/60973101/azure-powershell-module-properly-pushed-to-artifacts-feed-repository-cannot-be
		Register-AzureArtifactsPackageSource -feedUrl $FeedUrl -repositoryName $repositoryNameOfFeed -credential $Credential

		return $repositoryNameOfFeed
	}

	Begin
	{
		function Register-AzureArtifactsPowerShellRepository([string] $feedUrl, [string] $repository, [PSCredential] $credential)
		{
			$psRepositories = Get-PSRepository

			[PSCustomObject] $existingPsRepositoryForFeed = $psRepositories | Where-Object { $_.SourceLocation -ieq $feedUrl }
			[bool] $psRepositoryIsAlreadyRegistered = ($null -ne $existingPsRepositoryForFeed)
			if ($psRepositoryIsAlreadyRegistered)
			{
				Write-Verbose "Found existing PSRepository '$($existingPsRepositoryForFeed.Name)' for Feed URL '$feedUrl'."
				return $existingPsRepositoryForFeed.Name
			}

			[PSCustomObject] $existingPsRepositoryWithSameName = $psRepositories | Where-Object { $_.Name -ieq $repository }
			[bool] $psRepositoryWithDesiredNameAlreadyExists = ($null -ne $existingPsRepositoryWithSameName)
			if ($psRepositoryWithDesiredNameAlreadyExists)
			{
				Write-Verbose "PSRepository with name '$repository' already exists, but for a different Feed URL, so will attempt to create repository with slightly different name."
				$repository += '-' + (Get-RandomCharacters -length 3)
			}

			Write-Verbose "Attempting to create PSRepository with name '$repository' for SourceLocation '$feedUrl'."
			if ($null -eq $credential)
			{
				[string] $computerName = $Env:ComputerName
				Write-Warning "Credentials were not provided, so we will attempt to register a new PSRepository to connect to '$feedUrl' on '$computerName' without credentials."
				Register-PSRepository -Name $repository -SourceLocation $feedUrl -InstallationPolicy Trusted > $null
			}
			else
			{
				Register-PSRepository -Name $repository -SourceLocation $feedUrl -InstallationPolicy Trusted -Credential $credential > $null
			}

			return $repository
		}

		function Register-AzureArtifactsPackageSource([string] $feedUrl, [string] $repositoryName, [PSCredential] $credential)
		{
			$packageSources = Get-PackageSource

			[PSCustomObject] $existingPackageSourceForFeed = $packageSources | Where-Object { $_.Location -ieq $feedUrl }
			[bool] $packageSourceIsAlreadyRegistered = ($null -ne $existingPackageSourceForFeed)
			if ($packageSourceIsAlreadyRegistered)
			{
				Write-Verbose "Found existing PackageSource '$($existingPackageSourceForFeed.Name)' for Feed URL '$feedUrl'."
				return
			}

			[PSCustomObject] $existingPackageSourcesWithSameName = $packageSources | Where-Object { $_.Name -ieq $repositoryName }
			[bool] $packageSourceWithDesiredNameAlreadyExists = ($null -ne $existingPackageSourcesWithSameName)
			if ($packageSourceWithDesiredNameAlreadyExists)
			{
				Write-Verbose "PackageSource with name '$repositoryName' already exists, but for a different Feed URL, so will attempt to create repository with slightly different name."
				$repositoryName += '-' + (Get-RandomCharacters -length 3)
			}

			Write-Verbose "Attempting to create PackageSource with name '$repositoryName' for Location '$feedUrl'."
			if ($null -eq $credential)
			{
				[string] $computerName = $Env:ComputerName
				Write-Warning "Credentials were not provided, so we will attempt to register a new PackageSource to connect to '$feedUrl' on '$computerName' without credentials."
				Register-PackageSource -Name $repositoryName -Location $feedUrl -ProviderName NuGet -SkipValidate > $null
			}
			else
			{
				Register-PackageSource -Name $repositoryName -Location $feedUrl -ProviderName NuGet -SkipValidate -Credential $credential > $null
			}
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

			[System.Version] $minimumRequiredNuGetPackageProviderVersion = '2.8.5.208' # Minimum version required to install NuGet packages.
			[bool] $nuGetPackageProviderVersionIsHighEnough = Test-CurrentlyInstalledNuGetPackageProviderVersionIsHighEnough -minimumRequiredVersion $minimumRequiredNuGetPackageProviderVersion

			if (!$nuGetPackageProviderVersionIsHighEnough)
			{
				Write-Information "Installing NuGet package provider for user '$currentUser' to scope '$scope' on computer '$computerName'."
				Install-PackageProvider -Name NuGet -Scope $scope -Force -MinimumVersion $minimumRequiredNuGetPackageProviderVersion > $null
			}
		}

		function Test-CurrentlyInstalledNuGetPackageProviderVersionIsHighEnough([System.Version] $minimumRequiredVersion)
		{
			[string] $computerName = $Env:ComputerName

			$nuGetPackageProviderModule =
				Get-PackageProvider |
				Where-Object { $_.Name -ieq 'NuGet' } # Use Where instead of -Name to avoid error when it is not installed.

			if ($null -eq $nuGetPackageProviderModule)
			{
				Write-Information "The NuGet package provider is not installed on computer '$computerName'."
				return $false
			}

			[System.Version] $installedVersion = $nuGetPackageProviderModule.Version
			if ($installedVersion -lt $minimumRequiredVersion)
			{
				Write-Information "The installed version '$installedVersion' of the NuGet Package Provider on computer '$computerName' does not satisfy the minimum required version of '$minimumRequiredVersion'."
				return $false
			}

			Write-Information "The installed version '$installedVersion' of the NuGet Package Provider on computer '$computerName' satisfies the minimum required version of '$minimumRequiredVersion'."
			return $true
		}

		function Install-AndImportPowerShellGet([string] $scope)
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
				Install-Module -Name PowerShellGet -Repository PSGallery -Scope $scope -Force -AllowClobber
			}
			else
			{
				Write-Information "The installed version '$latestPowerShellGetVersionInstalled' of the PowerShellGet module on computer '$computerName' satisfies the minimum required version of '$minimumRequiredPowerShellGetVersion'."
			}

			Import-PowerShellGetModule -minimumRequiredPowerShellGetVersion $minimumRequiredPowerShellGetVersion
		}

		function Import-PowerShellGetModule([System.Version] $minimumRequiredPowerShellGetVersion)
		{
			$currentlyImportedVersion = Get-CurrentlyImportedPowerShellGetModuleVersion

			[bool] $powerShellGetIsNotAlreadyImported = ($null -eq $currentlyImportedVersion)
			if ($powerShellGetIsNotAlreadyImported)
			{
				Import-Module -Name PowerShellGet -MinimumVersion $minimumRequiredPowerShellGetVersion -Global -Force
				return
			}
			Write-Verbose "The currently imported PowerShellGet module version is '$currentlyImportedVersion'."
			
			[bool] $powerShellGetVersionImportedIsHighEnough = ($currentlyImportedVersion -ge $minimumRequiredPowerShellGetVersion)
			if ($powerShellGetVersionImportedIsHighEnough)
			{
				return
			}

			Write-Warning "The PowerShellGet module version currently imported is '$currentlyImportedVersion', which does not meet the minimum requirement of '$minimumRequiredPowerShellGetVersion'. The current PowerShellGet module will be removed and a newer version imported."
			Remove-Module -Name PowerShellGet -Force
			Import-Module -Name PowerShellGet -MinimumVersion $minimumRequiredPowerShellGetVersion -Global -Force
		}

		function Get-CurrentlyImportedPowerShellGetModuleVersion
		{
			[System.Version] $powerShellGetModuleVersionImported = $null
			$lowestCurrentlyImportedModuleVersion =
				Get-Module -Name PowerShellGet |
				Select-Object -ExpandProperty 'Version' -Unique |
				Sort-Object |
				Select-Object -First 1

			if ($null -ne $lowestCurrentlyImportedModuleVersion)
			{
				$powerShellGetModuleVersionImported = $lowestCurrentlyImportedModuleVersion
			}

			return $powerShellGetModuleVersionImported
		}
	}
}

# <#
# .SYNOPSIS
# 	Install (if necessary) and import a module from the specified repository.
# .DESCRIPTION
# 	Install (if necessary) and import a module from the specified repository.
# .EXAMPLE
# 	```
# 	Import-AzureArtifactsModule -Name 'ModuleNameInYourFeed' -Repository $repository
# 	```
# 	Installs the 'ModuleNameInYourFeed' module from the specified Repository if necessary, and then imports it.
# .INPUTS
# 	Name: (Required) The name of the PowerShell module to install (if necessary) and import.

# 	Version: The specific version of the PowerShell module to install (if necessary) and import. If not provided, the latest version will be used.

# 	AllowPrerelease: If provided, prerelease versions are allowed to be installed and imported. This must be provided if specifying a Prerelease version in the Version parameter.

# 	Repository: (Required) The name to use for the PSRepository that contains the module to import. This should be obtained from the Register-AzureArtifactsPSRepository cmdlet.

# 	Credential: The credential to use to connect to the Azure Artifacts feed.

# 	Force: If provided, the specified PowerShell module will always be downloaded and installed, even if the version is already installed.

# 	Scope: If the PowerShell Module needs to be installed, this is the scope it will be installed in. Allowed values are "AllUsers" and "CurrentUser". Default is "CurrentUser".
# .OUTPUTS
# 	No outputs are returned.
# .NOTES
# 	If a Credential is not provided, it will attempt to retrieve a PAT from the environment variables, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables

# 	This function writes to the error, warning, and information streams in different scenarios, as well as may throw exceptions for catastrophic errors.
# #>
# function Import-AzureArtifactsModule
# {
# 	[CmdletBinding(DefaultParameterSetName = 'PAT')]
# 	param
# 	(
# 		[Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true, HelpMessage = 'The name of the PowerShell module to install (if necessary) and import.')]
# 		[ValidateNotNullOrEmpty()]
# 		[string] $Name,

# 		[Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, HelpMessage = 'The specific version of the PowerShell module to install (if necessary) and import. If not provided, the latest version will be used.')]
# 		[string] $Version = $null,

# 		[Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, HelpMessage = 'If provided, prerelease versions are allowed to be installed and imported. This must be provided if specifying a Prerelease version in the Version parameter.')]
# 		[switch] $AllowPrerelease = $false,

# 		[Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, HelpMessage = 'The name to use for the PSRepository that contains the module to import. This should be obtained from the Register-AzureArtifactsPSRepository cmdlet.')]
# 		[string] $Repository,

# 		[Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, HelpMessage = 'The credential to use to connect to the Azure Artifacts feed. This should be created from a personal access token that has at least Read permissions to the Azure Artifacts feed. If not provided, the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable will be checked, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables')]
# 		[PSCredential] $Credential = $null,

# 		[Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, HelpMessage = 'If provided, the specified PowerShell module will always be downloaded and installed, even if the version is already installed.')]
# 		[switch] $Force = $false,

# 		[Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, HelpMessage = 'If the PowerShell Module needs to be installed, this is the scope it will be installed in. Allowed values are "AllUsers" and "CurrentUser". Default is "CurrentUser".')]
# 		[ValidateSet('AllUsers', 'CurrentUser')]
# 		[string] $Scope = 'CurrentUser'
# 	)

# 	Process
# 	{
# 		$Credential = Get-AzureArtifactsCredential -credential $Credential

# 		if ($null -eq $Credential)
# 		{
# 			[string] $computerName = $Env:ComputerName
# 			Write-Error "A personal access token was not found, so we cannot ensure a specific version (or the latest version) of PowerShell module '$Name' is installed on '$computerName'."
# 		}
# 		else
# 		{
# 			$Version = Install-ModuleVersion -powerShellModuleName $Name -versionToInstall $Version -allowPrerelease:$AllowPrerelease -Repository $Repository -credential $Credential -force:$Force -scope $Scope
# 		}

# 		Import-ModuleVersion -powerShellModuleName $Name -version $Version
# 	}

# 	Begin
# 	{
# 		function Install-ModuleVersion([string] $powerShellModuleName, [string] $versionToInstall, [switch] $allowPrerelease, [string] $repository, [PSCredential] $credential, [switch] $force, [string] $scope)
# 		{
# 			[string] $computerName = $Env:ComputerName

# 			[string[]] $currentModuleVersionsInstalled =
# 				Get-Module -Name $powerShellModuleName -ListAvailable |
# 				Select-Object -ExpandProperty 'Version' -Unique |
# 				Sort-Object -Descending

# 			[bool] $specificVersionWasRequestedAndIsAlreadyInstalled = ((![string]::IsNullOrWhitespace($versionToInstall)) -and $versionToInstall -in $currentModuleVersionsInstalled)
# 			if ($specificVersionWasRequestedAndIsAlreadyInstalled)
# 			{
# 				if (!$force)
# 				{
# 					return $versionToInstall
# 				}
# 			}

# 			[string] $existingLatestVersion = ($currentModuleVersionsInstalled | Select-Object -First 1)
# 			[bool] $moduleIsInstalledOnComputerAlready = ![string]::IsNullOrWhitespace($existingLatestVersion)

# 			[bool] $latestVersionShouldBeInstalled = [string]::IsNullOrWhitespace($versionToInstall)
# 			if ($latestVersionShouldBeInstalled)
# 			{
# 				[string] $latestModuleVersionAvailable = Get-LatestAvailableVersion -powerShellModuleName $powerShellModuleName -allowPrerelease:$allowPrerelease -Repository $repository -credential $credential

# 				[bool] $moduleWasNotFoundInPsRepository = [string]::IsNullOrWhitespace($latestModuleVersionAvailable)
# 				if ($moduleWasNotFoundInPsRepository)
# 				{
# 					if ($moduleIsInstalledOnComputerAlready)
# 					{
# 						Write-Error "The PowerShell module '$powerShellModuleName' could not be found in the PSRepository '$repository', so the latest version of the module could not be obtained. Perhaps the credentials used are not valid. The module version '$existingLatestVersion' is installed on computer '$computerName' though so it will be used."
# 						return $existingLatestVersion
# 					}
# 					else
# 					{
# 						throw "The PowerShell module '$powerShellModuleName' could not be found in the PSRepository '$repository' so it cannot be downloaded and installed. Perhaps the credentials used are not valid. The module is not already installed on computer '$computerName', so it cannot be imported."
# 					}
# 				}

# 				$versionToInstall = $latestModuleVersionAvailable
# 			}
# 			else
# 			{
# 				[bool] $specifiedVersionDoesNotExist = ($null -eq (Find-Module -Name $powerShellModuleName -AllowPrerelease:$allowPrerelease -RequiredVersion $versionToInstall -Repository $repository -Credential $credential -ErrorAction SilentlyContinue))
# 				if ($specifiedVersionDoesNotExist)
# 				{
# 					if ($moduleIsInstalledOnComputerAlready)
# 					{
# 						Write-Error "The specified version '$versionToInstall' of PowerShell module '$powerShellModuleName' does not exist in the PSRepository '$repository', so it cannot be installed on computer '$computerName'. Version '$existingLatestVersion' is already installed and will be imported instead."
# 						return $existingLatestVersion
# 					}
# 					else
# 					{
# 						[string] $latestModuleVersionAvailable = Get-LatestAvailableVersion -powerShellModuleName $powerShellModuleName -allowPrerelease:$allowPrerelease -Repository $repository -credential $credential

# 						[bool] $moduleWasNotFoundInPsRepository = [string]::IsNullOrWhitespace($latestModuleVersionAvailable)
# 						if ($moduleWasNotFoundInPsRepository)
# 						{
# 							throw "The PowerShell module '$powerShellModuleName' could not be found in the PSRepository '$repository' so it cannot be downloaded and installed. Perhaps the credentials used are not valid. The module is not already installed on computer '$computerName', so it cannot be imported."
# 						}

# 						Write-Error "The specified version '$versionToInstall' of PowerShell module '$powerShellModuleName' does not exist in the PSRepository '$repository'. Version '$latestModuleVersionAvailable' will be installed instead."

# 						$versionToInstall = $latestModuleVersionAvailable
# 					}
# 				}
# 			}

# 			[bool] $versionNeedsToBeInstalled = ($versionToInstall -notin $currentModuleVersionsInstalled) -or $force
# 			if ($versionNeedsToBeInstalled)
# 			{
# 				[string] $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
# 				[string] $moduleVersionsInstalledString = $currentModuleVersionsInstalled -join ','
# 				Write-Information "Current installed versions of PowerShell module '$powerShellModuleName' on computer '$computerName' are '$moduleVersionsInstalledString'. Installing version '$versionToInstall' for user '$currentUser' to scope '$scope'."
# 				try
# 				{
# 					Install-Module -Name $powerShellModuleName -AllowPrerelease:$allowPrerelease -RequiredVersion $versionToInstall -Repository $repository -Credential $credential -Scope $scope -Force -AllowClobber
# 				}
# 				catch
# 				{
# 					[string] $exceptionMessage = $_.Exception.ToString()
# 					[string] $errorMessage = "The following exception was thrown while trying to install PowerShell module '$powerShellModuleName' version '$versionToInstall' for user '$currentUser' to scope '$scope'."

# 					if ($moduleIsInstalledOnComputerAlready)
# 					{
# 						$errorMessage += "Version '$existingLatestVersion' will be used instead." +
# 							[System.Environment]::NewLine + $exceptionMessage
# 						Write-Error $errorMessage
# 						return $existingLatestVersion
# 					}
# 					else
# 					{
# 						$errorMessage += 'No other version of the PowerShell module is installed, so it cannot be imported.'
# 						throw ($errorMessage + [System.Environment]::NewLine + $exceptionMessage)
# 					}
# 				}
# 			}
# 			return $versionToInstall
# 		}

# 		function Get-LatestAvailableVersion([string] $powerShellModuleName, [switch] $allowPrerelease, [string] $repository, [PSCredential] $credential)
# 		{
# 			[string] $latestModuleVersionAvailable =
# 				Find-Module -Name $powerShellModuleName -AllowPrerelease:$allowPrerelease -Repository $repository -Credential $credential -ErrorAction SilentlyContinue |
# 				Select-Object -ExpandProperty 'Version' -First 1
# 			return $latestModuleVersionAvailable
# 		}

# 		function Import-ModuleVersion([string] $powerShellModuleName, [string] $version)
# 		{
# 			[bool] $isPrereleaseVersion = Test-PrereleaseVersion -version $version
# 			if (!$isPrereleaseVersion)
# 			{
# 				Import-Module -Name $powerShellModuleName -RequiredVersion $version -Global -Force
# 			}
# 			else
# 			{
# 				Import-ModulePrereleaseVersion -powerShellModuleName $powerShellModuleName -version $version
# 			}

# 			Write-ModuleVersionImported -powerShellModuleName $powerShellModuleName -version $version
# 		}

# 		function Test-PrereleaseVersion([string] $version)
# 		{
# 			[bool] $isPrereleaseVersion = $true
# 			[System.Version] $parsedVersion = $null
# 			if ([System.Version]::TryParse($Version, [ref]$parsedVersion))
# 			{
# 				$isPrereleaseVersion = $false
# 			}
# 			return $isPrereleaseVersion
# 		}

# 		function Import-ModulePrereleaseVersion([string] $powerShellModuleName, [string] $version)
# 		{
# 			[string] $computerName = $Env:ComputerName

# 			# PowerShell is weird about the way it supports prerelease versions.
# 			# The directory it installs to and the version it gives it is just the version with the prerelease postfix removed.
# 			# So really Import-Module has no way of telling if a module is a stable version or a prerelease version.
# 			# So we need to strip off the prerelease portion of the version number (i.e. what comes after the hyphen) to
# 			# 	get the stable version number, which Import-Module will use to find it.
# 			[string] $prereleaseVersionsStablePortion = ($ValidModulePrereleaseVersionThatExists -split '-')[0]

# 			[bool] $stableVersionWasExtractedFromPrereleaseVersion = ($prereleaseVersionsStablePortion -ne $version)
# 			if ($stableVersionWasExtractedFromPrereleaseVersion)
# 			{
# 				Import-Module -Name $powerShellModuleName -RequiredVersion $prereleaseVersionsStablePortion -Global -Force
# 			}
# 			else
# 			{
# 				Write-Warning "The prerelease version '$version' of module '$powerShellModuleName' was requested to be imported on computer '$computerName', but we could not determine where it was installed to. The module will be imported without specifying the version to import."
# 				Import-Module -Name $powerShellModuleName -Global -Force
# 			}
# 		}

# 		function Write-ModuleVersionImported([string] $powerShellModuleName, [string] $version)
# 		{
# 			[string] $computerName = $Env:ComputerName
# 			[string] $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

# 			$moduleImported = Get-Module -Name $powerShellModuleName

# 			[bool] $moduleWasImported = ($null -ne $moduleImported)
# 			if ($moduleWasImported)
# 			{
# 				[string] $moduleVersion = $moduleImported.Version
# 				Write-Information "Version '$moduleVersion' of module '$powerShellModuleName' was imported on computer '$computerName' for user '$currentUser'."
# 			}
# 			else
# 			{
# 				Write-Error "The module '$powerShellModuleName' was not imported on computer '$computerName' for user '$currentUser'."
# 			}
# 		}
# 	}
# }

<#
.SYNOPSIS
	A proxy function to Find-Module that first tries to dynamically obtain a Credential if one was not provided.
.DESCRIPTION
	A proxy function to Find-Module that first tries to dynamically obtain a Credential if one was not provided.

	If a Credential is not provided, it will attempt create one by retrieving a Personal Access Token (PAT) from the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables.

	The Find-Module help can be viewed at: https://docs.microsoft.com/en-us/powershell/module/powershellget/find-module
.EXAMPLE
	PS C:\> Find-AzureArtifactModule -Name YourModule -Repository YourAzureArtifactsRepositoryName

	This command will attempt to use the 'YourAzureArtifactsRepositoryName' PSRepository to search for the 'YourModule" module and list its details.
.INPUTS
	This function simply proxies to the Find-Module cmdlet.
	View the Find-Module cmdlet input parameters at: https://docs.microsoft.com/en-us/powershell/module/powershellget/find-module#parameters
.OUTPUTS
	This function simply proxies to the Find-Module cmdlet.
	View the Find-Module cmdlet outputs at: https://docs.microsoft.com/en-us/powershell/module/powershellget/find-module#outputs
.NOTES
	If a Credential is not provided, it will attempt create one by retrieving a Personal Access Token (PAT) from the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables.
#>
function Find-AzureArtifactsModule
{
	# Entire Param section was copy-pasted from the Find-Module function: https://github.com/PowerShell/PowerShellGet/blob/development/src/PowerShellGet/public/psgetfunctions/Find-Module.ps1
	# This was done so that we can easily splat this function to the Find-Module function, while providing the same intellisense experience.
	[CmdletBinding(HelpUri = 'https://go.microsoft.com/fwlink/?LinkID=398574')]
	[outputtype("PSCustomObject[]")]
	Param
	(
		[Parameter(ValueFromPipelineByPropertyName = $true,
			Position = 0)]
		[ValidateNotNullOrEmpty()]
		[string[]]
		$Name,

		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[ValidateNotNull()]
		[string]
		$MinimumVersion,

		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[ValidateNotNull()]
		[string]
		$MaximumVersion,

		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[ValidateNotNull()]
		[string]
		$RequiredVersion,

		[Parameter()]
		[switch]
		$AllVersions,

		[Parameter()]
		[switch]
		$IncludeDependencies,

		[Parameter()]
		[ValidateNotNull()]
		[string]
		$Filter,

		[Parameter()]
		[ValidateNotNull()]
		[string[]]
		$Tag,

		[Parameter()]
		[ValidateNotNull()]
		[ValidateSet('DscResource', 'Cmdlet', 'Function', 'RoleCapability')]
		[string[]]
		$Includes,

		[Parameter()]
		[ValidateNotNull()]
		[string[]]
		$DscResource,

		[Parameter()]
		[ValidateNotNull()]
		[string[]]
		$RoleCapability,

		[Parameter()]
		[ValidateNotNull()]
		[string[]]
		$Command,

		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[ValidateNotNullOrEmpty()]
		[Uri]
		$Proxy,

		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[PSCredential]
		$ProxyCredential,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string[]]
		$Repository,

		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[PSCredential]
		$Credential,

		[Parameter()]
		[switch]
		$AllowPrerelease
	)

	[hashtable] $parametersWithCredentials = Get-PsBoundParametersWithCredential -parameters $PSBoundParameters
	Find-Module @parametersWithCredentials
}

<#
.SYNOPSIS
	A proxy function to Install-Module that first tries to dynamically obtain a Credential if one was not provided.
.DESCRIPTION
	A proxy function to Install-Module that first tries to dynamically obtain a Credential if one was not provided.

	If a Credential is not provided, it will attempt create one by retrieving a Personal Access Token (PAT) from the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables.

	The Install-Module help can be viewed at: https://docs.microsoft.com/en-us/powershell/module/powershellget/install-module
.EXAMPLE
	PS C:\> Install-AzureArtifactModule -Name YourModule -Repository YourAzureArtifactsRepositoryName

	This command will attempt to use the 'YourAzureArtifactsRepositoryName' PSRepository to download and install 'YourModule".
.INPUTS
	This function simply proxies to the Install-Module cmdlet.
	View the Install-Module cmdlet input parameters at: https://docs.microsoft.com/en-us/powershell/module/powershellget/install-module#parameters
.OUTPUTS
	This function simply proxies to the Install-Module cmdlet.
	View the Install-Module cmdlet outputs at: https://docs.microsoft.com/en-us/powershell/module/powershellget/install-module#outputs
.NOTES
	If a Credential is not provided, it will attempt create one by retrieving a Personal Access Token (PAT) from the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables.
#>
function Install-AzureArtifactsModule
{
	# Entire Param section was copy-pasted from the Install-Module function: https://github.com/PowerShell/PowerShellGet/blob/development/src/PowerShellGet/public/psgetfunctions/Install-Module.ps1
	# This was done so that we can easily splat this function to the Install-Module function, while providing the same intellisense experience.
	[CmdletBinding(DefaultParameterSetName = 'NameParameterSet',
		HelpUri = 'https://go.microsoft.com/fwlink/?LinkID=398573',
		SupportsShouldProcess = $true)]
	Param
	(
		[Parameter(Mandatory = $true,
			ValueFromPipelineByPropertyName = $true,
			Position = 0,
			ParameterSetName = 'NameParameterSet')]
		[ValidateNotNullOrEmpty()]
		[string[]]
		$Name,

		[Parameter(Mandatory = $true,
			ValueFromPipeline = $true,
			ValueFromPipelineByPropertyName = $true,
			Position = 0,
			ParameterSetName = 'InputObject')]
		[ValidateNotNull()]
		[PSCustomObject[]]
		$InputObject,

		[Parameter(ValueFromPipelineByPropertyName = $true,
			ParameterSetName = 'NameParameterSet')]
		[ValidateNotNull()]
		[string]
		$MinimumVersion,

		[Parameter(ValueFromPipelineByPropertyName = $true,
			ParameterSetName = 'NameParameterSet')]
		[ValidateNotNull()]
		[string]
		$MaximumVersion,

		[Parameter(ValueFromPipelineByPropertyName = $true,
			ParameterSetName = 'NameParameterSet')]
		[ValidateNotNull()]
		[string]
		$RequiredVersion,

		[Parameter(ParameterSetName = 'NameParameterSet')]
		[ValidateNotNullOrEmpty()]
		[string[]]
		$Repository,

		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[PSCredential]
		$Credential,

		[Parameter()]
		[ValidateSet("CurrentUser", "AllUsers")]
		[string]
		$Scope,

		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[ValidateNotNullOrEmpty()]
		[Uri]
		$Proxy,

		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[PSCredential]
		$ProxyCredential,

		[Parameter()]
		[switch]
		$AllowClobber,

		[Parameter()]
		[switch]
		$SkipPublisherCheck,

		[Parameter()]
		[switch]
		$Force,

		[Parameter(ParameterSetName = 'NameParameterSet')]
		[switch]
		$AllowPrerelease,

		[Parameter()]
		[switch]
		$AcceptLicense,

		[Parameter()]
		[switch]
		$PassThru
	)

	[hashtable] $parametersWithCredentials = Get-PsBoundParametersWithCredential -parameters $PSBoundParameters
	Install-Module @parametersWithCredentials
}

<#
.SYNOPSIS
	A proxy function to Update-Module that first tries to dynamically obtain a Credential if one was not provided.
.DESCRIPTION
	A proxy function to Update-Module that first tries to dynamically obtain a Credential if one was not provided.

	If a Credential is not provided, it will attempt create one by retrieving a Personal Access Token (PAT) from the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables.

	The Update-Module help can be viewed at: https://docs.microsoft.com/en-us/powershell/module/powershellget/update-module
.EXAMPLE
	PS C:\> Update-AzureArtifactModule -Name YourModule -Repository YourAzureArtifactsRepositoryName

	This command will attempt to use the 'YourAzureArtifactsRepositoryName' PSRepository to download and update 'YourModule".
.INPUTS
	This function simply proxies to the Update-Module cmdlet.
	View the Update-Module cmdlet input parameters at: https://docs.microsoft.com/en-us/powershell/module/powershellget/update-module#parameters
.OUTPUTS
	This function simply proxies to the Update-Module cmdlet.
	View the Update-Module cmdlet outputs at: https://docs.microsoft.com/en-us/powershell/module/powershellget/update-module#outputs
.NOTES
	If a Credential is not provided, it will attempt create one by retrieving a Personal Access Token (PAT) from the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables.
#>
function Update-AzureArtifactsModule
{
	# Entire Param section was copy-pasted from the Update-Module function: https://github.com/PowerShell/PowerShellGet/blob/development/src/PowerShellGet/public/psgetfunctions/Update-Module.ps1
	# This was done so that we can easily splat this function to the Update-Module function, while providing the same intellisense experience.
	[CmdletBinding(SupportsShouldProcess = $true,
		HelpUri = 'https://go.microsoft.com/fwlink/?LinkID=398576')]
	Param
	(
		[Parameter(ValueFromPipelineByPropertyName = $true,
			Position = 0)]
		[ValidateNotNullOrEmpty()]
		[String[]]
		$Name,

		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[ValidateNotNull()]
		[string]
		$RequiredVersion,

		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[ValidateNotNull()]
		[string]
		$MaximumVersion,

		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[PSCredential]
		$Credential,

		[Parameter()]
		[ValidateSet("CurrentUser", "AllUsers")]
		[string]
		$Scope,

		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[ValidateNotNullOrEmpty()]
		[Uri]
		$Proxy,

		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[PSCredential]
		$ProxyCredential,

		[Parameter()]
		[Switch]
		$Force,

		[Parameter()]
		[Switch]
		$AllowPrerelease,

		[Parameter()]
		[switch]
		$AcceptLicense,

		[Parameter()]
		[switch]
		$PassThru
	)

	[hashtable] $parametersWithCredentials = Get-PsBoundParametersWithCredential -parameters $PSBoundParameters
	Update-Module @parametersWithCredentials
}

<#
.SYNOPSIS
	Installs and updates a module if needed by calling the Install-AzureArtifactsModule and Update-AzureArtifactsModule cmdlets.
.DESCRIPTION
	Installs and updates a module if needed by calling the Install-AzureArtifactsModule and Update-AzureArtifactsModule cmdlets.
	This is purely a convenience cmdlet so that you can install and/or update your modules in a single line of code instead of two.
.EXAMPLE
	```
	Install-AndUpdateAzureArtifactsModule -Name 'ModuleNameInYourFeed' -Repository $repository
	```
	Installs the latest version of ModuleNameInYourFeed if it is not already installed.
	If the module is already installed, it will be updated to the latest version.
.INPUTS
	This function simply proxies to the Install-AzureArtifactsModule and Update-AzureArtifactsModule cmdlets, so it accepts parameters common to those cmdlets and which make sense. These include:

	[string[]] Name
	[string[]] Repository,
	[string] MaximumVersion,
	[PSCredential] Credential,
	[string] Scope,
	[Uri] Proxy,
	[PSCredential] ProxyCredential,
	[switch] Force,
	[switch] AllowPrerelease,
	[switch] AcceptLicense

.OUTPUTS
	This function simply proxies to the Install-AzureArtifactsModule and Update-AzureArtifactsModule cmdlets, so it will return any outputs that they return (typically none).
.NOTES
	If a Credential is not provided, it will attempt create one by retrieving a Personal Access Token (PAT) from the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable, as per https://github.com/Microsoft/artifacts-credprovider#environment-variables.
#>
function Install-AndUpdateAzureArtifactsModule
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true,
			ValueFromPipelineByPropertyName = $true,
			Position = 0)]
		[ValidateNotNullOrEmpty()]
		[string[]] $Name,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string[]] $Repository,

		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[ValidateNotNull()]
		[string] $MaximumVersion,

		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[PSCredential] $Credential,

		[Parameter()]
		[ValidateSet("CurrentUser", "AllUsers")]
		[string] $Scope,

		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[ValidateNotNullOrEmpty()]
		[Uri] $Proxy,

		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[PSCredential] $ProxyCredential,

		[Parameter()]
		[switch] $Force,

		[Parameter()]
		[switch] $AllowPrerelease,

		[Parameter()]
		[switch] $AcceptLicense
	)

	Process
	{
		[hashtable] $parametersWithCredentials = Get-PsBoundParametersWithCredential -parameters $PSBoundParameters
		Install-AzureArtifactsModule @parametersWithCredentials -WarningVariable warnings 3> $null
		Write-UnexpectedInstallModuleWarnings -warnings $warnings

		# The Update-AzureArtifactsModule does not take a Repository parameter, so we must remove it before splatting.
		$parametersWithCredentials = Remove-RepositoryPropertyFromHashTable -hashTable $parametersWithCredentials
		Update-AzureArtifactsModule @parametersWithCredentials
	}

	Begin
	{
		function Write-UnexpectedInstallModuleWarnings([System.Collections.ArrayList] $warnings)
		{
			[System.Management.Automation.WarningRecord[]] $validWarnings = @()
			foreach ($warning in $warnings)
			{
				if (!$warning.ToString().Contains('is already installed'))
				{
					$validWarnings += $warning
				}
			}

			if ($validWarnings.Count -gt 0)
			{
				foreach ($warning in $validWarnings)
				{
					Write-Warning $warning
				}
			}
		}

		function Remove-RepositoryPropertyFromHashTable([hashtable] $hashTable)
		{
			if ($null -ne $hashTable.Repository)
			{
				$hashTable.Remove('Repository')
			}
			return $hashTable
		}
	}
}

function Get-PsBoundParametersWithCredential([hashtable] $parameters)
{
	[PSCredential] $credential = Get-AzureArtifactsCredential -credential $parameters.Credential

	$newParameters = $parameters
	$newParameters.Credential = $credential

	return $newParameters
}

function Get-AzureArtifactsCredential([PSCredential] $credential = $null)
{
	if ($null -ne $credential)
	{
		Write-Verbose "Credentials were explicitly provided, so they will be used."
		return $credential
	}

	[System.Security.SecureString] $personalAccessToken = Get-SecurePersonalAccessTokenFromEnvironmentVariable

	if ($null -ne $personalAccessToken)
	{
		Write-Verbose "Credentials were not explicitly provided, but a Personal Access Token was found, so it will be used."
		$credential = New-Object System.Management.Automation.PSCredential 'Username@DoesNotMatter.com', $personalAccessToken
	}

	if ($null -eq $credential)
	{
		[string] $computerName = $Env:ComputerName
		Write-Warning "Credentials were not explicitly provided, and a Personal Access Token was not found on '$computerName', so we could not dynamically obtain the credential to use."
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

Export-ModuleMember -Function Find-AzureArtifactsModule
Export-ModuleMember -Function Install-AzureArtifactsModule
Export-ModuleMember -Function Install-AndUpdateAzureArtifactsModule
Export-ModuleMember -Function Register-AzureArtifactsPSRepository
Export-ModuleMember -Function Update-AzureArtifactsModule
