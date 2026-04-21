function CleanUpRepo {

    # CleanUpRepo
    # v0.1 - 2026-04-21
	# This script searches recusively for files with the extension .app, launch.json and directories named .alpackages and deletes them. Use this script to quickly clean up your AL project folder.
	
	$currentDirectory = Get-Location
	$appFiles = Get-ChildItem -Path $currentDirectory -Filter *.app
	$launchJsonFile = Get-ChildItem -Path $currentDirectory -Filter launch.json -Recurse
	$alPackagesDirectory = Get-ChildItem -Path $currentDirectory -Filter .alpackages -Directory -Recurse
	$itemsToDelete = $appFiles + $launchJsonFile + $alPackagesDirectory
	if ($itemsToDelete.Count -eq 0) {
		Write-Host "No files or directories found to delete." -ForegroundColor Yellow
		return
	}
	Write-Host "The following files and directories will be deleted:"
	$itemsToDelete | ForEach-Object { Write-Host $_.FullName -ForegroundColor Red }
	if ((Read-Host "Do you want to proceed? (y)") -eq "y") {
		foreach ($item in $itemsToDelete) {
			if ($item.PSIsContainer) {
				Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
			}
			else {
				Remove-Item -Path $item.FullName -Force -ErrorAction SilentlyContinue
			}
		}
		Write-Host "Selected files and directories have been deleted." -ForegroundColor Green
	}
 else {
		Write-Host "Deletion cancelled by the user." -ForegroundColor Yellow
	}
	Read-Host -Prompt 'Press a key to exit'
}
Set-Alias cleanup CleanUpRepo