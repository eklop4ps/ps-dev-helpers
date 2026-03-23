function GetALObjectIdRanges {

    # FindALObjectIdRanges
    # v0.2 - 2026-03-23
    # This script collects the IDs of the AL objects in the app, divides it into ranges and outputs a JSON-snippet that can be copied to the app.json key `idRanges`.


	if(((Get-Item .).Name) -notin @('app', 'test')) {
		Write-Host 'You must call this command from the /app or /test directory' -ForegroundColor Red
		return
	}

	if(-not([bool](Get-ChildItem "app.json" -ErrorAction SilentlyContinue))) {
		Write-Host 'Youre not in the root of an AL project..' - ForegroundColor Red
	}

	$objectIdsFound = @()
	$objectTypes = @('page', 'pageextension', 'table', 'tableextension', 'codeunit', 'report', 'xmlport', 'query', 'permissionset', 'permissionsetextension', 'enum', 'enumextension');
	$objectTypeRegex = '^(' + ($objectTypes -join '|') + ')\s+(\w+)'
	$counters = @{
		'files_scanned' = 0
		'ids_found' = 0
		'fields_and_values_found' = 0
		'problems' =0
	}

	$srcFiles = Get-ChildItem -Path "./src/**/*.al" -Recurse
	kf($srcFiles.Count -eq 0) {
		Write-Host 'No AL files found in the /src directory.' -ForegroundColor Red
		return
	}

	$counters['files_scanned'] = $srcFiles.Count

	foreach ($file in $srcFiles) {
	    $firstLines = Get-Content -Path $file.FullName -TotalCount 25
		$objectTypeFound = $false
	    foreach ($line in $firstLines) {

	        if ($line -notmatch $objectTypeRegex) {
				continue
			}

			$objecttype = $matches[1]
			$objectTypeFound = $true
			
			$id = $matches[0].split(' ')[1]
			if($id -match '^\d+$') {
				$objectIdsFound += [int]$id
				$counters['ids_found'] += 1
			}
			
			if($objecttype -notin @('enum', 'enumextension', 'tableextension')) {
				continue
			}
			
			$fileLines = Get-Content -Path $file.FullName
			foreach($l in $fileLines) {	
				if($objecttype -eq 'tableextension') {
					if($l -notmatch '\sfield\((.+?);') { continue }
				} else {
					if($l -notmatch '\svalue\((.+?);') { continue }
				}

				if($matches[1] -notmatch '^\d+$') { 
					Write-Host ("Non numeric ID found in file {0}: {1}" -f $file.FullName, $matches[1]) -ForegroundColor Yellow
					$counters['problems']++
					continue 
				}
				
				$id = [int]$matches[0]
				if($id -ge 1000000) { 
					$objectIdsFound += $id
					$counters['fields_and_values_found'] += 1
				} else {
					Write-Host ("ID found in file {0} is below 1000000 and will be ignored: {1}" -f $file.FullName, $id) -ForegroundColor Yellow
					$counters['problems']++
					continue
				}
			}
	    }

		if(-not $objectTypeFound) {
			Write-Host ("No object type found in file {0}" -f $file.FullName) -ForegroundColor Yellow
			$counters['problems']++
		}
	}

	$uniqueIds = (($objectIdsFound | Sort-Object) | Select-Object -Unique)

    if($uniqueIds.Count -eq 0) {
        Write-Host 'No IDs found in the project.' -ForegroundColor Yellow
        return
    }

    # Create ranges from the unique IDs

	$start = $null
    $length = 0
    $ranges = @()
    
    foreach ($id in $uniqueIds) {
        if ($null -eq $start) {
            $start = $id
            $length = 1
            continue
        }
        
        if ($id -eq $start + $length) {
            $length++
            continue
        }
        
        if ($length -eq 1) {
            $ranges += @{from=$start; to=$start}
        } else {
            $ranges += @{from=$start; to=($start + $length - 1)}
        }
        
        $start = $id
        $length = 1
    }
    
    if ($null -ne $start) {
        if ($length -eq 1) {
            $ranges += @{from=$start; to=$start}
        } else {
            $ranges += @{from=$start; to=($start + $length - 1)}
        }
    }

    if($ranges.Count -eq 0) {
        Write-Host 'No IDs found in the project.' -ForegroundColor Yellow
        return
    }
	Write-Host " "
	Write-Host "FINISHED:" -ForegroundColor Green
	Write-Host " "
	Write-Host ("Scanned: {0} " -f $counters['files_scanned'])
	Write-Host ("IDs found: {0} " -f $counters['ids_found'])
	Write-Host ("Fields and values found: {0} " -f $counters['fields_and_values_found'])
	Write-Host ("Problems: {0} " -f $counters['problems'] )
	Write-Host " "
	$resultObj = @{idRanges=$ranges}
	$resultObjJson = ($resultObj | ConvertTo-Json -Depth 10)
	Write-Host $resultObjJson -ForegroundColor Cyan
	Set-Clipboard -Value $resultObjJson
	Write-Host "Copied to clipboard" -ForegroundColor Green
}
Set-Alias GetRanges GetALObjectIdRanges