# These are Integration tests (not unit tests).
# This means that these tests will actually reach out to the specified $FeedUrl and connect/authenticate against it.
# In order for these tests to run successfully:
#	- You need to use a real Azure Artifacts $FeedUrl and a real module to import from it.
#	- You need to have a real Personal Access Token, both in the variables below and in your environmental variables: https://github.com/Microsoft/artifacts-credprovider#environment-variables
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
[System.Management.Automation.PSCredential] $Credential = New-Object System.Management.Automation.PSCredential 'Username@DoesNotMatter.com', ($AzureArtifactsPersonalAccessToken | ConvertTo-SecureString -AsPlainText -Force)

function Remove-PsRepository([string] $feedUrl)
{
	Get-PSRepository | Where-Object { $_.SourceLocation -ieq $feedUrl } | Unregister-PSRepository
	Get-PSRepository | Where-Object { $_.SourceLocation -ieq $feedUrl } | Should -BeNullOrEmpty
}

function Remove-PowerShellModule([string] $powerShellModuleName)
{
	Remove-Module -Name $PowerShellModuleName -Force -ErrorAction SilentlyContinue
	# Uninstall-Module -Name $PowerShellModuleName -Force -AllVersions -AllowPrerelease # Commented out because it causes file-in-use errors.
	Get-Module -Name $PowerShellModuleName | Should -BeNullOrEmpty
}

Describe 'Registering an Azure Artifacts PS Repository' {
	It 'Should register a new PS repository properly when relying in PAT from environmental variable' {
		# Arrange.
		[string] $expectedRepositoryName = 'AzureArtifactsPowerShellFeed'
		Remove-PsRepository -feedUrl $FeedUrl

		# Act.
		[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl -RepositoryName $expectedRepositoryName

		# Assert.
		$repositoryName | Should -Be $expectedRepositoryName
		Get-PSRepository -Name $repositoryName | Should -Not -BeNullOrEmpty
	}

	It 'Should register a new PS repository properly when passing in a valid Credential' {
		# Arrange.
		[string] $expectedRepositoryName = 'AzureArtifactsPowerShellFeed'
		Remove-PsRepository -feedUrl $FeedUrl

		# Act.
		[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl -RepositoryName $expectedRepositoryName -Credential $Credential

		# Assert.
		$repositoryName | Should -Be $expectedRepositoryName
		Get-PSRepository -Name $repositoryName | Should -Not -BeNullOrEmpty
	}

	It 'Should return an existing PS repository properly when no RepositoryName is specified' {
		# Arrange.
		[string] $expectedRepositoryName = 'AzureArtifactsPowerShellFeed'
		Remove-PsRepository -feedUrl $FeedUrl
		Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl -RepositoryName $expectedRepositoryName

		# Act.
		[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl

		# Assert.
		$repositoryName | Should -Be $expectedRepositoryName
		Get-PSRepository -Name $repositoryName | Should -Not -BeNullOrEmpty
	}

	It 'Should return an existing PS repository properly when a different RepositoryName is specified' {
		# Arrange.
		[string] $expectedRepositoryName = 'AzureArtifactsPowerShellFeed'
		Remove-PsRepository -feedUrl $FeedUrl
		Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl -RepositoryName $expectedRepositoryName

		# Act.
		[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl -RepositoryName 'NameThatShouldNotEndUpInThePSRepositories'

		# Assert.
		$repositoryName | Should -Be $expectedRepositoryName
		Get-PSRepository -Name $repositoryName | Should -Not -BeNullOrEmpty
	}

	It 'Should register a new PS repository properly when piping in the Feed URL' {
		# Arrange.
		[string] $expectedRepositoryName = 'AzureArtifactsPowerShellFeed'
		Remove-PsRepository -feedUrl $FeedUrl

		# Act.
		[string] $repositoryName = ($FeedUrl | Register-AzureArtifactsPSRepository -RepositoryName $expectedRepositoryName)

		# Assert.
		$repositoryName | Should -Be $expectedRepositoryName
		Get-PSRepository -Name $repositoryName | Should -Not -BeNullOrEmpty
	}

	# It 'Should register a new PS repository properly when piping in the Feed URL and RepositoryName by name' {
	# 	# Arrange.
	# 	[string] $expectedRepositoryName = 'AzureArtifactsPowerShellFeed'
	# 	[hashtable] $params = @{
	# 		FeedUrl = $FeedUrl
	# 		RepositoryName = $expectedRepositoryName
	# 	}
	# 	Remove-PsRepository -feedUrl $FeedUrl

	# 	# Act.
	# 	[string] $repositoryName = ($params | Register-AzureArtifactsPSRepository)

	# 	# Assert.
	# 	$repositoryName | Should -Be $expectedRepositoryName
	# 	Get-PSRepository -Name $repositoryName | Should -Not -BeNullOrEmpty
	# }

	Context 'When connecting to a feed without using a Credential' {
		Mock Get-AzureArtifactsCredential { return $null } -ModuleName $ModuleNameBeingTested

		It 'Should not throw an error when credentials are not found. (Assumes the FeedUrl allows you to register it without a Credential)' {
			# Arrange.
			[string] $expectedRepositoryName = 'AzureArtifactsPowerShellFeed'
			Remove-PsRepository -feedUrl $FeedUrl

			# Act.
			[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl -RepositoryName $expectedRepositoryName

			# Assert.
			$repositoryName | Should -Be $expectedRepositoryName
			Get-PSRepository -Name $repositoryName | Should -Not -BeNullOrEmpty
		}
	}
}

Describe 'Importing a PowerShell module from Azure Artifacts' {
	It 'Should import the module properly' {
		# Arrange.
		[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
		[ScriptBlock] $action = { Import-AzureArtifactsModule -Name $PowerShellModuleName -RepositoryName $repositoryName }
		Remove-PowerShellModule -powerShellModuleName $PowerShellModuleName

		# Act and Assert.
		$action | Should -Not -Throw
		Get-Module -Name $PowerShellModuleName | Should -Not -BeNullOrEmpty
	}

	It 'Should import the module properly when forced' {
		# Arrange.
		[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
		[ScriptBlock] $action = { Import-AzureArtifactsModule -Name $PowerShellModuleName -RepositoryName $repositoryName -Force }
		Remove-PowerShellModule -powerShellModuleName $PowerShellModuleName

		# Act and Assert.
		$action | Should -Not -Throw
		Get-Module -Name $PowerShellModuleName | Should -Not -BeNullOrEmpty
	}

	It 'Should import the specified version properly' {
		# Arrange.
		[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
		[ScriptBlock] $action = { Import-AzureArtifactsModule -Name $PowerShellModuleName -RepositoryName $repositoryName -Version $ValidModuleVersionThatExists }
		Remove-PowerShellModule -powerShellModuleName $PowerShellModuleName

		# Act and Assert.
		$action | Should -Not -Throw
		$module = Get-Module -Name $PowerShellModuleName
		$module | Should -Not -BeNullOrEmpty
		$module.Version | Should -Be $ValidModuleVersionThatExists
	}

	# Could not get this one to work, as it complains that the module is in use so it's not able to uninstall it to do a proper test.
	# It 'Should throw an error when trying to import a version that does not exist and no different version exists' {
	# 	# Arrange.
	# 	[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
	# 	[ScriptBlock] $action = { Import-AzureArtifactsModule -Name $PowerShellModuleName -RepositoryName $repositoryName -Version $InvalidModuleVersionThatDoesNotExist }
	# 	Remove-PowerShellModule -powerShellModuleName $PowerShellModuleName
	# 	Uninstall-Module -Name $PowerShellModuleName -Force -AllVersions
	# 	Write-Host "Versions: " + (Get-Module -Name $PowerShellModuleName -ListAvailable | Format-Table | Out-String)
	# 	Get-Module -Name $PowerShellModuleName -ListAvailable | Should -BeNullOrEmpty

	# 	# Act and Assert.
	# 	$action | Should -Not -Throw
	# }

	It 'Should write an error and continue when trying to import a version that does not exist, but a different version exists' {
		# Arrange.
		[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
		Import-AzureArtifactsModule -Name $PowerShellModuleName -RepositoryName $repositoryName
		Get-Module -Name $PowerShellModuleName -ListAvailable | Should -Not -BeNullOrEmpty

		# Act
		Import-AzureArtifactsModule -Name $PowerShellModuleName -RepositoryName $repositoryName -Version $InvalidModuleVersionThatDoesNotExist -ErrorAction SilentlyContinue -ErrorVariable err

		# Assert.
		$err.Count | Should -BeGreaterThan 0
		[string] $errors = $err | ForEach-Object { $_.ToString() }
		$errors | Should -Match 'is already installed and will be imported instead.'
	}

	It 'Should throw an error when trying to import a module that does not exist' {
		# Arrange.
		[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
		[ScriptBlock] $action = { Import-AzureArtifactsModule -Name 'InvalidModuleName' -RepositoryName $repositoryName }

		# Act and Assert.
		$action | Should -Throw "The PowerShell module 'InvalidModuleName' could not be found in the PSRepository"
	}

	It 'Should write an error and continue when an invalid RepositoryName is specified, but the module is already installed' {
		# Arrange.
		[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
		Import-AzureArtifactsModule -Name $PowerShellModuleName -RepositoryName $repositoryName
		Get-Module -Name $PowerShellModuleName -ListAvailable | Should -Not -BeNullOrEmpty

		# Act.
		Import-AzureArtifactsModule -Name $PowerShellModuleName -RepositoryName 'InvalidRepositoryName' -ErrorAction SilentlyContinue -ErrorVariable err

		# Act and Assert.
		$err.Count | Should -BeGreaterThan 0
		[string] $errors = $err | ForEach-Object { $_.ToString() }
		$errors | Should -Match "Version '.+?' is installed on computer '.+?' though so it will be used.*"
	}

	It 'Should throw an error if the Credential is invalid' {
		# Arrange.
		[System.Security.SecureString] $invalidPat = 'InvalidPat' | ConvertTo-SecureString -AsPlainText -Force
		[System.Management.Automation.PSCredential] $invalidCredential = New-Object System.Management.Automation.PSCredential 'Username@DoesNotMatter.com', $invalidPat
		[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl

		# Act.
		Import-AzureArtifactsModule -Name $PowerShellModuleName -RepositoryName $repositoryName -Credential $invalidCredential -ErrorAction SilentlyContinue -ErrorVariable err

		# Assert.
		$err.Count | Should -BeGreaterThan 0
		[string] $errors = $err | ForEach-Object { $_.ToString() }
		$errors | Should -Match "Perhaps the credentials used are not valid."
	}

	It 'Should not import module Prerelease versions when the Prerelease switch is not provided' {
		# Arrange.
		[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
		[ScriptBlock] $action = { Import-AzureArtifactsModule -Name $PowerShellModuleName -RepositoryName $repositoryName -Version $ValidModulePrereleaseVersionThatExists }
		Remove-PowerShellModule -powerShellModuleName $PowerShellModuleName

		# Act and Assert.
		$action | Should -Throw "The '-AllowPrerelease' parameter must be specified when using the Prerelease string"
		Get-Module -Name $PowerShellModuleName | Should -BeNullOrEmpty
	}

	# Currently fails because we cannot explicitly import prerelease versions that don't conform to System.Version.
	# 	Waiting on an answer to this before proceeding: https://github.com/MicrosoftDocs/PowerShell-Docs/issues/5177
	It 'Should import module Prerelease versions properly' {
		# Arrange.
		[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
		[ScriptBlock] $action = { Import-AzureArtifactsModule -Name $PowerShellModuleName -RepositoryName $repositoryName -Version $ValidModulePrereleaseVersionThatExists -AllowPrerelease }
		Remove-PowerShellModule -powerShellModuleName $PowerShellModuleName

		# PowerShell is weird about the way it supports prerelease versions.
		# The directory it installs to and the version it gives it is just the version with the prerelease portion removed.
		# So we need to strip off the prerelease portion of the version number. i.e. what comes after the hyphen.
		[string] $prereleaseVersionsStablePortion = ($ValidModulePrereleaseVersionThatExists -split '-')[0]

		# Act and Assert.
		$action | Should -Not -Throw
		$module = Get-Module -Name $PowerShellModuleName
		$module | Should -Not -BeNullOrEmpty
		$module.Version | Should -Be $prereleaseVersionsStablePortion
	}
}
