function GetALObjectIdRanges {

    # FindALObjectIdRanges
    # v0.1 - 2026-03-13
    # This script collects the IDs of the AL objects in the app, divides it into ranges and outputs a JSON-snippet that can be copied to the app.json key `idRanges`.

    if(((Get-Item .).Name) -notin @('app', 'test')) {
        Write-Host 'You must call this command from the /app or /test directory' -ForegroundColor Red
        return
    }

    if(-not([bool](Get-ChildItem "app.json" -ErrorAction SilentlyContinue))) {
        Write-Host 'Youre not in the root of an AL project..' - ForegroundColor Red
    }

    $idsFound = @()
    $objectTypes = @('page', 'pageextension', 'table', 'tableextension', 'codeunit', 'report', 'xmlport', 'query', 'permissionset', 'permissionsetextension', 'enum', 'enumextension');
    $objectTypeRegex = '^(' + ($objectTypes -join '|') + ')\s+(\w+)'

    foreach ($file in (Get-ChildItem -Path "./src/**/*.al" -Recurse)) {
        $firstLines = Get-Content -Path $file.FullName -TotalCount 10
        foreach ($line in $firstLines) {
            if ($line -match $objectTypeRegex) {
                
                $objecttype = $matches[1]
                
                $id = $matches[0].split(' ')[1]
                if($id -match '^\d+$') {
                    $idsFound += [int]$id
                }
                
                if($objecttype -notin @('enum', 'enumextension')) {
                    continue
                }
                
                $enumFileLines = Get-Content -Path $file.FullName
                foreach($l in $enumFileLines) {
                    if($l -notmatch 'value\((.+?);') { continue }
                    if($matches[1] -notmatch '^\d+$') { continue }
                    
                    $id = [int]$matches[0]
                    if($id -ge 1000000) { 
                        $idsFound += $id
                    }
                }
            }
        }
    }

    $uniqueIds = (($idsFound | Sort-Object) | Select-Object -Unique)

    if($uniqueIds.Count -eq 0) {
        Write-Host 'No IDs found in the project.' -ForegroundColor Yellow
        return
    }

    # Collect ranges from ID list

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

    $resultObj = @{idRanges=$ranges}
    $resultObj | ConvertTo-Json -Depth 10 | Write-Host
}
Set-Alias GetRanges GetALObjectIdRanges