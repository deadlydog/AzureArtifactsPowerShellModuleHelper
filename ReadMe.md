# Azure Artifacts PowerShell Module Helper

This is a PowerShell module that contains cmdlets that make it easier to work with PowerShell modules stored in Azure Artifacts (which is part of Azure DevOps).

One main benefit of this package is not having to provide credentials for every call if you follow [the microsoft guidance to supply an environmental variable][MicrosoftCredentialProviderEnvironmentVariableDocumentationUrl] that contains your Azure Artifacts Personal Access Token (PAT).

## Quick-start guide

The first step is to install this module, which can be done with the PowerShell command:

```powershell
Install-Module -Name AzureArtifactsPowerShellModuleHelper -Scope CurrentUser -Force
```

Assuming you already have [an environment variable with your PAT setup][MicrosoftCredentialProviderEnvironmentVariableDocumentationUrl], you can import your Azure Artifact modules using:

```powershell
Install-Module -Name AzureArtifactsPowerShellModuleHelper -Scope CurrentUser -Force
[string] $feedUrl = 'https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2'
[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $feedUrl
Import-AzureArtifactsModule -Name 'ModuleNameInYourFeed' -RepositoryName $repositoryName
```

For more information, continue reading.

## Interacting with your Azure Artifacts

In order to interact with your Azure Artifacts, you will need to have a Personal Access Token (PAT) setup that has appropriate permissions.

### Setting up your Personal Access Token

You can follow Microsoft's documentation to [create a Personal Access Token (PAT) in Azure DevOps](https://docs.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=azure-devops&tabs=preview-page#create-personal-access-tokens-to-authenticate-access) that has `Read` and `Write` permission under the `Packaging` scope.
If you only plan on consuming packages and not publishing them, then your PAT only requires the `Read` permission.

Optionally, you can also follow [Microsoft's documentation][MicrosoftCredentialProviderEnvironmentVariableDocumentationUrl] and also [setup a system environment variable on your computer](https://helpdeskgeek.com/how-to/create-custom-environment-variables-in-windows/) with the following values, replacing `YOUR_PERSONAL_ACCESS_TOKEN` with the PAT you created above, and the `endpoint` address with the address of your Azure Artifacts feed.

- Name: `VSS_NUGET_EXTERNAL_FEED_ENDPOINTS`
- Value: `{"endpointCredentials": [{"endpoint":"https://pkgs.dev.azure.com/YourOganization/_packaging/YourFeed/nuget/v3/index.json", "username":"AzureDevOps", "password":"YOUR_PERSONAL_ACCESS_TOKEN"}]}`

Setting up the environment variable is not a requirement, but it will allow you to avoid creating and passing in the `Credential` parameter to all of the cmdlets in this module.
This is because by default the module will check if the `VSS_NUGET_EXTERNAL_FEED_ENDPOINTS` environment variable is present and extract your PAT from it.

### Registering your Azure Artifacts provider

Before you can interact with your Azure Artifacts feed, you will need to register it using the `Register-AzureArtifactsPSRepository` cmdlet:

```powershell
[string] $feedUrl = 'https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2'
[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $feedUrl
```

__Important:__ When retrieving your feed's URL from Azure DevOps, it will often specify a `/v3` endpoint.
PowerShell is not yet compatible with the `/v3` endpoint, so you must use `/v2`.

Notice that the cmdlet returns back a Repository Name.
Save this in a variable, as you will need to use this when interacting with other cmdlets in this module.

You can confirm that your Azure Artifacts feed was registered by running the PowerShell command `Get-PSRepository`, and can remove it if needed using the command `Unregister-PSRepository -Name $repositoryName`.

To get more details on what happens during this process, you can use the Information stream:

```powershell
[string] $repositoryName = Register-AzureArtifactsPSRepository -FeedUrl $feedUrl -InformationAction Continue
```

### Explicitly using your Personal Access Token

If you do not have the environment variable set, or do not want to use it, all of the cmdlets allow you to provide a `Credential` parameter.

You can provide a Credential object like this:

```powershell
[System.Security.SecureString] $securePersonalAccessToken = 'YourPatGoesHere' | ConvertTo-SecureString -AsPlainText -Force
[System.Management.Automation.PSCredential] $Credential = New-Object System.Management.Automation.PSCredential 'Username@DoesNotMatter.com', $securePersonalAccessToken
[string] $feedUrl = 'https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2'
[string] $repositoryName = Register-AzureArtifactsPSRepository -Credential $credential -FeedUrl $feedUrl
```

If a Credential is provided, it will be used instead of any value stored in the `VSS_NUGET_EXTERNAL_FEED_ENDPOINTS` environment variable.

__NOTE:__ You should avoid committing your Personal Access Token to source control and instead retrieve it from a secure repository, like Azure KeyVault.

### Importing a module from your Azure Artifacts

Now that you have your Azure Artifacts feed registered, you can import it by using the `Import-AzureArtifactsModule` module:

```powershell
Import-AzureArtifactsModule -Name 'ModuleNameInYourFeed' -RepositoryName $repositoryName
```

The `$repositoryName` is the value that was returned from the `Register-AzureArtifactsPSRepository` cmdlet above.

The module will be installed if necessary, and then imported.

To get more details on what version was installed and imported, you can use the Information stream:

```powershell
Import-AzureArtifactsModule -Name 'ModuleNameInYourFeed' -RepositoryName $repositoryName -InformationAction Continue
```

#### Importing a specific version

You can import a specific module version by using the `Version` parameter:

```powershell
Import-AzureArtifactsModule -Name 'ModuleNameInYourFeed' -Version '1.2.3' -RepositoryName $repositoryName
```

#### Importing a prerelease version

If you want to install and import a prerelease version, you must also provide the `AllowPrerelease` parameter:

```powershell
Import-AzureArtifactsModule -Name 'ModuleNameInYourFeed' -Version '1.2.3-beta1' -AllowPrerelease -RepositoryName $repositoryName
````

#### Force a download and reinstall

Use the `Force` parameter to force a module to be downloaded and installed, even if it already exists on the computer:

```powershell
Import-AzureArtifactsModule -Name 'ModuleNameInYourFeed' -Force -RepositoryName $repositoryName
```

[MicrosoftCredentialProviderEnvironmentVariableDocumentationUrl]: https://github.com/Microsoft/artifacts-credprovider#environment-variables
