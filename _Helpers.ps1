function GetPatFromCredentialManager {
    if(-not ([bool](Get-Module -ListAvailable -Name 'CredentialManager'))) {
        Write-Host 'Credential Manager module not found. Installing it now..' -ForegroundColor Yellow
        Install-Module -Name 'CredentialManager' -Force
    }
    Import-Module -Name CredentialManager

    if(-not [bool](Get-StoredCredential -Target devops)) {
        Write-Error 'No DevOps PAT found in CredentialManager. Please set it first.'
        Write-Host "You can generate a PAT in Azure DevOps by going to User Settings > Personal Access Tokens > New Token." -ForegroundColor Yellow
        Write-Host "In Windows, go to Credential Manager > Windows Credentials > Add a generic credential" -ForegroundColor Yellow
        Write-Host "Set the 'Internet or network address' to 'devops', username can be anything (e.g. 'pat') and the password should be your DevOps PAT." -ForegroundColor Yellow
        return
    }

    $patEncoded = (Get-StoredCredential -Target devops).Password;
    $ctmu = [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($patEncoded);
    $pat = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($ctmu);
    [System.Runtime.InteropServices.Marshal]::ZeroFreeCoTaskMemUnicode($ctmu);

    if(-not [bool]$pat) {
        Write-Error 'No DevOps PAT found in CredentialManager. Please set it first.'
        return
    }  
    
    return $pat
}

function DoGetRequest {
    param($url)

    $pat = GetPatFromCredentialManager

    $req = @{
        'Method'      = 'GET'
        'Uri'         = $url
        'Headers'     = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")) }
        'ContentType' = 'application/json'
    }
    return Invoke-RestMethod @req
}