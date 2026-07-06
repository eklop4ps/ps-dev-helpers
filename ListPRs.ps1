function GetPatFromCredentialManager {
  if (-not ([bool](Get-Module -ListAvailable -Name 'CredentialManager'))) {
    Write-Host 'Credential Manager module not found. Installing it now..' -ForegroundColor Yellow
    Install-Module -Name 'CredentialManager' -Force
  }
  Import-Module -Name CredentialManager
  
  if (-not [bool](Get-StoredCredential -Target devops)) {
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
  
  if (-not [bool]$pat) {
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

function ListPullRequests {
  
  # ListPullRequests
  # v0.1 - 2026-05-08
  
  $myID = 'c4524801-27c9-6ff5-b223-f8b819edbb4f'
  
  $TargetUrl = "https://dev.azure.com/4psnl/4e4c1481-984c-4784-8eb9-988c831c195b/_apis/git/pullrequests?api-version=7.1&searchCriteria.creatorId=$myID"
  
  $res = DoGetRequest -url $TargetUrl
  
  Write-Host "PUBLISHED"
  $res.value | Where-Object { $_.isDraft -eq $false } | Select-Object -Property title, @{Name = 'RepositoryName'; Expression = { $_.repository.name } }, @{Name = 'CreatedBy'; Expression = { $_.createdBy.displayName } }, creationDate | Sort-Object -Property creationDate | Format-Table
  
  Write-Host "DRAFTS"
  $res.value | Where-Object { $_.isDraft -eq $true } | Select-Object -Property title, @{Name = 'RepositoryName'; Expression = { $_.repository.name } }, @{Name = 'CreatedBy'; Expression = { $_.createdBy.displayName } }, creationDate | Sort-Object -Property creationDate | Format-Table
  
}
Set-Alias listprs ListPullRequests

function ListPullRequestsHtml {
  
  # ListPullRequestsHtml
  # v0.1 - 2026-05-11
  # Renders the current user's pull requests as a pretty HTML page and opens it in the default browser.
  
  param(
  [string]$OutputPath = (Join-Path $env:TEMP "PullRequests.html"),
  [switch]$NoLaunch
  )
  
  $pat = GetPatFromCredentialManager
  if (-not $pat) { return }
  
  $myID = 'c4524801-27c9-6ff5-b223-f8b819edbb4f'
  $projId = '4e4c1481-984c-4784-8eb9-988c831c195b'
  $TargetUrl = "https://dev.azure.com/4psnl/$projId/_apis/git/pullrequests?api-version=7.1&searchCriteria.creatorId=$myID"
  
  $req = @{
    'Method'      = 'GET'
    'Uri'         = $TargetUrl
    'Headers'     = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")) }
    'ContentType' = 'application/json'
  }
  $res = Invoke-RestMethod @req
  
  function Format-PrRows {
    param($prs)
    if (-not $prs -or $prs.Count -eq 0) {
      return '<tr><td colspan="6" class="empty">No pull requests.</td></tr>'
    }
    $sb = New-Object System.Text.StringBuilder
    foreach ($pr in ($prs | Sort-Object -Property creationDate -Descending)) {
      Write-Host $pr
      $title = [System.Web.HttpUtility]::HtmlEncode($pr.title)
      $repo = [System.Web.HttpUtility]::HtmlEncode($pr.repository.name)
      $author = [System.Web.HttpUtility]::HtmlEncode($pr.createdBy.displayName)
      $created = ([datetime]$pr.creationDate).ToString("yyyy-MM-dd HH:mm")
      $latestPolicyStatus = [System.Web.HttpUtility]::HtmlEncode($pr.LatestPolicyStatus)
      $source = ($pr.sourceRefName -replace '^refs/heads/', '')
      $target = ($pr.targetRefName -replace '^refs/heads/', '')
      $branches = [System.Web.HttpUtility]::HtmlEncode("$source -> $target")
      
      $prUrl = "https://4psnl.visualstudio.com/4PS_NL/_git/$($pr.repository.name)/pullrequest/$($pr.pullRequestId)"
      
      [void]$sb.AppendLine("<tr>")
      [void]$sb.AppendLine("  <td class='id'>!$($pr.pullRequestId)</td>")
      [void]$sb.AppendLine("  <td class='title'><a href='$prUrl' target='_blank'>$title</a></td>")
      [void]$sb.AppendLine("  <td>$repo</td>")
      [void]$sb.AppendLine("  <td>$branches</td>")
      [void]$sb.AppendLine("  <td>$latestPolicyStatus</td>")
      [void]$sb.AppendLine("  <td class='date'>$created</td>")
      [void]$sb.AppendLine("</tr>")
    }
    return $sb.ToString()
  }
  
  Add-Type -AssemblyName System.Web
  
  $published = $res.value | Where-Object { $_.isDraft -eq $false } | Sort-Object -Property creationDate -Descending
  $drafts = $res.value | Where-Object { $_.isDraft -eq $true } | Sort-Object -Property creationDate -Descending
  
  $res.value | ForEach-Object {
    
    $url = "https://dev.azure.com/4psnl/4PS_NL/_apis/policy/evaluations?artifactId=vstfs:///CodeReview/CodeReviewId/$projId/$($_.pullRequestId)&api-version=7.1-preview.1"
    $res2 = DoGetRequest -url $url
    if ([bool]$res2.value) {
      $latest = $res2.value | Sort-Object -Property createdDate -Descending | Select-Object -First 1
      $_ | Add-Member -NotePropertyName "LatestPolicyStatus" -NotePropertyValue $latest.status
    }
    else {
      $_ | Add-Member -NotePropertyName "LatestPolicyStatus" -NotePropertyValue "unknown"
    }
  }
  
  $publishedRows = Format-PrRows -prs $published
  $draftRows = Format-PrRows -prs $drafts
  
  $generated = (Get-Date).ToString("yyyy-MM-dd")
  
  $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<title>My Pull Requests</title>
<style>
  :root {
    --bg: #0d1117;
    --panel: #161b22;
    --border: #30363d;
    --text: #e6edf3;
    --muted: #8b949e;
    --accent: #58a6ff;
    --row-hover: #1f2630;
    --draft: #d29922;
    --published: #3fb950;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 32px;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    background: var(--bg);
    color: var(--text);
  }
  h1 { margin: 0 0 4px 0; font-size: 24px; }
  .meta { color: var(--muted); font-size: 13px; margin-bottom: 24px; }
  .section { background: var(--panel); border: 1px solid var(--border); border-radius: 8px; margin-bottom: 24px; overflow: hidden; }
  .section-header { padding: 12px 16px; display: flex; align-items: center; gap: 12px; border-bottom: 1px solid var(--border); }
  .section-header h2 { margin: 0; font-size: 16px; }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 12px; font-size: 12px; font-weight: 600; }
  .badge.published { background: rgba(63,185,80,0.15); color: var(--published); border: 1px solid rgba(63,185,80,0.3); }
  .badge.draft     { background: rgba(210,153,34,0.15); color: var(--draft);     border: 1px solid rgba(210,153,34,0.3); }
  table { width: 100%; border-collapse: collapse; font-size: 14px; }
  th, td { padding: 10px 16px; text-align: left; border-bottom: 1px solid var(--border); vertical-align: top; }
  th { background: #0d1117; color: var(--muted); font-weight: 600; text-transform: uppercase; font-size: 11px; letter-spacing: 0.05em; }
  tr:last-child td { border-bottom: none; }
  tbody tr:hover { background: var(--row-hover); }
  td.id { color: var(--muted); font-family: ui-monospace, SFMono-Regular, Menlo, monospace; white-space: nowrap; }
  td.title a { color: var(--accent); text-decoration: none; font-weight: 500; }
  td.title a:hover { text-decoration: underline; }
  td.date { color: var(--muted); white-space: nowrap; }
  td.empty { color: var(--muted); text-align: center; font-style: italic; padding: 24px; }
</style>
</head>
<body>
  <h1>My Pull Requests</h1>
  <div class="meta">Generated $generated &middot; $($res.value.Count) total</div>
  
  <div class="section">
    <div class="section-header">
      <h2>Published</h2>
      <span class="badge published">$($published.Count)</span>
    </div>
    <table>
      <thead>
        <tr><th>ID</th><th>Title</th><th>Repo</th><th>Branches</th><th>Status</th><th>Created</th></tr>
      </thead>
      <tbody>
        $publishedRows
      </tbody>
    </table>
  </div>
  
  <div class="section">
    <div class="section-header">
      <h2>Drafts</h2>
      <span class="badge draft">$($drafts.Count)</span>
    </div>
    <table>
      <thead>
        <tr><th>ID</th><th>Title</th><th>Repo</th><th>Branches</th><th>Status</th><th>Created</th></tr>
      </thead>
      <tbody>
        $draftRows
      </tbody>
    </table>
  </div>
</body>
</html>
"@
  
  $html | Out-File -FilePath $OutputPath -Encoding utf8
  Write-Host "Wrote $OutputPath" -ForegroundColor Green
  
  if (-not $NoLaunch) {
    Start-Process $OutputPath
  }
}
Set-Alias listprshtml ListPullRequestsHtml