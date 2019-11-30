# These are Integration tests (not unit tests).
# This means that these tests will actually reach out to the specified $FeedUrl and connect/authenticate against it.
# In order for these tests to run successfully:
#	- You need to use a real Azure Artifacts $FeedUrl and a real module to import from it.
#	- You need to have a real Personal Access Token, both in the variables below and in your environmental variables: https://github.com/Microsoft/artifacts-credprovider#environment-variables
# Ideally we would mock out any external/infrastructure dependencies; I just haven't had time to yet so for now hit the real dependencies.

Set-StrictMode -Version Latest
[string] $THIS_SCRIPTS_PATH = $PSCommandPath
[string] $moduleFilePathToTest = $THIS_SCRIPTS_PATH.Replace('.IntegrationTests.ps1', '.psm1') | Resolve-Path
Write-Verbose "Importing the module file '$moduleFilePathToTest' to run tests against it." -Verbose
Import-Module -Name $moduleFilePathToTest -Force

###########################################################
# You will need to update the following variables with info to pull a real package down from a real feed.
###########################################################
# [string] $FeedUrl = 'https://pkgs.dev.azure.com/Organization/_packaging/Feed/nuget/v2'
[string] $FeedUrl = 'https://pkgs.dev.azure.com/iqmetrix/_packaging/iqmetrix/nuget/v2'
[string] $PowerShellModuleName = 'IQ.DataCenter.ServerConfiguration'
[string] $ValidModuleVersionThatExists = '1.0.40'
[string] $InvalidModuleVersionThatDoesNotExist = '1.0.99999'
# DO NOT commit your real PAT to source control!
[System.Security.SecureString] $SecurePersonalAccessToken = 'YourPatGoesHereButDoNotCommitItToSourceControl' | ConvertTo-SecureString -AsPlainText -Force
[System.Management.Automation.PSCredential] $Credential = New-Object System.Management.Automation.PSCredential 'Username@DoesNotMatter.com', $SecurePersonalAccessToken

function Remove-PsRepository([string] $feedUrl)
{
	[PSCustomObject] $psRepository = (Get-PSRepository | Where-Object { $_.SourceLocation -ieq $feedUrl })
	if ($null -ne $psRepository)
	{
		Unregister-PSRepository -Name $psRepository.Name
	}
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
	}

	It 'Should register a new PS repository properly when passing in a valid PAT' {
		# Arrange.
		[string] $expectedRepositoryName = 'AzureArtifactsPowerShellFeed'
		Remove-PsRepository -feedUrl $FeedUrl

		# Act.
		[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl -RepositoryName $expectedRepositoryName -PersonalAccessToken $SecurePersonalAccessToken

		# Assert.
		$repositoryName | Should -Be $expectedRepositoryName
	}

	It 'Should register a new PS repository properly when passing in a valid Credential' {
		# Arrange.
		[string] $expectedRepositoryName = 'AzureArtifactsPowerShellFeed'
		Remove-PsRepository -feedUrl $FeedUrl

		# Act.
		[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl -RepositoryName $expectedRepositoryName -Credential $Credential

		# Assert.
		$repositoryName | Should -Be $expectedRepositoryName
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
	}

	It 'Should throw an error if both a PersonalAccessToken and a Credential are provided' {
		# Arrange.
		[ScriptBlock] $action = { Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl -PersonalAccessToken $null -Credential $null }

		# Act and Assert.
		$action | Should -Throw 'Parameter set cannot be resolved using the specified named parameters.'
	}
}

Describe 'Importing a PowerShell module from Azure Artifacts' {
	It 'Should import the module properly' {
		# Arrange.
		[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
		[ScriptBlock] $action = { Import-AzureArtifactsModule -Name $PowerShellModuleName -RepositoryName $repositoryName }
		Remove-Module -Name $PowerShellModuleName -Force -ErrorAction SilentlyContinue
		Get-Module -Name $PowerShellModuleName | Should -BeNullOrEmpty

		# Act and Assert.
		$action | Should -Not -Throw
		Get-Module -Name $PowerShellModuleName | Should -Not -BeNullOrEmpty
	}

	It 'Should import the module properly when forced' {
		# Arrange.
		[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
		[ScriptBlock] $action = { Import-AzureArtifactsModule -Name $PowerShellModuleName -RepositoryName $repositoryName -Force }
		Remove-Module -Name $PowerShellModuleName -Force -ErrorAction SilentlyContinue
		Get-Module -Name $PowerShellModuleName | Should -BeNullOrEmpty

		# Act and Assert.
		$action | Should -Not -Throw
		Get-Module -Name $PowerShellModuleName | Should -Not -BeNullOrEmpty
	}

	It 'Should import the specified version properly' {
		# Arrange.
		[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl
		[ScriptBlock] $action = { Import-AzureArtifactsModule -Name $PowerShellModuleName -RepositoryName $repositoryName -Version $ValidModuleVersionThatExists }
		Remove-Module -Name $PowerShellModuleName -Force -ErrorAction SilentlyContinue
		Get-Module -Name $PowerShellModuleName | Should -BeNullOrEmpty

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
	# 	Remove-Module -Name $PowerShellModuleName -Force
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
		$errors | Should -Match "Version '.+?' is installed on computer '.+?' though so it will be used.*" #'though so it will be used.'
	}

	It 'Should allow Prerelease versions to be installed' {

	}
}
