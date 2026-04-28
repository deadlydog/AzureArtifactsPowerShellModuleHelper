# Use .NET 10 runtime as base image
FROM mcr.microsoft.com/dotnet/sdk:10.0

# Install PowerShell
RUN apt-get update && \
    apt-get install -y curl gnupg apt-transport-https && \
    curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - && \
    echo "deb [arch=amd64] https://packages.microsoft.com/repos/microsoft-debian-bullseye-prod bullseye main" > /etc/apt/sources.list.d/microsoft.list && \
    apt-get update && \
    apt-get install -y powershell && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /workspace

# Copy the module and tests into the container
COPY . .

# Set PowerShell as the default shell
SHELL ["pwsh", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# Install required PowerShell modules
RUN Install-Module -Name PowerShellGet -RequiredVersion 2.2.5 -Force && \
    Install-Module -Name Pester -Force

# Run Pester tests
ENTRYPOINT ["pwsh", "-NoProfile", "-Command", "Invoke-Pester -Configuration (New-PesterConfiguration @{ Output = @{ Verbosity = 'Detailed' }})"]
