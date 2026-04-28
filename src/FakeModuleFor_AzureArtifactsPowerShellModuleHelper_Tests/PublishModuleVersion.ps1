# Use this script to publish versions of the FakeModuleFor_AzureArtifactsPowerShellModuleHelper_Tests module.

[string] $versionToPublish = '1.3.0' # Update this value to the version you want to publish.
[string] $prereleaseVersionLabel = '' # Leave blank for no prerelease label.

[string] $azureArtifactsPersonalAccessToken = $Env:AZURE_ARTIFACTS_TESTING_FEED_PAT
[string] $feedUrl = 'https://pkgs.dev.azure.com/deadlydog/2fdacc85-2f97-401e-bc68-69090c712dea/_packaging/AzureArtifactsPowerShellModuleHelper-Tests/nuget/v3/index.json'
[string] $moduleName = 'FakeModuleFor_AzureArtifactsPowerShellModuleHelper_Tests'
[string] $moduleDirectoryPath = $PSScriptRoot
[string] $moduleManifestFilePath = Join-Path -Path $moduleDirectoryPath -ChildPath "$moduleName.psd1"
[PSCredential] $credential = New-Object System.Management.Automation.PSCredential('AzureArtifacts', (ConvertTo-SecureString -String $azureArtifactsPersonalAccessToken -AsPlainText -Force))

if (-not $azureArtifactsPersonalAccessToken) {
	throw "The environment variable 'AZURE_ARTIFACTS_TESTING_FEED_PAT' is not set. Please set this variable to your Azure Artifacts Personal Access Token and try again."
}

Write-Output "Updating the module manifest version number to '$versionToPublish' with prerelease label '$prereleaseVersionLabel'."
[string] $manifestContents = Get-Content -Path $moduleManifestFilePath -Raw
$versionReplacedContents = [regex]::Replace($manifestContents, "ModuleVersion = '.*?'", "ModuleVersion = '$versionToPublish'")
$prereleaseLabelReplacedContents = [regex]::Replace($versionReplacedContents, "Prerelease = '.*?'", "Prerelease = '$prereleaseVersionLabel'")
Set-Content -Path $moduleManifestFilePath -Value $prereleaseLabelReplacedContents -Encoding UTF8 -NoNewline
Test-ModuleManifest -Path $moduleManifestFilePath

# Get the PSRepository if it exists, otherwise register it.
$psRepository = Get-PSResourceRepository | Where-Object { $_.Uri -eq $feedUrl } | Select-Object -First 1
if (-not $psRepository) {
	Write-Output "Registering the PSRepository for the feed URL '$feedUrl'."
	$psRepository = Register-PSResourceRepository -Name DeadlydogTestingFeed -Uri $feedUrl -Trusted -PassThru
}

Write-Output "Publishing new version of the module to '$($psRepository.Uri)'."
Publish-PSResource -Path $moduleDirectoryPath -Repository $psRepository.Name -ApiKey AzureDevOps -Credential $credential
