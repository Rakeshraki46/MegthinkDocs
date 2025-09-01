# Variables for Service Principal Authentication
$tenantId = "06798ab6-9546-46bf-9d4d-76817d80a8a5"   # Replace with your Tenant ID
$clientId = "29d1d4ea-9f6d-4eb7-ae3c-2080e5768d9b"    # Replace with your Client ID
$clientSecret = "26B8Q~Ntmj~TW4qIpOU836IaoAawe7xVvzLILbr8"  # Replace with your Client Secret

# Import the AzureAD Module (or use the newer Microsoft.Graph module if you prefer)
Import-Module AzureAD

# Authenticate using Service Principal
$securePassword = ConvertTo-SecureString -String $clientSecret -AsPlainText -Force
$credentials = New-Object System.Management.Automation.PSCredential($clientId, $securePassword)

# Try to connect to Azure AD using Service Principal authentication
Try {
    Write-Host "Connecting to Azure AD..."
    Connect-AzureAD -TenantId $tenantId -Credential $credentials
    Write-Host "Successfully connected to Azure AD."
} Catch {
    Write-Host "An error occurred during connection: $_"
    Exit
}

# Define application details
$appName = "TestAvira"           # The name of your application
$redirectUri = "https://localhost" # The Redirect URI for the application
$availableToOtherTenants = $false # Set to $true if app should be available to other tenants

# Try to register the application
Try {
    Write-Host "Registering the application..."
    $app = New-AzureADApplication -DisplayName $appName `
                                  -IdentifierUris "https://$($appName).com" `
                                  -ReplyUrls $redirectUri `
                                  -AvailableToOtherTenants $availableToOtherTenants

    if ($app -ne $null) {
        Write-Host "Application registered successfully. Application ID: $($app.ObjectId)"
    } else {
        Write-Host "Failed to register application."
    }
} Catch {
    Write-Host "An error occurred during application registration: $_"
}
