# These are Integration tests (not unit tests).
# This means that these tests will actually reach out to the specified $FeedUrl and connect/authenticate against it.
# In order for these tests to run successfully:
#	- You need to use a real Azure Artifacts $FeedUrl.
#	- You need to have a real Personal Access Token in your environmental variables: https://github.com/Microsoft/artifacts-credprovider#environment-variables
# Ideally we would mock out any external/infrastructure dependencies; I just haven't had time to yet so for now hit the real dependencies.

Set-StrictMode -Version Latest
[string] $THIS_SCRIPTS_PATH = $PSCommandPath
[string] $moduleFilePathToTest = $THIS_SCRIPTS_PATH.Replace('.Tests.ps1', '.psm1') | Resolve-Path
Write-Verbose "Importing the module file '$moduleFilePathToTest' to run tests against it." -Verbose
Import-Module -Name $moduleFilePathToTest -Force

# You will need to update this value to your actual feed URL.
[string] $FeedUrl = 'https://pkgs.dev.azure.com/Organization/_packaging/Feed/nuget/v2'

function Remove-PsRepository([string] $feedUrl)
{
	[PSCustomObject] $psRepository = (Get-PSRepository | Where-Object { $_.SourceLocation -ieq $feedUrl })
	if ($null -ne $psRepository)
	{
		Unregister-PSRepository -Name $psRepository.Name
	}
}

Describe 'Registering an Azure Artifacts PS Repository' {
	It 'Should register a new PS repository properly' {
		# Arrange.
		[string] $expectedRepositoryName = 'AzureArtifactsPowerShellFeed'
		Remove-PsRepository -feedUrl $FeedUrl

		# Act.
		[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $FeedUrl -RepositoryName $expectedRepositoryName

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
