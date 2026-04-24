# This is a fake dummy module that will be published to an Azure DevOps Artifacts feed.
# This is used when testing the AzureArtifactsPowerShellModuleHelper module to ensure that
# it can successfully install packages from an Azure DevOps Artifacts feed.

function Get-HelloWorld {
	[CmdletBinding()]
	Param ()

	Write-Output "Hello, World!"
}
