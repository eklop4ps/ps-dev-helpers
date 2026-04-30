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

function CloneRepo {

	# CloneRepo
    # v0.2 - 2026-03-23
	# This script helps you to clone one of the commonly used repos, create a branch for your issue and open it in VS Code.
	
	$pat = GetPatFromCredentialManager

	$req = @{'Method' = 'GET';'Uri' = 'https://dev.azure.com/4psnl/4e4c1481-984c-4784-8eb9-988c831c195b/_apis/git/repositories?api-version=7.1';'Headers' = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")) };'ContentType' = 'application/json'}

	$repos = Invoke-RestMethod @req
	
	$repoSelection = $repos.value | Where-Object { $_.name.StartsWith("4PS") }

	if(-not $repoSelection) {
		Write-Host "No repositories found or failed to fetch repositories." -ForegroundColor Red
		return
	}

	if(-not ([bool]$global:DEV_ROOT)) {
        Write-Host "DEV_ROOT environment variable not set." -ForegroundColor Red
        Write-Host "1. Run command 'code `$profile'" -ForegroundColor Yellow
        Write-Host "2. Add this line to the top of the file:" -ForegroundColor Yellow
        Write-Host "    `$global:DEV_ROOT = 'C:\dev\...';" -ForegroundColor Green
        Write-Host "3. Replace the path with the full path to the root directory of your AL projects" -ForegroundColor Yellow
        Write-Host "4. Restart Powershell/Terminal" -ForegroundColor Yellow

        return
    }

	Set-Location $global:DEV_ROOT
	
	$TicketNo = Read-Host -Prompt 'Enter issue no: '
	if(-not $TicketNo) {
		Write-Host "No issue number provided. Aborting." -ForegroundColor Red
		return
	}
	if(-not $TicketNo.StartsWith('FBE-')) {
		$TargetDir = "FBE-${TicketNo}"
	}
	
	if(-not (Test-Path $TargetDir )) {
		New-Item -ItemType Directory -Path $TargetDir  | Out-Null
		Write-Host "Created directory: $TargetDir" -ForegroundColor Green
	}

	Set-Location $TargetDir

	Write-Host "Choose repo to clone:" -ForegroundColor Cyan

	for ($i = 0; $i -lt $repoSelection.Count; $i++) {
		# remove the first part of the repo name (4PS.) to make it more readable in the selection list 
		if($i -lt 9) {
			$spacer = " "
		} else {
			$spacer = ""
		}

		Write-Host "[$($i+1)$($spacer)] $($repoSelection[$i].name.Substring(4))"
	}

	$choice = [int](Read-Host -Prompt ("Enter choice (1-{0})" -f $repoSelection.Count))
	if($choice -lt 1 -or $choice -gt $repoSelection.Count) {
		Write-Host "Invalid choice." -ForegroundColor Red
		return
	}

    $selected = @{
		name=$repoSelection[$choice-1].name;
		url=$repoSelection[$choice-1].remoteUrl
	}

	Write-Host "Cloning "+$selected.name+"..." -ForegroundColor Green
	git clone $selected.url ("{0}" -f $selected.name)
	$repoDir = "./"+("{0}" -f $selected.name)

	Set-Location $repoDir
	$targetBranchName = "feature/FBE-${TicketNo}"

	if(-not ([bool](git branch --list "master"))) {
		Write-Host "Master branch not found.."
		return
	}

	if([bool](git branch --list -r "origin/$targetBranchName")) {
		git checkout $targetBranchName
	} else {
		if((Read-Host -Prompt "Create branch '${targetBranchName}'? (y/n)") -eq 'y') {
			git checkout -b $targetBranchName master
		}
	}

	$workspaceFile = Get-ChildItem -Path "." -Filter "*.code-workspace" -Recurse -File | Select-Object -First 1
	if($workspaceFile) {
		code -r $workspaceFile.FullName
	} else {
		code -r .
	}
}
Set-Alias cr CloneRepo