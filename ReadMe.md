# Azure Artifacts PowerShell Module Helper

This is a PowerShell module that contains cmdlets that make it easier to work with PowerShell modules stored in Azure Artifacts (which is part of Azure DevOps).
This includes finding, installing, and updating modules stored in your Azure Artifacts feeds.

One main benefit of this package is not having to provide credentials for every call if you follow [the microsoft guidance to supply an environmental variable][MicrosoftCredentialProviderEnvironmentVariableDocumentationUrl] that contains your Azure Artifacts Personal Access Token (PAT).

This package is available on [the public PowerShell gallery here][PowerShellGalleryPackageUrl].

## Quick-start guide

Assuming you already have [an environment variable with your PAT setup][MicrosoftCredentialProviderEnvironmentVariableDocumentationUrl], you can install your Azure Artifact modules using:

```powershell
Install-Module -Name AzureArtifactsPowerShellModuleHelper -Scope CurrentUser -Force
[string] $repository =
    'https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2' |
    Register-AzureArtifactsPSRepository
Install-AzureArtifactsModule -Name 'ModuleNameInYourFeed' -Repository $repository
```

### Installing this module

The first step is to install this module, which can be done with the PowerShell command:

```powershell
Install-Module -Name AzureArtifactsPowerShellModuleHelper -Scope CurrentUser -Force -RequiredVersion 2.2.2
```

- `-Scope CurrentUser` is used so that admin permissions are not required to install the module.
- `-Force` is used to suppress any user prompts.
- I would typically also recommend using `-MaximumVersion 2.9999` to ensure that scripts using this module continue to work if a breaking change is introduced and the major version is incremented to v3.
However, there is currently [a bug with the `MaximumVersion` parameter](https://github.com/PowerShell/PowerShellGet/issues/562) on some machines, so I wouldn't recommend using it until that gets addressed.
Instead, you can use `-RequiredVersion 2.2.2` (or whatever [the latest version is][PowerShellGalleryPackageUrl]) to ensure you don't accidentally download an update with a breaking change.

Feel free to omit these parameters if needed, but they are recommended if you are using this in an automated script that won't have human intervention.

## Setting up your Personal Access Token

In order to interact with your Azure Artifacts, you will need to have a Personal Access Token (PAT) setup that has appropriate permissions.

You can follow Microsoft's documentation to [create a Personal Access Token (PAT) in Azure DevOps](https://docs.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=azure-devops&tabs=preview-page#create-personal-access-tokens-to-authenticate-access) that has `Read` and `Write` permission under the `Packaging` scope.
If you only plan on consuming packages and not publishing them, then your PAT only requires the `Read` permission.

You can also follow [Microsoft's documentation][MicrosoftCredentialProviderEnvironmentVariableDocumentationUrl] and also [setup a system environment variable on your computer](https://helpdeskgeek.com/how-to/create-custom-environment-variables-in-windows/) with the following values, replacing `YOUR_PERSONAL_ACCESS_TOKEN` with the PAT you created above, and the `endpoint` address with the address of your Azure Artifacts feed.

- Name: `VSS_NUGET_EXTERNAL_FEED_ENDPOINTS`
- Value: `{"endpointCredentials": [{"endpoint":"https://pkgs.dev.azure.com/YourOganization/_packaging/YourFeed/nuget/v3/index.json", "username":"AzureDevOps", "password":"YOUR_PERSONAL_ACCESS_TOKEN"}]}`

Setting up the environment variable is not a hard requirement, but it allows you to avoid creating and passing in the `Credential` parameter, which is one of the main benefits of using this module;
The cmdlets in this module check if the `VSS_NUGET_EXTERNAL_FEED_ENDPOINTS` environment variable is present and create the Crendential object automatically if needed.

### Explicitly using your Personal Access Token

If you do not have the environment variable set, or do not want to use it, the cmdlets allow you to provide a `Credential` parameter.

You can provide a Credential object like this:

```powershell
[System.Security.SecureString] $securePersonalAccessToken = 'YourPatGoesHere' | ConvertTo-SecureString -AsPlainText -Force
[PSCredential] $credential = New-Object System.Management.Automation.PSCredential 'Username@DoesNotMatter.com', $securePersonalAccessToken
[string] $feedUrl = 'https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2'
[string] $repository = Register-AzureArtifactsPSRepository -Credential $credential -FeedUrl $feedUrl
```

If a Credential is provided, it will be used instead of any value stored in the `VSS_NUGET_EXTERNAL_FEED_ENDPOINTS` environment variable.

__NOTE:__ You should avoid committing your Personal Access Token to source control and instead retrieve it from a secure repository, like Azure KeyVault.

## Cmdlets provided by the module

The cmdlets provided by this module are:

- `Register-AzureArtifactsPSRepository`
- `Find-AzureArtifactsModule` (Proxy to [Find-Module][MicrosoftFindModuleDocumentationUrl])
- `Install-AzureArtifactsModule` (Proxy to [Install-Module][MicrosoftInstallModuleDocumentationUrl])
- `Update-AzureArtifactsModule` (Proxy to [Update-Module][MicrosoftUpdateModuleDocumentationUrl])
- `Install-AndUpdateAzureArtifactsModule`

All of the cmdlets take an optional `-Credential` parameter.
When not provided, one will attempt to be created by using the PAT stored in the environment variable if available.

The modules marked as a `Proxy` above are just proxy functions to their respective native PowerShellGet cmdlets.
The only difference is that they attempt to create a Credential to use if one was not provided.
This means that all of the parameters work the exact same way as the native cmdlets.

### `Register-AzureArtifactsPSRepository` cmdlet

Before you can interact with your Azure Artifacts feed, you will need to register it using the `Register-AzureArtifactsPSRepository` cmdlet:

```powershell
[string] $feedUrl = 'https://pkgs.dev.azure.com/YourOrganization/_packaging/YourFeed/nuget/v2'
[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $feedUrl
```

__Important:__ When retrieving your feed's URL from Azure DevOps, it will often specify a `/v3` endpoint.
PowerShell is not yet compatible with the `/v3` endpoint, so you must use `/v2`.

In addition to registering the PSRepository, this cmdlet also makes sure some other requirements are installed, such as the minimum required versions of the NuGet Package Provider and PowerShellGet.

Notice that the cmdlet returns back a Repository name; you may want to save it in a variable.
The repository name can be provided to the other cmdlets via their `-Repository` parameter.
Providing the `-Repository` parameter to those cmdlets is optional, but it can increase performance by not having to scan through other registered repositories, and it can avoid unnecessary warnings if any of those other repositories require different authentication that is not being provided.

If the PSRepository already exists, this cmdlet will simply return back the name of the existing PSRepository for the provided feed.
If you already have a PSRepository setup for your feed and don't want to get the repository name, then you can potentially skip calling this cmdlet.
If this is being used in an automated script however, it's recommended to include it.

You can confirm that your Azure Artifacts feed was registered by running the PowerShell command `Get-PSRepository`, and can remove it if needed using the command `Unregister-PSRepository -Name $repository`.

To get more details on what happens during this process, you can use the Information stream:

```powershell
[string] $repository = Register-AzureArtifactsPSRepository -FeedUrl $feedUrl -InformationAction Continue
```

### `Find-AzureArtifactsModule` cmdlet

After registering your Azure Artifacts repository, you can find modules in it by using the `Find-AzureArtifactsModule` cmdlet:

```powershell
Install-AzureArtifactsModule -Name 'ModuleNameInYourFeed' -Repository $repository
```

The `Find-AzureArtifactsModule` takes all the same parameters as the native [`Find-Module` cmdlet][MicrosoftFindModuleDocumentationUrl].

For example, you can find a specific module version by using the `RequiredVersion` parameter:

```powershell
Find-AzureArtifactsModule -Name 'ModuleNameInYourFeed' -RequiredVersion '1.2.3' -Repository $repository
```

### `Install-AzureArtifactsModule` cmdlet

After registering your Azure Artifacts repository, you can install modules from it by using the `Install-AzureArtifactsModule` cmdlet:

```powershell
Install-AzureArtifactsModule -Name 'ModuleNameInYourFeed' -Repository $repository
```

The `Install-AzureArtifactsModule` takes all the same parameters as the native [`Install-Module` cmdlet][MicrosoftInstallModuleDocumentationUrl].

For example, you can install a specific module version by using the `RequiredVersion` parameter:

```powershell
Install-AzureArtifactsModule -Name 'ModuleNameInYourFeed' -RequiredVersion '1.2.3' -Repository $repository
```

To install a prerelease version, you must also provide the `AllowPrerelease` parameter:

```powershell
Install-AzureArtifactsModule -Name 'ModuleNameInYourFeed' -RequiredVersion '1.2.3-beta1' -AllowPrerelease -Repository $repository
```

### `Update-AzureArtifactsModule` cmdlet

After installing one of the modules, you can update it by using the `Update-AzureArtifactsModule` cmdlet:

```powershell
Update-AzureArtifactsModule -Name 'ModuleNameInYourFeed'
```

### `Install-AndUpdateAzureArtifactsModule` cmdlet

After registering your Azure Artifacts repository, you can install and update your modules by using the `Install-AndUpdateAzureArtifactsModule` cmdlet:

```powershell
Install-AndUpdateAzureArtifactsModule -Name 'ModuleNameInYourFeed' -Repository $repository
```

This cmdlet is a convenience cmdlet that allows you to install and/or update a cmdlet in one line instead of two.
The above command is the equivalent of:

```powershell
Install-AzureArtifactsModule -Name 'ModuleNameInYourFeed' -Repository $repository
Update-AzureArtifactsModule -Name 'ModuleNameInYourFeed'
```

This cmdlet does not take as many parameters as the `Install-AzureArtifactsModule` and `Update-AzureArtifactsModule` cmdlets since not all of them make sense.
For example, it does not provide a `RequiredVersion` parameter because it would not make sense to call both cmdlets using the same `RequiredVersion`.
It also does not provide a `MinimumVersion` parameter because that cannot be used with `Update-AzureArtifactsModule`.

An alternative to this cmdlet would be to use the `Force` parameter with `Install-AzureArtifactsModule`, however that has the downside of downloading and installing the module every time it's called, even if the same version is already installed.

<!-- Links used multiple times -->
[MicrosoftCredentialProviderEnvironmentVariableDocumentationUrl]: https://github.com/Microsoft/artifacts-credprovider#environment-variables
[MicrosoftFindModuleDocumentationUrl]: https://docs.microsoft.com/en-us/powershell/module/powershellget/find-module
[MicrosoftInstallModuleDocumentationUrl]: https://docs.microsoft.com/en-us/powershell/module/powershellget/install-module
[MicrosoftUpdateModuleDocumentationUrl]: https://docs.microsoft.com/en-us/powershell/module/powershellget/update-module
[PowerShellGalleryPackageUrl]: https://www.powershellgallery.com/packages/AzureArtifactsPowerShellModuleHelper
