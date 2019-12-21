# Azure Artifacts PowerShell Module Helper

This is a PowerShell module that contains cmdlets that make it easier to work with PowerShell modules stored in Azure Artifacts (which is part of Azure DevOps).

One main benefit of this package is not having to provide credentials for every call if you follow [the microsoft guidance to supply an environmental variable][MicrosoftCredentialProviderEnvironmentVariableDocumentationUrl] that contains your Azure Artifacts Personal Access Token (PAT).

This package is available on [the public PowerShell gallery here][PowerShellGalleryPackageUrl].

## Quick-start guide

The first step is to install this module, which can be done with the PowerShell command:

```powershell
Install-Module -Name AzureArtifactsPowerShellModuleHelper -Scope CurrentUser -Force -RequiredVersion 2.0.6
```

- `-Scope CurrentUser` is used so that admin permissions are not required to install the module.
- `-Force` is used to suppress any user prompts.
- I would typically also recommend using `-MaximumVersion 2.9999` to ensure that scripts using this module continue to work if a breaking change is introduced and the major version is incremented to v3.
However, there is currently [a bug with the `MaximumVersion` parameter](https://github.com/PowerShell/PowerShellGet/issues/562) on some machines, so I wouldn't recommend using it until that gets addressed.
Instead, you can use `-RequiredVersion 2.0.6` (or whatever [the latest version is][PowerShellGalleryPackageUrl]) to ensure you don't accidentally download an update with a breaking change.

Feel free to omit these parameters if needed, but they are recommended if you are using this in an automated script that won't have human intervention.

Assuming you already have [an environment variable with your PAT setup][MicrosoftCredentialProviderEnvironmentVariableDocumentationUrl], you can install your Azure Artifact modules using:

```powershell
Install-Module -Name AzureArtifactsPowerShellModuleHelper -Scope CurrentUser -Force
'https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2' |
    Register-AzureArtifactsPSRepository
Install-AzureArtifactsModule -Name 'ModuleNameInYourFeed'
```

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

#### Explicitly using your Personal Access Token

If you do not have the environment variable set, or do not want to use it, all of the cmdlets allow you to provide a `Credential` parameter.

You can provide a Credential object like this:

```powershell
[System.Security.SecureString] $securePersonalAccessToken = 'YourPatGoesHere' | ConvertTo-SecureString -AsPlainText -Force
[PSCredential] $Credential = New-Object System.Management.Automation.PSCredential 'Username@DoesNotMatter.com', $securePersonalAccessToken
[string] $feedUrl = 'https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2'
[string] $repository = Register-AzureArtifactsPSRepository -Credential $credential -FeedUrl $feedUrl
```

If a Credential is provided, it will be used instead of any value stored in the `VSS_NUGET_EXTERNAL_FEED_ENDPOINTS` environment variable.

__NOTE:__ You should avoid committing your Personal Access Token to source control and instead retrieve it from a secure repository, like Azure KeyVault.

### Cmdlets provided by the module

The cmdlets provided by this module are:

- `Register-AzureArtifactsPSRepository`
- `Install-AzureArtifactsModule`
- `Find-AzureArtifactsModule`

`Register-AzureArtifactsPSRepository` returns the name of the repository for the Azure Artifacts feed, which can be provided to the other cmdlets via the `-Repository` parameter.
Providing the `-Repository` parameter to those cmdlets is optional, but it can increase performance by not having to scan through other registered repositories, and can avoid unnecessary warnings if any of those other repositories require different authentication that is not being provided.

All of the cmdlets take an optional `-Credential` parameter. When not provided, one will attempt to be created by using the PAT stored in an environment variable.

The `Install-AzureArtifactsModule` is essentially just a proxy to the native [`Install-Module` cmdlet][MicrosoftInstallModuleDocumentationUrl], and `Find-AzureArtifactsModule` to the native [`Find-Module` cmdlet][MicrosoftFindModuleDocumentationUrl], that tries to dynamically create a Credential if one was not provided.
This means that all of the parameters work the exact same way as the native Install-Module and Find-Module cmdlets.

#### Registering your Azure Artifacts provider

Before you can interact with your Azure Artifacts feed, you will need to register it using the `Register-AzureArtifactsPSRepository` cmdlet:

```powershell
[string] $feedUrl = 'https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2'
[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $feedUrl
```

__Important:__ When retrieving your feed's URL from Azure DevOps, it will often specify a `/v3` endpoint.
PowerShell is not yet compatible with the `/v3` endpoint, so you must use `/v2`.

Notice that the cmdlet returns back a Repository Name.
Save this in a variable, as you will need to use this when interacting with other cmdlets in this module.

If you already have a PSRepository setup for your feed then you can potentially skip calling this cmdlet, although it isn't recommended as this cmdlet also makes sure some other requirements are installed, such as the NuGet Package Provider and the minimum required version of PowerShellGet.

You can confirm that your Azure Artifacts feed was registered by running the PowerShell command `Get-PSRepository`, and can remove it if needed using the command `Unregister-PSRepository -Name $repository`.

To get more details on what happens during this process, you can use the Information stream:

```powershell
[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $feedUrl -InformationAction Continue
```

#### Installing a module from your Azure Artifacts

Now that you have your Azure Artifacts feed registered, you can install modules from it by using the `Install-AzureArtifactsModule` module:

```powershell
Install-AzureArtifactsModule -Name 'ModuleNameInYourFeed' -Repository $repository
```

The `Install-AzureArtifactsModule` takes all the same parameters as the native [`Install-Module` cmdlet][MicrosoftInstallModuleDocumentationUrl].

##### Installing a specific version

You can install a specific module version by using the `RequiredVersion` parameter:

```powershell
Install-AzureArtifactsModule -Name 'ModuleNameInYourFeed' -RequiredVersion '1.2.3' -Repository $repository
```

You can also use the typical `MinimumVersion` and `MaximumVersion` parameters as usual.

##### Installing a prerelease version

If you want to install a prerelease version, you must also provide the `AllowPrerelease` parameter:

```powershell
Install-AzureArtifactsModule -Name 'ModuleNameInYourFeed' -RequiredVersion '1.2.3-beta1' -AllowPrerelease -Repository $repository
```

#### Find a module in your Azure Artifacts

After registering your Azure Artifacts, you can find modules in it by using the `Find-AzureArtifactsModule` cmdlet:

```powershell
Install-AzureArtifactsModule -Name 'ModuleNameInYourFeed' -Repository $repository
```

The `Find-AzureArtifactsModule` takes all the same parameters as the native [`Find-Module` cmdlet][MicrosoftFindModuleDocumentationUrl].

##### Finding a specific version

You can find a specific module version by using the `RequiredVersion` parameter:

```powershell
Find-AzureArtifactsModule -Name 'ModuleNameInYourFeed' -RequiredVersion '1.2.3' -Repository $repository
```

You can also use the typical `MinimumVersion` and `MaximumVersion` parameters as usual.

<!-- Links used multiple times -->
[MicrosoftCredentialProviderEnvironmentVariableDocumentationUrl]: https://github.com/Microsoft/artifacts-credprovider#environment-variables
[MicrosoftInstallModuleDocumentationUrl]: https://docs.microsoft.com/en-us/powershell/module/powershellget/install-module
[MicrosoftFindModuleDocumentationUrl]: https://docs.microsoft.com/en-us/powershell/module/powershellget/find-module
[PowerShellGalleryPackageUrl]: https://www.powershellgallery.com/packages/AzureArtifactsPowerShellModuleHelper
