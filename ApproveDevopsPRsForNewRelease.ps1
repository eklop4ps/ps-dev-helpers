#Requires -Version 5.0
<#
.SYNOPSIS
    GUI to auto-approve Azure DevOps pull requests from dev/* to release/* branches

.DESCRIPTION
    Launches a Windows Forms based UI that finds and approves active pull requests
    in Azure DevOps where the source branch matches 'dev/*' and the target branch
    matches 'release/*'.

    The Azure DevOps Personal Access Token is expected in $global:DEVOPS_PAT.
    Run "code $profile" to persist it in your PowerShell profile.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------------------------------------------------------------------------
# Startup checks
# ---------------------------------------------------------------------------
if (-not [bool]$global:DEVOPS_PAT) {
    $msg = @'
$global:DEVOPS_PAT is not set. 

1. Open your Powershell profile in VS Code with command: code $profile
2. Add this line: $global:DEVOPS_PAT = '...'
3. Restart Powershell

Profile location:
{0}
'@ -f $profile
    
    [System.Windows.Forms.MessageBox]::Show($msg, 'Missing Azure DevOps PAT',
    [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    Write-Error $msg -ErrorAction Stop
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
$script:MatchingPRs = @()
$script:Headers     = $null
$script:BaseUrl     = $null
$script:UserId      = $null

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Log {
    param(
        [string]$Message,
        [System.Drawing.Color]$Color = [System.Drawing.Color]::Black
    )

    if (-not $script:LogBox) { return }

    $script:LogBox.SelectionStart  = $script:LogBox.TextLength
    $script:LogBox.SelectionLength = 0
    $script:LogBox.SelectionColor  = $Color
    $script:LogBox.AppendText("$Message`r`n")
    $script:LogBox.SelectionColor  = $script:LogBox.ForeColor
    $script:LogBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Write-LogInfo    { param([string]$m) Write-Log $m ([System.Drawing.Color]::FromArgb(0, 102, 204)) }
function Write-LogSuccess { param([string]$m) Write-Log "OK  $m" ([System.Drawing.Color]::FromArgb(0, 128, 0)) }
function Write-LogError   { param([string]$m) Write-Log "ERR $m" ([System.Drawing.Color]::FromArgb(200, 0, 0)) }
function Write-LogWarn    { param([string]$m) Write-Log "!   $m" ([System.Drawing.Color]::FromArgb(180, 120, 0)) }

function Set-Status {
    param([string]$Text)
    if ($script:StatusLabel) {
        $script:StatusLabel.Text = $Text
        [System.Windows.Forms.Application]::DoEvents()
    }
}

# ---------------------------------------------------------------------------
# Azure DevOps API
# ---------------------------------------------------------------------------
function Initialize-DevOpsContext {
    param(
        [string]$Organization,
        [string]$Project,
        [string]$Token
    )

    $base64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Token"))
    $script:Headers = @{
        Authorization  = "Basic $base64"
        "Content-Type" = "application/json"
    }
    $script:BaseUrl = "https://dev.azure.com/$Organization/$Project/_apis"
}

function Get-Repositories {
    try {
        $url = "$($script:BaseUrl)/git/repositories?api-version=7.0"
        return (Invoke-RestMethod -Uri $url -Headers $script:Headers -Method Get).value
    }
    catch {
        Write-LogError "Failed to fetch repositories: $_"
        return @()
    }
}

function Get-PullRequests {
    param([string]$RepoId)

    try {
        $url = "$($script:BaseUrl)/git/repositories/$RepoId/pullrequests?searchCriteria.status=active&api-version=7.0&`$top=100"
        return (Invoke-RestMethod -Uri $url -Headers $script:Headers -Method Get).value
    }
    catch {
        Write-LogError "Failed to fetch PRs from repo $RepoId : $_"
        return @()
    }
}

function Select-MatchingPullRequests {
    param([array]$PullRequests)

    $result = @()
    foreach ($pr in $PullRequests) {
        if ($pr.sourceRefName -match "^refs/heads/dev/" -and
            $pr.targetRefName -match "^refs/heads/release/") {

            $result += [pscustomobject]@{
                PullRequestId = $pr.pullRequestId
                Title         = $pr.title
                SourceBranch  = $pr.sourceRefName -replace "^refs/heads/", ""
                TargetBranch  = $pr.targetRefName -replace "^refs/heads/", ""
                Status        = $pr.status
                RepositoryId  = $pr.repository.id
                RepoName      = $pr.repository.name
                CreatedBy     = $pr.createdBy.displayName
            }
        }
    }
    return $result
}

function Get-UserIdentity {
    param([string]$Organization)

    try {
        $url = "https://dev.azure.com/$Organization/_apis/connectionData?api-version=7.0-preview.1"
        return (Invoke-RestMethod -Uri $url -Headers $script:Headers -Method Get).authenticatedUser.id
    }
    catch {
        Write-LogError "Failed to get user identity: $_"
        return $null
    }
}

function Approve-PullRequest {
    param(
        [string]$RepoId,
        [string]$RepoName,
        [int]$PRId,
        [string]$UserId
    )

    try {
        $url = "$($script:BaseUrl)/git/repositories/$RepoId/pullrequests/$PRId/reviewers/$UserId"
        $body = @{
            vote      = 10
            isFlagged = $false
        } | ConvertTo-Json

        $putHeaders = @{
            Authorization  = $script:Headers.Authorization
            Accept         = "application/json; api-version=7.0"
            "Content-Type" = "application/json"
        }

        $response = Invoke-RestMethod -Uri $url -Headers $putHeaders -Method Put -Body $body
        Write-LogSuccess "Approved PR #$PRId ($RepoName)"
        return $true
    }
    catch {
        Write-LogError "Failed to approve PR #$PRId ($RepoName) : $_"
        return $false
    }
}

# ---------------------------------------------------------------------------
# UI actions
# ---------------------------------------------------------------------------
function Invoke-FetchPRs {
    $script:ListView.Items.Clear()
    $script:MatchingPRs = @()
    $script:ApproveButton.Enabled = $false

    $org   = $script:OrgBox.Text.Trim()
    $proj  = $script:ProjectBox.Text.Trim()
    $repo  = $script:RepoBox.Text.Trim()
    $token = $global:DEVOPS_PAT

    if (-not $org -or -not $proj) {
        Write-LogError "Organization and Project are required."
        return
    }

    Initialize-DevOpsContext -Organization $org -Project $proj -Token $token
    Set-Status "Connecting to $org/$proj..."
    Write-LogInfo "Connecting to Azure DevOps: $org/$proj"

    try {
        $script:FetchButton.Enabled = $false

        if ($repo) {
            Write-LogInfo "Limiting search to repository: $repo"
            $repos = @([pscustomobject]@{ id = $repo })
        }
        else {
            Write-LogInfo "Fetching all repositories..."
            $repos = Get-Repositories
            Write-LogInfo "Found $($repos.Count) repository(ies)"
        }

        if (-not $repos -or $repos.Count -eq 0) {
            Write-LogError "No repositories found."
            return
        }

        $allPRs = @()
        $i = 0
        foreach ($r in $repos) {
            $i++
            Set-Status "Fetching PRs ($i / $($repos.Count))..."
            $allPRs += Get-PullRequests -RepoId $r.id
        }
        Write-LogInfo "Found $($allPRs.Count) active pull request(s)"

        $script:MatchingPRs = @(Select-MatchingPullRequests -PullRequests $allPRs)

        if ($script:MatchingPRs.Count -eq 0) {
            Write-LogWarn "No PRs match criteria (dev/* -> release/*)."
            Set-Status "No matching PRs."
            return
        }

        foreach ($pr in $script:MatchingPRs) {
            $item = New-Object System.Windows.Forms.ListViewItem($pr.PullRequestId.ToString())
            [void]$item.SubItems.Add($pr.RepoName)
            [void]$item.SubItems.Add($pr.Title)
            [void]$item.SubItems.Add($pr.SourceBranch)
            [void]$item.SubItems.Add($pr.TargetBranch)
            [void]$item.SubItems.Add($pr.CreatedBy)
            $item.Checked = $true
            $item.Tag     = $pr
            [void]$script:ListView.Items.Add($item)
        }

        Write-LogSuccess "$($script:MatchingPRs.Count) matching PR(s) listed."
        Set-Status "$($script:MatchingPRs.Count) matching PR(s)."
        $script:ApproveButton.Enabled = $true
    }
    finally {
        $script:FetchButton.Enabled = $true
    }
}

function Invoke-ApprovePRs {
    $selected = @()
    foreach ($item in $script:ListView.Items) {
        if ($item.Checked) { $selected += $item.Tag }
    }

    if ($selected.Count -eq 0) {
        Write-LogWarn "No PRs selected."
        return
    }

    if ($script:DryRunBox.Checked) {
        Write-LogInfo "[DRY RUN] Would approve $($selected.Count) PR(s):"
        foreach ($pr in $selected) {
            Write-LogInfo "  - PR #$($pr.PullRequestId) ($($pr.RepoName)): $($pr.SourceBranch) -> $($pr.TargetBranch)"
        }
        Set-Status "Dry run complete."
        return
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Approve $($selected.Count) pull request(s)?",
        "Confirm approval",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    if (-not $script:UserId) {
        Set-Status "Getting user identity..."
        $script:UserId = Get-UserIdentity -Organization $script:OrgBox.Text.Trim()
    }
    if (-not $script:UserId) {
        Write-LogError "Could not get user identity for approval."
        return
    }

    try {
        $script:ApproveButton.Enabled = $false
        $script:FetchButton.Enabled   = $false

        $approved = 0
        $i = 0
        foreach ($pr in $selected) {
            $i++
            Set-Status "Approving $i / $($selected.Count)..."
            if (Approve-PullRequest -RepoId $pr.RepositoryId -RepoName $pr.RepoName -PRId $pr.PullRequestId -UserId $script:UserId) {
                $approved++
            }
        }

        Write-LogSuccess "Approved $approved / $($selected.Count) PR(s)."
        Set-Status "Approved $approved / $($selected.Count)."
    }
    finally {
        $script:ApproveButton.Enabled = $true
        $script:FetchButton.Enabled   = $true
        Invoke-FetchPRs
    }
}

# ---------------------------------------------------------------------------
# Build UI
# ---------------------------------------------------------------------------
$form               = New-Object System.Windows.Forms.Form
$form.Text          = "Approve Azure DevOps PRs (dev/* -> release/*)"
$form.Size          = New-Object System.Drawing.Size(980, 680)
$form.StartPosition = "CenterScreen"
$form.MinimumSize   = New-Object System.Drawing.Size(720, 500)

# --- Top input panel ---
$inputPanel = New-Object System.Windows.Forms.TableLayoutPanel
$inputPanel.Dock        = 'Top'
$inputPanel.Height      = 110
$inputPanel.ColumnCount = 4
$inputPanel.RowCount    = 3
$inputPanel.Padding     = New-Object System.Windows.Forms.Padding(10)
[void]$inputPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 110)))
[void]$inputPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent',  50)))
[void]$inputPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 110)))
[void]$inputPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent',  50)))

function New-UILabel {
    param([string]$Text)
    $l = New-Object System.Windows.Forms.Label
    $l.Text      = $Text
    $l.AutoSize  = $false
    $l.Dock      = 'Fill'
    $l.TextAlign = 'MiddleLeft'
    return $l
}

function New-UITextBox {
    param([string]$Text = '')
    $t = New-Object System.Windows.Forms.TextBox
    $t.Text   = $Text
    $t.Dock   = 'Fill'
    $t.Anchor = 'Left,Right'
    return $t
}

$script:OrgBox     = New-UITextBox '4psnl'
$script:ProjectBox = New-UITextBox '4PS_NL'
$script:RepoBox    = New-UITextBox ''

$inputPanel.Controls.Add((New-UILabel "Organization:"), 0, 0)
$inputPanel.Controls.Add($script:OrgBox,                1, 0)
$inputPanel.Controls.Add((New-UILabel "Project:"),      2, 0)
$inputPanel.Controls.Add($script:ProjectBox,            3, 0)

$inputPanel.Controls.Add((New-UILabel "Repository Id:"), 0, 1)
$inputPanel.Controls.Add($script:RepoBox,                1, 1)

$script:DryRunBox = New-Object System.Windows.Forms.CheckBox
$script:DryRunBox.Text     = "Dry run (do not approve)"
$script:DryRunBox.AutoSize = $true
$script:DryRunBox.Dock     = 'Fill'
$inputPanel.Controls.Add($script:DryRunBox, 3, 1)

# Buttons row
$buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$buttonPanel.Dock          = 'Fill'
$buttonPanel.FlowDirection = 'LeftToRight'
$buttonPanel.WrapContents  = $false

$script:FetchButton = New-Object System.Windows.Forms.Button
$script:FetchButton.Text   = "Fetch / Refresh"
$script:FetchButton.Width  = 120
$script:FetchButton.Height = 28
$script:FetchButton.Add_Click({ Invoke-FetchPRs })

$script:ApproveButton = New-Object System.Windows.Forms.Button
$script:ApproveButton.Text    = "Approve selected"
$script:ApproveButton.Width   = 150
$script:ApproveButton.Height  = 28
$script:ApproveButton.Enabled = $false
$script:ApproveButton.Add_Click({ Invoke-ApprovePRs })

$selectAllBtn = New-Object System.Windows.Forms.Button
$selectAllBtn.Text   = "Select all"
$selectAllBtn.Width  = 90
$selectAllBtn.Height = 28
$selectAllBtn.Add_Click({
    foreach ($item in $script:ListView.Items) { $item.Checked = $true }
})

$selectNoneBtn = New-Object System.Windows.Forms.Button
$selectNoneBtn.Text   = "Select none"
$selectNoneBtn.Width  = 90
$selectNoneBtn.Height = 28
$selectNoneBtn.Add_Click({
    foreach ($item in $script:ListView.Items) { $item.Checked = $false }
})

$buttonPanel.Controls.Add($script:FetchButton)
$buttonPanel.Controls.Add($script:ApproveButton)
$buttonPanel.Controls.Add($selectAllBtn)
$buttonPanel.Controls.Add($selectNoneBtn)

$inputPanel.Controls.Add($buttonPanel, 1, 2)
$inputPanel.SetColumnSpan($buttonPanel, 3)

$form.Controls.Add($inputPanel)

# --- Split: list + log ---
$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock             = 'Fill'
$split.Orientation      = 'Horizontal'
$split.SplitterDistance = 320

# ListView
$script:ListView = New-Object System.Windows.Forms.ListView
$script:ListView.Dock          = 'Fill'
$script:ListView.View          = 'Details'
$script:ListView.CheckBoxes    = $true
$script:ListView.FullRowSelect = $true
$script:ListView.GridLines     = $true
[void]$script:ListView.Columns.Add("PR #",   60)
[void]$script:ListView.Columns.Add("Repo",   180)
[void]$script:ListView.Columns.Add("Title",  340)
[void]$script:ListView.Columns.Add("Source", 140)
[void]$script:ListView.Columns.Add("Target", 140)
[void]$script:ListView.Columns.Add("Author", 140)

$split.Panel1.Controls.Add($script:ListView)

# Log box
$script:LogBox = New-Object System.Windows.Forms.RichTextBox
$script:LogBox.Dock      = 'Fill'
$script:LogBox.ReadOnly  = $true
$script:LogBox.Font      = New-Object System.Drawing.Font("Consolas", 9)
$script:LogBox.BackColor = [System.Drawing.Color]::White
$script:LogBox.WordWrap  = $false

$split.Panel2.Controls.Add($script:LogBox)

$form.Controls.Add($split)

# --- Status bar ---
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$script:StatusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$script:StatusLabel.Text = "Ready."
[void]$statusStrip.Items.Add($script:StatusLabel)
$form.Controls.Add($statusStrip)

$split.BringToFront()

$form.Add_Shown({
    Write-LogInfo 'Using token from $global:DEVOPS_PAT.'
})

[void]$form.ShowDialog()
