# Parameters
$tenantId = "06798ab6-9546-46bf-9d4d-76817d80a8a5"
$clientId = "14d82eec-204b-4c2f-b7e8-296a70dab67e"
$clientSecret = "VL~8Q~PX2A6fCxf9JFTMBv95zQPbkpbIBUVhVaMe"
$appId = "29d1d4ea-9f6d-4eb7-ae3c-2080e5768d9b"
$newCertSubject = "CN=MyNewSAMLCert"
$certPath = "C:\ExportedCert.cer"  # Ensure this directory exists
$pfxPath = "C:\ExportedCert.pfx"  # For private key export

# Ensure required modules are installed
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Install-Module -Name Microsoft.Graph -MinimumVersion 1.5.0 -Force -AllowClobber
}
if (-not (Get-Module -ListAvailable -Name MSAL.PS)) {
    Install-Module -Name MSAL.PS -Force -AllowClobber
}

# Connect to Microsoft Graph (Interactive login for simplicity)
Connect-MgGraph -Scopes "Application.ReadWrite.All" -NoWelcome

# Generate new self-signed certificate
try {
    $newCert = New-SelfSignedCertificate -Subject $newCertSubject -KeySpec KeyExchange `
        -KeyExportPolicy Exportable -CertStoreLocation "cert:\LocalMachine\My" `
        -KeyUsage DigitalSignature, KeyEncipherment
    Write-Host "New self-signed certificate generated successfully."
} catch {
    Write-Host "ERROR: Failed to generate self-signed certificate. $_"
    exit 1
}

# Export public certificate
try {
    Export-Certificate -Cert $newCert -FilePath $certPath -Type CERT
    Write-Host "Certificate exported successfully to $certPath."
} catch {
    Write-Host "ERROR: Failed to export the certificate. $_"
    exit 1
}

# Export private key (PFX)
try {
    $password = ConvertTo-SecureString -String "YourPFXPassword" -AsPlainText -Force
    Export-PfxCertificate -Cert $newCert -FilePath $pfxPath -Password $password
    Write-Host "Private key exported successfully to $pfxPath."
} catch {
    Write-Host "ERROR: Failed to export the private key. $_"
    exit 1
}

# Convert public certificate to base64
try {
    $publicCert = Get-Content -Path $certPath -Encoding Byte
    $base64Cert = [Convert]::ToBase64String($publicCert)
} catch {
    Write-Host "ERROR: Failed to convert certificate to Base64. $_"
    exit 1
}

# Get application details
try {
    $app = Get-MgApplication -Filter "appId eq '$appId'"
    if (-not $app) {
        Write-Host "ERROR: Application with App ID $appId not found."
        exit 1
    }
    Write-Host "Application details retrieved successfully."
} catch {
    Write-Host "ERROR: Failed to retrieve application details. $_"
    exit 1
}

# Create new key credential configuration using the correct type
try {
    $keyCredential = [Microsoft.Graph.PowerShell.Models.MicrosoftGraphKeyCredential]@{
        Type          = "AsymmetricX509Cert"
        Usage         = "Verify"
        Key           = [Convert]::FromBase64String($base64Cert)
        StartDateTime = (Get-Date).ToUniversalTime()
        EndDateTime   = (Get-Date).AddYears(1).ToUniversalTime()
        DisplayName   = $newCertSubject
    }

    # Update application with new certificate
    try {
        Update-MgApplication -ApplicationId $app.Id -KeyCredentials @($keyCredential)
        Write-Host "Application updated with new SAML signing certificate successfully."
    } catch {
        Write-Host "ERROR: Failed to update application with new certificate. $_"
        exit 1
    }
} catch {
    Write-Host "ERROR: Failed to create key credential. $_"
    exit 1
}

# Validate token generation with new certificate
try {
    # Load the PFX certificate
    $password = ConvertTo-SecureString -String "YourPFXPassword" -AsPlainText -Force
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($pfxPath, $password)

    # Ensure MSAL.PS is loaded before other modules
    Remove-Module -Name Microsoft.Graph -Force -ErrorAction SilentlyContinue
    Remove-Module -Name MSAL.PS -Force -ErrorAction SilentlyContinue
    Import-Module -Name MSAL.PS

    # Create a client application object
    $clientApp = Get-MsalClientApplication -ClientId $clientId -ClientCertificate $cert -TenantId $tenantId

    # Get the token using the client application object
    $msalToken = $clientApp | Get-MsalToken -Scopes @("https://graph.microsoft.com/.default")

    if ($msalToken) {
        Write-Host "SUCCESS: Token validation successful."
        Write-Host "Certificate Expiration: $($cert.NotAfter)"
        Write-Host "Certificate Thumbprint: $($cert.Thumbprint)"
    }
} catch {
    Write-Host "ERROR: Token validation failed. $_"
}