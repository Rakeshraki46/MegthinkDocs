# Parameters
$tenantId = "06798ab6-9546-46bf-9d4d-76817d80a8a5"
$clientId = "14d82eec-204b-4c2f-b7e8-296a70dab67e"
$clientSecret = "VL~8Q~PX2A6fCxf9JFTMBv95zQPbkpbIBUVhVaMe"
$appId = "fc3708a6-70dc-4dd4-a3d7-ede7b1181a8a"
$newCertSubject = "CN=MyNewSAMLCert"
$certPath = "C:\Path\To\ExportedCert."


# Debugging: Start transcript logging
$logPath = "$PSScriptRoot\SAMLCertRenewal.log"
Start-Transcript -Path $logPath -Append

# Install/Update Microsoft Graph module
try {
    if (-not (Get-Module Microsoft.Graph -ListAvailable)) {
        Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module Microsoft.Graph -Force
}
catch {
    Write-Host "Module installation failed: $_" -ForegroundColor Red
    Exit 1
}

# Connect with token expiration check
function Connect-GraphWithRetry {
    try {
        $context = Get-MgContext
        if (-not $context -or (Get-Date) -ge $context.TokenExpiration) {
            Write-Host "Acquiring new access token..." -ForegroundColor Yellow
            Connect-MgGraph -TenantId $tenantId -ClientId $clientId -ClientSecret $clientSecret -ErrorAction Stop
        }
        Write-Host "Connected to Microsoft Graph (Token expires: $(Get-MgContext).TokenExpiration)" -ForegroundColor Green
    }
    catch {
        Write-Host "Connection failed: $_" -ForegroundColor Red
        Exit 1
    }
}

# Main execution
try {
    # Step 1: Connect to Graph
    Connect-GraphWithRetry

    # Step 2: Certificate generation
    Write-Host "Checking existing certificates..."
    $existingCert = Get-ChildItem "Cert:\LocalMachine\My" | Where-Object { $_.Subject -eq $newCertSubject }
    
    if ($existingCert -and $existingCert.NotAfter -gt (Get-Date).AddDays(7)) {
        Write-Host "Valid certificate found: $($existingCert.Thumbprint)" -ForegroundColor Green
        Exit 0
    }

    Write-Host "Generating new certificate..."
    $newCert = New-SelfSignedCertificate @{
        Subject = $newCertSubject
        KeySpec = 'KeyExchange'
        CertStoreLocation = 'Cert:\LocalMachine\My'
        KeyExportPolicy = 'Exportable'
        KeyLength = 2048
        HashAlgorithm = 'SHA256'
        NotAfter = (Get-Date).AddYears(1)
    }

    # Step 3: Export certificate
    $certFolder = Split-Path $certPath -Parent
    if (-not (Test-Path $certFolder)) { New-Item -Path $certFolder -ItemType Directory -Force | Out-Null }
    Export-Certificate -Cert $newCert -FilePath $certPath -Type CERT -Force
    
    # Step 4: Update Azure AD Application
    Write-Host "Updating application credentials..."
    $certBytes = [System.IO.File]::ReadAllBytes($certPath)
    $keyCredential = @{
        type = "AsymmetricX509Cert"
        usage = "Verify"
        key = [Convert]::ToBase64String($certBytes)
    }
    
    Update-MgApplication -ApplicationId $appId -KeyCredentials @($keyCredential)
    
    # Verification
    $updatedApp = Get-MgApplication -ApplicationId $appId
    $newCreds = $updatedApp.KeyCredentials | Where-Object { $_.KeyId -eq $newCert.Thumbprint }
    
    if ($newCreds) {
        Write-Host "SUCCESS: New certificate deployed (Thumbprint: $($newCert.Thumbprint))" -ForegroundColor Green
    }
    else {
        Write-Host "FAILED: Certificate not found in application credentials" -ForegroundColor Red
    }
}
catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
}
finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Stop-Transcript
    Read-Host "Press Enter to exit..."
}
