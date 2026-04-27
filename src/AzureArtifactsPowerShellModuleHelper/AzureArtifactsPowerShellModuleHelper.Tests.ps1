# These are Integration tests (not unit tests).
# This means that these tests will actually reach out to the specified $FeedUrl and connect/authenticate against it.
# They will also interact with the local machines PowerShell PS Repositories and installed modules.
# In order for these tests to run successfully:
#	- You need to use a real Azure Artifacts $FeedUrl and a real module to import from it.
# 	- You need to use a real Azure Artifacts Personal Access Token (PAT) with package read permissions, stored in an
# 	environment variable called AZURE_ARTIFACTS_TESTING_FEED_PAT, or you can hardcode it in the $AzureArtifactsPersonalAccessToken
# 	variable below, but do not commit that to source control.
# Ideally we would mock out any external/infrastructure dependencies; I just haven't had time to yet so for now hit the real dependencies.

using module '.\AzureArtifactsPowerShellModuleHelper.psm1'

BeforeAll {
	Set-StrictMode -Version Latest

	###########################################################
	# You will need to update the following variables with info to pull a real package down from a real feed.
	###########################################################
	[string] $AzureArtifactsPersonalAccessToken = $Env:AZURE_ARTIFACTS_TESTING_FEED_PAT
	[string] $FeedUrl = 'https://pkgs.dev.azure.com/deadlydog/2fdacc85-2f97-401e-bc68-69090c712dea/_packaging/AzureArtifactsPowerShellModuleHelper-Tests/nuget/v2'
	[string] $PowerShellModuleName = 'FakeModuleFor_AzureArtifactsPowerShellModuleHelper_Tests'
	[string] $ValidOlderModuleVersionThatExists = '1.0.2'
	[string] $InvalidModuleVersionThatDoesNotExist = '1.0.99999'
	[string] $ValidModulePrereleaseVersionThatExists = '1.0.1-alpha'

	[string] $ModuleNameBeingTested = 'AzureArtifactsPowerShellModuleHelper'
	[System.Security.SecureString] $SecurePersonalAccessToken = ($AzureArtifactsPersonalAccessToken | ConvertTo-SecureString -AsPlainText -Force)
	[PSCredential] $Credential = New-Object System.Management.Automation.PSCredential 'Username@DoesNotMatter.com', $SecurePersonalAccessToken
	[System.Version] $MinimumRequiredPowerShellGetModuleVersion = [System.Version]::Parse('2.2.1')

	function Remove-PsRepository([string] $feedUrl)
	{
		$repositories = Get-PSRepository

		# PowerShellGet v2 uses SourceLocation and v3 uses Uri for the feed URL of Get-PSRepository, so check both.
		if ($repositories -and $repositories[0].PSObject.Properties.Name -contains 'SourceLocation')
		{
			$repositories | Where-Object { $_.SourceLocation -ieq $feedUrl } | Unregister-PSRepository
			Get-PSRepository | Where-Object { $_.SourceLocation -ieq $feedUrl } | Should -BeNullOrEmpty
		}
		else
		{
			$repositories | Where-Object { $_.Uri -ieq $feedUrl } | Unregister-PSRepository
			Get-PSRepository | Where-Object { $_.Uri -ieq $feedUrl } | Should -BeNullOrEmpty
		}
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
}

Describe 'Tests setup' {
	It 'Should have the Azure Artifacts Personal Access Token available' {
		$AzureArtifactsPersonalAccessToken | Should -Not -BeNullOrEmpty
	}

	It 'Should have the Feed URL available' {
		$FeedUrl | Should -Not -BeNullOrEmpty
	}

	It 'Should have the PowerShell module name to test with available' {
		$PowerShellModuleName | Should -Not -BeNullOrEmpty
	}
}

Describe 'Registering an Azure Artifacts PS Repository' {
	Context 'When relying on retrieving the Azure Artifacts PAT from the environment variable that exists' {
		BeforeEach {
			Mock Get-SecurePersonalAccessTokenFromEnvironmentVariable { return $SecurePersonalAccessToken } -ModuleName $ModuleNameBeingTested
		}

		It 'Should register a new PS repository properly when relying on PAT from environmental variable' {
			# Arrange.
			[string] $expectedRepository = 'TempTestingFeed'
			Remove-PsRepository -feedUrl $FeedUrl

			# Act.
			[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl -Repository $expectedRepository

			# Assert.
			$repository | Should -Be $expectedRepository
			Get-PSRepository -Name $repository | Should -Not -BeNullOrEmpty
		}

		It 'Should return an existing PS repository properly when no Repository is specified' {
			# Arrange.
			[string] $expectedRepository = 'TempTestingFeed'
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
			[string] $expectedRepository = 'TempTestingFeed'
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
			[string] $expectedRepository = 'TempTestingFeed'
			Remove-PsRepository -feedUrl $FeedUrl

			# Act.
			[string] $repository = ($FeedUrl | Register-AzureArtifactsPSRepository -Repository $expectedRepository)

			# Assert.
			$repository | Should -Be $expectedRepository
			Get-PSRepository -Name $repository | Should -Not -BeNullOrEmpty
		}

		It 'Should register a new PS repository properly when piping in the all of the parameters by property name' {
			# Arrange.
			[string] $expectedRepository = 'TempTestingFeed'
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
		[string] $expectedRepository = 'TempTestingFeed'
		Remove-PsRepository -feedUrl $FeedUrl

		# Act.
		[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl -Repository $expectedRepository -Credential $Credential

		# Assert.
		$repository | Should -Be $expectedRepository
		Get-PSRepository -Name $repository | Should -Not -BeNullOrEmpty
	}

	Context 'When connecting to a feed without using a Credential' {
		BeforeEach {
			Mock Get-AzureArtifactsCredential { return $null } -ModuleName $ModuleNameBeingTested
		}

		It 'Should not throw an error when credentials are not found. (Assumes the FeedUrl allows you to register it without a Credential)' {
			# Arrange.
			[string] $expectedRepository = 'TempTestingFeed'
			Remove-PsRepository -feedUrl $FeedUrl

			# Act.
			[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl -Repository $expectedRepository

			# Assert.
			$repository | Should -Be $expectedRepository
			Get-PSRepository -Name $repository | Should -Not -BeNullOrEmpty
		}
	}
}

Describe 'Finding a PowerShell module from Azure Artifacts' {
	Context 'When relying on retrieving the Azure Artifacts PAT from the environment variable that exists' {
		BeforeEach {
			Mock Get-SecurePersonalAccessTokenFromEnvironmentVariable { return $SecurePersonalAccessToken } -ModuleName $ModuleNameBeingTested
		}

		It 'Should find the module properly' {
			# Arrange.
			[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
			[ScriptBlock] $action = { Find-AzureArtifactsModule -Name $PowerShellModuleName -Repository $repository }

			# Act and Assert.
			$action | Should -Not -BeNullOrEmpty
		}
	}

	Context 'When connecting to a feed without using a Credential' {
		BeforeEach {
			Mock Get-AzureArtifactsCredential { return $null } -ModuleName $ModuleNameBeingTested
		}

		It 'Should throw an exception' {
			# Arrange.
			[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
			[scriptblock] $action = { Find-AzureArtifactsModule -Name $PowerShellModuleName -Repository $repository -ErrorAction Stop }

			# Act and Assert.
			$action | Should -Throw "No match was found for the specified search criteria and module name '$PowerShellModuleName'. Try Get-PSRepository to see all available registered module repositories."
		}
	}

	It 'Should throw an exception when the Credential is invalid' {
		# Arrange.
		[System.Security.SecureString] $invalidPat = 'InvalidPat' | ConvertTo-SecureString -AsPlainText -Force
		[PSCredential] $invalidCredential = New-Object System.Management.Automation.PSCredential 'Username@DoesNotMatter.com', $invalidPat
		[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
		[scriptblock] $action = { Find-AzureArtifactsModule -Name $PowerShellModuleName -Repository $repository -Credential $invalidCredential -ErrorAction Stop }

		# Act and Assert.
		$action | Should -Throw "No match was found for the specified search criteria and module name '$PowerShellModuleName'. Try Get-PSRepository to see all available registered module repositories."
	}
}

Describe 'Installing a PowerShell module from Azure Artifacts' {
	Context 'When relying on retrieving the Azure Artifacts PAT from the environment variable that exists' {
		BeforeEach {
			Mock Get-SecurePersonalAccessTokenFromEnvironmentVariable { return $SecurePersonalAccessToken } -ModuleName $ModuleNameBeingTested
		}

		It 'Should install the module properly' {
			# Arrange.
			[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
			[ScriptBlock] $action = { Install-AzureArtifactsModule -Name $PowerShellModuleName -Repository $repository -ErrorAction Stop }
			Uninstall-PowerShellModule -powerShellModuleName $PowerShellModuleName -ErrorAction 'SilentlyContinue'

			# Act and Assert.
			$action | Should -Not -Throw
			Get-Module -Name $PowerShellModuleName -ListAvailable | Should -Not -BeNullOrEmpty
		}
	}
}

Describe 'Updating a PowerShell module from Azure Artifacts' {
	Context 'When relying on retrieving the Azure Artifacts PAT from the environment variable that exists' {
		BeforeEach {
			Mock Get-SecurePersonalAccessTokenFromEnvironmentVariable { return $SecurePersonalAccessToken } -ModuleName $ModuleNameBeingTested
		}

		It 'Should update the module properly when already installed, resulting in 2 versions being installed' {
			# Arrange.
			[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
			[ScriptBlock] $action = { Update-AzureArtifactsModule -Name $PowerShellModuleName -ErrorAction Stop }
			Uninstall-PowerShellModule -powerShellModuleName $PowerShellModuleName -ErrorAction 'SilentlyContinue'
			Install-AzureArtifactsModule -Name $PowerShellModuleName -Repository $repository -RequiredVersion $ValidOlderModuleVersionThatExists

			# Act and Assert.
			$action | Should -Not -Throw
			$modulesInstalled = Get-Module -Name $PowerShellModuleName -ListAvailable
			$modulesInstalled | Should -Not -BeNullOrEmpty
			$modulesInstalled.Count | Should -BeGreaterThan 1
		}
	}
}

Describe 'Installing-and-Updating a PowerShell module from Azure Artifacts' {
	Context 'When relying on retrieving the Azure Artifacts PAT from the environment variable that exists' {
		BeforeEach {
			Mock Get-SecurePersonalAccessTokenFromEnvironmentVariable { return $SecurePersonalAccessToken } -ModuleName $ModuleNameBeingTested
		}

		It 'Should install the module properly' {
			# Arrange.
			[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
			[ScriptBlock] $action = { Install-AndUpdateAzureArtifactsModule -Name $PowerShellModuleName -Repository $repository -ErrorAction Stop }
			Uninstall-PowerShellModule -powerShellModuleName $PowerShellModuleName -ErrorAction 'SilentlyContinue'

			# Act and Assert.
			$action | Should -Not -Throw
			Get-Module -Name $PowerShellModuleName -ListAvailable | Should -Not -BeNullOrEmpty
		}

		It 'Should update the module properly when already installed, resulting in 2 versions being installed' {
			# Arrange.
			[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
			[ScriptBlock] $action = { Install-AndUpdateAzureArtifactsModule -Name $PowerShellModuleName -Repository $repository -ErrorAction Stop }
			Uninstall-PowerShellModule -powerShellModuleName $PowerShellModuleName -ErrorAction 'SilentlyContinue'
			Install-AzureArtifactsModule -Name $PowerShellModuleName -Repository $repository -RequiredVersion $ValidOlderModuleVersionThatExists

			# Act and Assert.
			$action | Should -Not -Throw
			$modulesInstalled = Get-Module -Name $PowerShellModuleName -ListAvailable
			$modulesInstalled | Should -Not -BeNullOrEmpty
			$modulesInstalled.Count | Should -BeGreaterThan 1
		}
	}
}
