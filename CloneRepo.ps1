function CloneRepo {

	# CloneRepo
    # v0.2 - 2026-03-23
	# This script helps you to clone one of the commonly used repos, create a branch for your issue and open it in VS Code.

	$repoNames = @(
		"CAPO Interface"
		"DSP"
		"DICO Interface"
		"Construct NL"
	)

	$repoUrls = @(
		"https://4psnl.visualstudio.com/4PS_NL/_git/4PS%20CAPO%20Interface"
		"https://4psnl.visualstudio.com/4PS_NL/_git/4PS%20DSP"
		"https://4psnl.visualstudio.com/4PS_NL/_git/4PS%20DICO%20Interface"
		"https://4psnl.visualstudio.com/4PS_NL/_git/4PSConstructNL"
	)

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

	for ($i = 0; $i -lt $repoNames.Count; $i++) {
		Write-Host "[$($i+1)] $($repoNames[$i])"
	}

	$choice = Read-Host -Prompt ("Enter choice (1-{0}) or multiple choices separated by comma (e.g. 1,3)" -f $repoNames.Count)
	if($choice -lt 1 -or $choice -gt ($repoNames.Count+1)) {
		Write-Host "Invalid choice. " -ForegroundColor Red
		return
	}

    $selected = @{
		name=$repoNames[$choice-1];
		url=$repoUrls[$choice-1]
	}

	Write-Host "Cloning "+$selected['name']+"..." -ForegroundColor Green
	git clone $selected['url'] ("{0}" -f $selected['name'])
	$repoDir = "./"+("{0}" -f $selected['name'])

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