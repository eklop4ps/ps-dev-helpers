function GetALObjectIdRanges {

    # FindALObjectIdRanges
    # v0.3 - 2026-03-27
    # This script collects the IDs of the AL objects in the app, divides it into ranges and outputs a JSON-snippet that can be copied to the app.json key `idRanges`.

	if(((Get-Item .).Name) -notin @('app', 'test')) {
		if((Get-ChildItem -Directory -Filter "app" -ErrorAction SilentlyContinue)) {
			Write-Host 'Redirecting to app directory...' -ForegroundColor Yellow
			Set-Location "./app"
		} elseif ((Get-ChildItem -Directory -Filter "test" -ErrorAction SilentlyContinue)) {
			Write-Host 'Redirecting to test directory...' -ForegroundColor Yellow
			Set-Location "./test"
		} else {		
			Write-Host 'Cannot find /app or /test directory.. Are you sure you are in an AL project?' -ForegroundColor Red
			return
		}
	}

	if(-not([bool](Get-ChildItem "app.json" -ErrorAction SilentlyContinue))) {
		Write-Host 'No app.json found..' - ForegroundColor Red
		return
	}

	$objectIdsFound = @()
$filesWithInvalidFieldIds = @()
$filesWithInvalidObjectIds = @()

	$objectTypes = @('page', 'pageextension', 'profile', 'table', 'tableextension', 'codeunit', 'report', 'xmlport', 'query', 'permissionset', 'permissionsetextension', 'enum', 'enumextension');
	$objectTypeRegex = '^(' + ($objectTypes -join '|') + ')\s+(\w+)?'
	$counters = @{
		'files_scanned' = 0
		'object_ids_found' = 0
		'invalid_object_ids_found' = 0
		'field_ids_found' = 0
		'invalid_field_ids_found' = 0
	}

	$srcFiles = Get-ChildItem -Path "./**/*.al" -Recurse
	if($srcFiles.Count -eq 0) {
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
				$counters['object_ids_found']++;
			}

			if($objecttype -eq 'profile') {
				$counters['object_ids_found']++;
				continue
			}
			
			if($objecttype -notin @('enum', 'enumextension', 'tableextension')) {
				continue
			}
			
			$fileLines = Get-Content -Path $file.FullName
			foreach($l in $fileLines) {	
				if($objecttype -eq 'tableextension') {
					if($l -notmatch '\s{4}field\((.+?);') { continue }
				} else {
					if($l -notmatch '\s{4}value\((.+?);') { continue }
				}

				if($matches[1] -notmatch '^\d+$') {
					if(-not $filesWithInvalidObjectIds.Contains($file.Name)) {
						$filesWithInvalidObjectIds += $file.Name
					}
					$counters['invalid_ids']++
					continue 
				}
				
				$id = [int]$matches[0]

				if($id -ge 1000000) { 
					$objectIdsFound += $id
					$counters['field_ids_found']++;
				} else {
					if(-not $filesWithInvalidFieldIds.Contains($file.Name)) {
						$filesWithInvalidFieldIds += $file.Name
					}
					$counters['invalid_field_ids_found']++;
					continue
				}
			}
	    }

		if(-not $objectTypeFound) {
			$counters['invalid_object_ids_found']++;

		}
	}

	$uniqueIds = (($objectIdsFound | Sort-Object) | Select-Object -Unique)

    if($uniqueIds.Count -eq 0) {
        Write-Host 'No IDs found in the project.' -ForegroundColor Red
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
	Write-Host "FINISHED!" -ForegroundColor Green
	Write-Host ("{0} id ranges found." -f $ranges.Count) -ForegroundColor Green
	Write-Host " "
	Write-Host "$($counters['files_scanned']) files"
	
	if($counters['object_ids_found'] -gt 0) {
		Write-Host "$($counters['object_ids_found']) valid object ID's"
	}
	if($counters['field_ids_found'] -gt 0) {
		Write-Host "$($counters['field_ids_found']) valid field ID's"
	}
	if($counters['invalid_object_ids_found'] -gt 0) {
		Write-Host "$($counters['invalid_object_ids_found']) invalid object ID's" -ForegroundColor Red
	}
	if($counters['invalid_field_ids_found'] -gt 0) {
		Write-Host "$($counters['invalid_field_ids_found']) invalid field ID's" -ForegroundColor Red
	}

	if($filesWithInvalidObjectIds.Count -gt 0) {
		Write-Host " "
		Write-Host ("Invalid object ID's: ({0}) " -f $filesWithInvalidObjectIds.Count ) -ForegroundColor Red
		Write-Host "------------------------------" -ForegroundColor Red
		$filesWithInvalidObjectIds | ForEach-Object {
			Write-Host $_ -ForegroundColor Red
		}
		Write-Host " "
	}

	if($filesWithInvalidFieldIds.Count -gt 0) {
		Write-Host " "
		Write-Host ("Invalid field ID's: ({0}) " -f $filesWithInvalidFieldIds.Count ) -ForegroundColor Red
		Write-Host "------------------------------" -ForegroundColor Red
		$filesWithInvalidFieldIds | ForEach-Object {
			Write-Host $_ -ForegroundColor Red
		}
		Write-Host " "
	}
	
	$resultObj = @{idRanges=$ranges}
	$resultObjJson = ($resultObj | ConvertTo-Json -Depth 10)
	Set-Clipboard -Value $resultObjJson
	Write-Host "idRanges JSON copied to clipboard!" -ForegroundColor Green
	Write-Host " "
}
Set-Alias GetRanges GetALObjectIdRanges