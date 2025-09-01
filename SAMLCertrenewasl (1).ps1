# Parameters
$tenantId = "<Your Tenant ID>"
$clientId = "<Your Client ID>"
$clientSecret = "26B8Q~Ntmj~TW4qIpOU836IaoAawe7xVvzLILbr8"
$appId = "<Your App ID>"  # Azure AD Application (Service Principal) to update SAML certificate for
$newCertSubject = "CN=MyNewSAMLCert"  # Subject for the new certificate
$certPath = "C:\Path\To\ExportedCert.cer"  # Path to export the public certificate

# Connect to Azure AD using Service Principal (as in previous answer)
$securePassword = ConvertTo-SecureString -String $clientSecret -AsPlainText -Force
$credentials = New-Object System.Management.Automation.PSCredential($clientId, $securePassword)

# Connect to Azure AD
Connect-AzureAD -TenantId $tenantId -Credential $credentials

# Generate a new self-signed certificate (or use an existing certificate)
$newCert = New-SelfSignedCertificate -Subject $newCertSubject -KeySpec KeyExchange -CertStoreLocation "cert:\LocalMachine\My"

# Export the certificate to a file (only public part needed for SAML)
Export-Certificate -Cert $newCert -FilePath $certPath

# Obtain the thumbprint of the new certificate
$newCertThumbprint = $newCert.Thumbprint

# Update SAML certificate in Azure AD application (this example assumes you're updating an Azure AD App)
# You must provide the `appId` for the application that uses SAML

# Retrieve the application
$app = Get-AzureADApplication -ObjectId $appId

# Get the current SAML signing certificates (you may want to replace this if there is an old certificate)
$currentCerts = Get-AzureADApplicationKeyCredential -ObjectId $app.ObjectId

# Remove the old signing certificates (optional, but recommended)
foreach ($cert in $currentCerts) {
    Remove-AzureADApplicationKeyCredential -ObjectId $app.ObjectId -KeyId $cert.KeyId
}

# Add the new certificate to the application
$publicCert = Get-Content -Path $certPath -Encoding Byte
$certObject = New-Object -TypeName Microsoft.Open.AzureAD.Model.KeyCredential
$certObject.StartDate = (Get-Date)
$certObject.EndDate = (Get-Date).AddYears(1)  # Set the expiration date for the new certificate
$certObject.KeyId = [guid]::NewGuid().ToString()
$certObject.Type = "AsymmetricX509Cert"
$certObject.Usage = "Sign"
$certObject.Value = [Convert]::ToBase64String($publicCert)

# Add the new certificate
New-AzureADApplicationKeyCredential -ObjectId $app.ObjectId -KeyCredential $certObject

Write-Host "SAML certificate has been renewed and updated successfully."

# Optionally: You can notify your team or stakeholders here or log the details.
