function RenameSourceFiles {
	$renameList = Import-Csv -Path "new-names.csv" -Delimiter ";"

	if (-not (Test-Path -Path "new-names.csv")) {
		Write-Host "CSV file 'new-names.csv' not found. Create a CSV file with two columns: old and new, containing the old and new filename" -ForegroundColor Red
		return
	}

	foreach ($e in $renameList) {
		$oldName = $e.old
		$newName = $e.new

		if (-not $oldName -or -not $newName) {
			Write-Host "Invalid row in CSV: each row must have 'old' and 'new' columns." -ForegroundColor Red
			continue
		}

		$existingFile = (Get-ChildItem . -Recurse -Filter $oldName).FullName

		# if $existingFile contains multiple entries, it will be an array. We should handle that case.
		if ($existingFile -is [array]) {
			Write-Host "Multiple files found for '$oldName':" -ForegroundColor Yellow
			$existingFile | ForEach-Object { Write-Host $_ -ForegroundColor Cyan }
			Write-Host "Skipping '$oldName' due to multiple matches. Fix them manually" -ForegroundColor Yellow
			continue;
		}

		if (-not [bool]$existingFile) {
			Write-Host "File '$oldName' not found in the current directory or subdirectories. Skipping." -ForegroundColor Yellow	
			continue;
		}

		if ($existingFile -and (Test-Path -Path $existingFile)) {
			Rename-Item -Path $existingFile -NewName $newName
			Write-Host "Renamed '$oldName' to '$newName'" -ForegroundColor Green
		}
		else {
			Write-Host "File '$oldName' not found. Skipping." -ForegroundColor Yellow
		}
	}
}
Set-Alias renamefiles RenameSourceFiles