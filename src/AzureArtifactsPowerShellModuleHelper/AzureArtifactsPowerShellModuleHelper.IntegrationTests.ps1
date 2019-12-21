# These are Integration tests (not unit tests).
# This means that these tests will actually reach out to the specified $FeedUrl and connect/authenticate against it.
# In order for these tests to run successfully:
#	- You need to use a real Azure Artifacts $FeedUrl and a real module to import from it.
# Ideally we would mock out any external/infrastructure dependencies; I just haven't had time to yet so for now hit the real dependencies.

param
(
	[Parameter(Mandatory = $false, HelpMessage = 'The Personal Access Token to use to connect to the Azure Artifacts feed.')]
	[string] $AzureArtifactsPersonalAccessToken = 'YourPatGoesHereButDoNotCommitItToSourceControl'
)

Set-StrictMode -Version Latest
[string] $THIS_SCRIPTS_PATH = $PSCommandPath
[string] $moduleFilePathToTest = $THIS_SCRIPTS_PATH.Replace('.IntegrationTests.ps1', '.psm1') | Resolve-Path
Write-Verbose "Importing the module file '$moduleFilePathToTest' to run tests against it." -Verbose
Import-Module -Name $moduleFilePathToTest -Force
[string] $ModuleNameBeingTested = ((Split-Path -Path $moduleFilePathToTest -Leaf) -split '\.')[0] # Filename without the extension.

###########################################################
# You will need to update the following variables with info to pull a real package down from a real feed.
###########################################################
# [string] $FeedUrl = 'https://pkgs.dev.azure.com/Organization/_packaging/Feed/nuget/v2'
[string] $FeedUrl = 'https://pkgs.dev.azure.com/iqmetrix/_packaging/iqmetrix/nuget/v2'
[string] $PowerShellModuleName = 'IQ.DataCenter.ServerConfiguration'
[string] $ValidModuleVersionThatExists = '1.0.40'
[string] $InvalidModuleVersionThatDoesNotExist = '1.0.99999'
[string] $ValidModulePrereleaseVersionThatExists = '1.0.66-ci20191121T214736'
[System.Security.SecureString] $SecurePersonalAccessToken = ($AzureArtifactsPersonalAccessToken | ConvertTo-SecureString -AsPlainText -Force)
[PSCredential] $Credential = New-Object System.Management.Automation.PSCredential 'Username@DoesNotMatter.com', $SecurePersonalAccessToken
[System.Version] $MinimumRequiredPowerShellGetModuleVersion = [System.Version]::Parse('2.2.1')

function Remove-PsRepository([string] $feedUrl)
{
	Get-PSRepository | Where-Object { $_.SourceLocation -ieq $feedUrl } | Unregister-PSRepository
	Get-PSRepository | Where-Object { $_.SourceLocation -ieq $feedUrl } | Should -BeNullOrEmpty
}

function Remove-PowerShellModule([string] $powerShellModuleName)
{
	Remove-Module -Name $powerShellModuleName -Force -ErrorAction SilentlyContinue
	Get-Module -Name $powerShellModuleName | Should -BeNullOrEmpty
}

function Uninstall-PowerShellModule([string] $powerShellModuleName)
{
	Remove-PowerShellModule -powerShellModuleName $powerShellModuleName
	Uninstall-Module -Name $powerShellModuleName -AllVersions -Force
	Get-Module -Name $powerShellModuleName -ListAvailable | Should -BeNullOrEmpty
}

Describe 'Registering an Azure Artifacts PS Repository' {
	Context 'When relying on retrieving the Azure Artifacts PAT from the environment variable that exists' {
		Mock Get-SecurePersonalAccessTokenFromEnvironmentVariable { return $SecurePersonalAccessToken } -ModuleName $ModuleNameBeingTested

		It 'Should register a new PS repository properly when relying in PAT from environmental variable' {
			# Arrange.
			[string] $expectedRepository = 'AzureArtifactsPowerShellFeed'
			Remove-PsRepository -feedUrl $FeedUrl

			# Act.
			[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl -Repository $expectedRepository

			# Assert.
			$repository | Should -Be $expectedRepository
			Get-PSRepository -Name $repository | Should -Not -BeNullOrEmpty
		}

		It 'Should return an existing PS repository properly when no Repository is specified' {
			# Arrange.
			[string] $expectedRepository = 'AzureArtifactsPowerShellFeed'
			Remove-PsRepository -feedUrl $FeedUrl
			Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl -Repository $expectedRepository

			# Act.
			[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl

			# Assert.
			$repository | Should -Be $expectedRepository
			Get-PSRepository -Name $repository | Should -Not -BeNullOrEmpty
		}

		It 'Should return an existing PS repository properly when a different Repository is specified' {
			# Arrange.
			[string] $expectedRepository = 'AzureArtifactsPowerShellFeed'
			Remove-PsRepository -feedUrl $FeedUrl
			Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl -Repository $expectedRepository

			# Act.
			[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl -Repository 'NameThatShouldNotEndUpInThePSRepositories'

			# Assert.
			$repository | Should -Be $expectedRepository
			Get-PSRepository -Name $repository | Should -Not -BeNullOrEmpty
		}

		It 'Should register a new PS repository properly when piping in the Feed URL' {
			# Arrange.
			[string] $expectedRepository = 'AzureArtifactsPowerShellFeed'
			Remove-PsRepository -feedUrl $FeedUrl

			# Act.
			[string] $repository = ($FeedUrl | Register-AzureArtifactsPSRepository -Repository $expectedRepository)

			# Assert.
			$repository | Should -Be $expectedRepository
			Get-PSRepository -Name $repository | Should -Not -BeNullOrEmpty
		}

		It 'Should register a new PS repository properly when piping in the all of the parameters by property name' {
			# Arrange.
			[string] $expectedRepository = 'AzureArtifactsPowerShellFeed'
			[PSCustomObject] $params = [PSCustomObject]@{
				FeedUrl = $FeedUrl
				Repository = $expectedRepository
				Credential = $Credential
				Scope = 'CurrentUser'
			}
			Remove-PsRepository -feedUrl $FeedUrl

			# Act.
			[string] $repository = ($params | Register-AzureArtifactsPSRepository)

			# Assert.
			$repository | Should -Be $expectedRepository
			Get-PSRepository -Name $repository | Should -Not -BeNullOrEmpty
		}

		It 'Should import the PowerShellGet module properly when it is not imported yet' {
			# Arrange.
			Remove-PowerShellModule -powerShellModuleName PowerShellGet

			# Act.
			Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl

			# Assert.
			$powerShellGetModuleImported = Get-Module -Name PowerShellGet
			$powerShellGetModuleImported | Should -Not -BeNullOrEmpty
			$powerShellGetModuleImported.Version | Should -BeGreaterOrEqual $MinimumRequiredPowerShellGetModuleVersion
		}

		It 'Should remove the existing too-low PowerShellGet module and import a newer version properly' {
			# Arrange.
			[System.Version] $notHighEnoughPowerShellGetModuleVersion = [System.Version]::Parse('2.0.4')
			Remove-PowerShellModule -powerShellModuleName PowerShellGet
			Install-Module -Name PowerShellGet -RequiredVersion $notHighEnoughPowerShellGetModuleVersion -Force
			Import-Module -Name PowerShellGet -RequiredVersion $notHighEnoughPowerShellGetModuleVersion -Force

			# Act.
			Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl

			# Assert.
			$powerShellGetModuleImported = Get-Module -Name PowerShellGet
			$powerShellGetModuleImported | Should -Not -BeNullOrEmpty
			$powerShellGetModuleImported.Version | Should -BeGreaterOrEqual $MinimumRequiredPowerShellGetModuleVersion
		}

		It 'Should import the PowerShellGet module properly when a high enough version is already imported' {
			# Arrange.
			Remove-PowerShellModule -powerShellModuleName PowerShellGet
			Install-Module -Name PowerShellGet -MinimumVersion $MinimumRequiredPowerShellGetModuleVersion -Force
			Import-Module -Name PowerShellGet -MinimumVersion $MinimumRequiredPowerShellGetModuleVersion

			# Act.
			Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl

			# Assert.
			$powerShellGetModuleImported = Get-Module -Name PowerShellGet
			$powerShellGetModuleImported | Should -Not -BeNullOrEmpty
			$powerShellGetModuleImported.Version | Should -BeGreaterOrEqual $MinimumRequiredPowerShellGetModuleVersion
		}
	}

	It 'Should register a new PS repository properly when passing in a valid Credential' {
		# Arrange.
		[string] $expectedRepository = 'AzureArtifactsPowerShellFeed'
		Remove-PsRepository -feedUrl $FeedUrl

		# Act.
		[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl -Repository $expectedRepository -Credential $Credential

		# Assert.
		$repository | Should -Be $expectedRepository
		Get-PSRepository -Name $repository | Should -Not -BeNullOrEmpty
	}

	Context 'When connecting to a feed without using a Credential' {
		Mock Get-AzureArtifactsCredential { return $null } -ModuleName $ModuleNameBeingTested

		It 'Should not throw an error when credentials are not found. (Assumes the FeedUrl allows you to register it without a Credential)' {
			# Arrange.
			[string] $expectedRepository = 'AzureArtifactsPowerShellFeed'
			Remove-PsRepository -feedUrl $FeedUrl

			# Act.
			[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl -Repository $expectedRepository

			# Assert.
			$repository | Should -Be $expectedRepository
			Get-PSRepository -Name $repository | Should -Not -BeNullOrEmpty
		}
	}
}

# Describe 'Importing a PowerShell module from Azure Artifacts' {
# 	It 'Should import the module properly' {
# 		# Arrange.
# 		[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
# 		[ScriptBlock] $action = { Import-AzureArtifactsModule -Name $PowerShellModuleName -Repository $repository }
# 		Remove-PowerShellModule -powerShellModuleName $PowerShellModuleName

# 		# Act and Assert.
# 		$action | Should -Not -Throw
# 		Get-Module -Name $PowerShellModuleName | Should -Not -BeNullOrEmpty
# 	}

# 	It 'Should import the module properly when forced' {
# 		# Arrange.
# 		[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
# 		[ScriptBlock] $action = { Import-AzureArtifactsModule -Name $PowerShellModuleName -Repository $repository -Force }
# 		Remove-PowerShellModule -powerShellModuleName $PowerShellModuleName

# 		# Act and Assert.
# 		$action | Should -Not -Throw
# 		Get-Module -Name $PowerShellModuleName | Should -Not -BeNullOrEmpty
# 	}

# 	It 'Should import the module properly when a specific version is requested' {
# 		# Arrange.
# 		[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
# 		[ScriptBlock] $action = { Import-AzureArtifactsModule -Name $PowerShellModuleName -Repository $repository -Version $ValidModuleVersionThatExists }
# 		Remove-PowerShellModule -powerShellModuleName $PowerShellModuleName

# 		# Act and Assert.
# 		$action | Should -Not -Throw
# 		$module = Get-Module -Name $PowerShellModuleName
# 		$module | Should -Not -BeNullOrEmpty
# 		$module.Version | Should -Be $ValidModuleVersionThatExists
# 	}

# 	# Could not get this one to work, as it complains that the module is in use so it's not able to uninstall it to do a proper test.
# 	# It 'Should throw an error when trying to import a version that does not exist and no different version exists' {
# 	# 	# Arrange.
# 	# 	[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
# 	# 	[ScriptBlock] $action = { Import-AzureArtifactsModule -Name $PowerShellModuleName -Repository $repository -Version $InvalidModuleVersionThatDoesNotExist }
# 	# 	Remove-PowerShellModule -powerShellModuleName $PowerShellModuleName
# 	# 	Uninstall-Module -Name $PowerShellModuleName -Force -AllVersions
# 	# 	Write-Host "Versions: " + (Get-Module -Name $PowerShellModuleName -ListAvailable | Format-Table | Out-String)
# 	# 	Get-Module -Name $PowerShellModuleName -ListAvailable | Should -BeNullOrEmpty

# 	# 	# Act and Assert.
# 	# 	$action | Should -Not -Throw
# 	# }

# 	It 'Should write an error and continue when trying to import a version that does not exist, but a different version exists' {
# 		# Arrange.
# 		[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
# 		Import-AzureArtifactsModule -Name $PowerShellModuleName -Repository $repository
# 		Get-Module -Name $PowerShellModuleName -ListAvailable | Should -Not -BeNullOrEmpty

# 		# Act
# 		Import-AzureArtifactsModule -Name $PowerShellModuleName -Repository $repository -Version $InvalidModuleVersionThatDoesNotExist -ErrorAction SilentlyContinue -ErrorVariable err

# 		# Assert.
# 		$err.Count | Should -BeGreaterThan 0
# 		[string] $errors = $err | ForEach-Object { $_.ToString() }
# 		$errors | Should -Match 'is already installed and will be imported instead.'
# 	}

# 	It 'Should throw an error when trying to import a module that does not exist' {
# 		# Arrange.
# 		[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
# 		[ScriptBlock] $action = { Import-AzureArtifactsModule -Name 'InvalidModuleName' -Repository $repository }

# 		# Act and Assert.
# 		$action | Should -Throw "The PowerShell module 'InvalidModuleName' could not be found in the PSRepository"
# 	}

# 	It 'Should write an error and continue when an invalid Repository is specified, but the module is already installed' {
# 		# Arrange.
# 		[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
# 		Import-AzureArtifactsModule -Name $PowerShellModuleName -Repository $repository
# 		Get-Module -Name $PowerShellModuleName -ListAvailable | Should -Not -BeNullOrEmpty

# 		# Act.
# 		Import-AzureArtifactsModule -Name $PowerShellModuleName -Repository 'InvalidRepositoryName' -ErrorAction SilentlyContinue -ErrorVariable err

# 		# Act and Assert.
# 		$err.Count | Should -BeGreaterThan 0
# 		[string] $errors = $err | ForEach-Object { $_.ToString() }
# 		$errors | Should -Match "Version '.+?' is installed on computer '.+?' though so it will be used.*"
# 	}

# 	It 'Should throw an error if the Credential is invalid' {
# 		# Arrange.
# 		[System.Security.SecureString] $invalidPat = 'InvalidPat' | ConvertTo-SecureString -AsPlainText -Force
# 		[PSCredential] $invalidCredential = New-Object System.Management.Automation.PSCredential 'Username@DoesNotMatter.com', $invalidPat
# 		[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl

# 		# Act.
# 		Import-AzureArtifactsModule -Name $PowerShellModuleName -Repository $repository -Credential $invalidCredential -ErrorAction SilentlyContinue -ErrorVariable err

# 		# Assert.
# 		$err.Count | Should -BeGreaterThan 0
# 		[string] $errors = $err | ForEach-Object { $_.ToString() }
# 		$errors | Should -Match "Perhaps the credentials used are not valid."
# 	}

# 	It 'Should not import module Prerelease versions when the Prerelease switch is not provided' {
# 		# Arrange.
# 		[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
# 		[ScriptBlock] $action = { Import-AzureArtifactsModule -Name $PowerShellModuleName -Repository $repository -Version $ValidModulePrereleaseVersionThatExists }
# 		Remove-PowerShellModule -powerShellModuleName $PowerShellModuleName

# 		# Act and Assert.
# 		$action | Should -Throw "The '-AllowPrerelease' parameter must be specified when using the Prerelease string"
# 		Get-Module -Name $PowerShellModuleName | Should -BeNullOrEmpty
# 	}

# 	It 'Should import module Prerelease versions properly' {
# 		# Arrange.
# 		[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
# 		[ScriptBlock] $action = { Import-AzureArtifactsModule -Name $PowerShellModuleName -Repository $repository -Version $ValidModulePrereleaseVersionThatExists -AllowPrerelease }
# 		Remove-PowerShellModule -powerShellModuleName $PowerShellModuleName

# 		# PowerShell is weird about the way it supports prerelease versions.
# 		# The directory it installs to and the version it gives it is just the version with the prerelease portion removed.
# 		# So we need to strip off the prerelease portion of the version number. i.e. what comes after the hyphen.
# 		[string] $prereleaseVersionsStablePortion = ($ValidModulePrereleaseVersionThatExists -split '-')[0]

# 		# Act and Assert.
# 		$action | Should -Not -Throw
# 		$module = Get-Module -Name $PowerShellModuleName
# 		$module | Should -Not -BeNullOrEmpty
# 		$module.Version | Should -Be $prereleaseVersionsStablePortion
# 	}

# 	It 'Should import the module properly when piping in the Repository Name' {
# 		# Arrange.
# 		[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
# 		[ScriptBlock] $action = {
# 			$repository | Import-AzureArtifactsModule -Name $PowerShellModuleName
# 		}
# 		Remove-PowerShellModule -powerShellModuleName $PowerShellModuleName

# 		# Act and Assert.
# 		$action | Should -Not -Throw
# 		Get-Module -Name $PowerShellModuleName | Should -Not -BeNullOrEmpty
# 	}

# 	It 'Should import the module properly when piping in all of the parameters by property name' {
# 		# Arrange.
# 		[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
# 		[PSCustomObject] $params = [PSCustomObject]@{
# 				Name = $PowerShellModuleName
# 				Version = $null
# 				AllowPrerelease = $false
# 				Repository = $repository
# 				Credential = $Credential
# 				Force = $false
# 				Scope = 'CurrentUser'
# 			}
# 		[ScriptBlock] $action = {
# 			$params | Import-AzureArtifactsModule
# 		}
# 		Remove-PowerShellModule -powerShellModuleName $PowerShellModuleName

# 		# Act and Assert.
# 		$action | Should -Not -Throw
# 		Get-Module -Name $PowerShellModuleName | Should -Not -BeNullOrEmpty
# 	}
# }

Describe 'Installing a PowerShell module from Azure Artifacts' {
	It 'Should install the module properly' {
		# Arrange.
		[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
		[ScriptBlock] $action = { Install-AzureArtifactsModule -Name $PowerShellModuleName -Repository $repository -Force -ErrorAction Stop }
		Uninstall-PowerShellModule -powerShellModuleName $PowerShellModuleName

		# Act and Assert.
		$action | Should -Not -Throw
		Get-Module -Name $PowerShellModuleName -ListAvailable | Should -Not -BeNullOrEmpty
	}
}

Describe 'Finding a PowerShell module from Azure Artifacts' {
	Context 'When relying on retrieving the Azure Artifacts PAT from the environment variable that exists' {
		It 'Should find the module properly' {
			# Arrange.
			[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
			[ScriptBlock] $action = { Find-AzureArtifactsModule -Name $PowerShellModuleName -Repository $repository }

			# Act and Assert.
			$action | Should -Not -BeNullOrEmpty
		}
	}

	Context 'When connecting to a feed without using a Credential' {
		Mock Get-AzureArtifactsCredential { return $null } -ModuleName $ModuleNameBeingTested

		It 'Should throw an exception' {
			# Arrange.
			[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
			[scriptblock] $action = { Find-AzureArtifactsModule -Name $PowerShellModuleName -Repository $repository -ErrorAction Stop }

			# Act and Assert.
			$action | Should -Throw "Unable to find repository"
		}
	}

	It 'Should throw an exception when the Credential is invalid' {
		# Arrange.
		[System.Security.SecureString] $invalidPat = 'InvalidPat' | ConvertTo-SecureString -AsPlainText -Force
		[PSCredential] $invalidCredential = New-Object System.Management.Automation.PSCredential 'Username@DoesNotMatter.com', $invalidPat
		[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
		[scriptblock] $action = { Find-AzureArtifactsModule -Name $PowerShellModuleName -Repository $repository -Credential $invalidCredential -ErrorAction Stop }

		# Act and Assert.
		$action | Should -Throw "No match was found for the specified search criteria and module name"
	}
}
