function FindConstructFile {
    Set-Location $PSScriptRoot
    . .\_Helpers.ps1

    if(-not (Test-Path "./paths.json")) {
        $res = DoGetRequest -url "https://4psnl.visualstudio.com/4e4c1481-984c-4784-8eb9-988c831c195b/_apis/git/repositories/334f2573-d859-4775-86bf-17290cbe1ed6/filePaths?versionType=Branch&version=master&versionOptions=None"
        $res.paths | ConvertTo-Json -Depth 50 | Out-File "./paths.json"
        Write-Host "Retrieved $($res.paths.Count) paths and stored in paths.json"
        $paths = $res.paths
    } else {
        $paths = Get-Content "./paths.json" | ConvertFrom-Json
    }

    $q = Read-Host "Enter search query"

    $results = $paths | Where-Object { $_ -like "*$q*.al" }

    if($results.Count -eq 0) {
        Write-Host "No results found for query '$q'"
        return
    }

    # Create a list of objects from the results, by splitting the path and taking the last part as the name
    $results = $results | ForEach-Object {
        $parts = $_ -split "/"
        $objectType = $parts[-1].Split(".")[-2]
        [PSCustomObject]@{
            Index = $results.IndexOf($_)
            Name = $parts[-1].Split(".")[-3]
            Path = $_
            Type = $objectType
        }
    }

    $results = $results | Sort-Object -Property Type

    $results | Format-Table -Property Index,Name,Type,Path

    $selection = Read-Host "Enter index of file to open:"
    
    $selectedFile = $results | Where-Object { $_.Index -eq [int]$selection } | Select-Object -ExpandProperty Path
    if($selectedFile) {
        Start-Process "https://4psnl.visualstudio.com/4PS_NL/_git/4PSConstructNL?path=/$selectedFile"
    }
}
Set-Alias fs FindConstructFile