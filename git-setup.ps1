# =============================================================
#  git-multi-account  (PowerShell)
#  Interactive multi-GitHub-account manager.
#
#  FIRST-TIME SETUP (run once):
#    powershell -ExecutionPolicy Bypass -File .\git-setup.ps1
#
#  It walks you through adding accounts (unlimited), guides SSH
#  key creation/reuse per account, writes ~/.ssh/config, saves
#  ~/.git-accounts, and installs helper functions into $PROFILE.
#
#  After setup, reload:  . $PROFILE
#  Then type:  githelp
# =============================================================

$ErrorActionPreference = "Continue"
$AccountsFile = Join-Path $HOME ".git-accounts"
$SshDir       = Join-Path $HOME ".ssh"
$SshConfig    = Join-Path $SshDir "config"
$MarkStart    = "# >>> git-multi-account >>>"
$MarkEnd      = "# <<< git-multi-account <<<"

function Say($m){ Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m){  Write-Host "  OK $m" -ForegroundColor Green }
function Warn($m){ Write-Host "  ! $m" -ForegroundColor Yellow }
function Ask($p,$d=""){
    if($d){ $a = Read-Host "$p [$d]"; if([string]::IsNullOrWhiteSpace($a)){ return $d } return $a }
    else { return (Read-Host "$p") }
}

if(-not (Test-Path $SshDir)){ New-Item -ItemType Directory -Path $SshDir -Force | Out-Null }

function Add-OneAccount {
    Write-Host ""
    Say "New account"
    $label = ""
    while(-not $label){
        $label = (Ask "  Short label (letters/numbers, e.g. bibek)") -replace '[^A-Za-z0-9_-]',''
        if(-not $label){ Warn "Label can't be empty." }
    }
    $user  = Ask "  GitHub username (e.g. questbibek)"
    $email = Ask "  Email for commits"

    $defaultKey = Join-Path $SshDir "id_ed25519_$label"
    if(Test-Path $defaultKey){
        Ok "Found existing key: $defaultKey"; $keypath = $defaultKey
    } else {
        Write-Host ""; Warn "No key found at $defaultKey"
        $gen = Ask "  Generate a new SSH key for '$label'? (y/n)" "y"
        if($gen.ToLower() -eq "y"){
            Write-Host "  (when prompted for a passphrase, press Enter twice for none)" -ForegroundColor DarkGray
            ssh-keygen -t ed25519 -C "$label-github" -f $defaultKey
            $keypath = $defaultKey; Ok "Key created: $defaultKey"
        } else {
            $keypath = Ask "  Path to an existing private key" $defaultKey
        }
    }

    $pub = "$keypath.pub"
    if(Test-Path $pub){
        Write-Host ""
        Say "Add THIS public key to GitHub for '$user':"
        Write-Host "  https://github.com/settings/ssh/new"
        Write-Host "  ----------------------------------------------------------------"
        Write-Host ("  " + (Get-Content $pub -Raw).Trim())
        Write-Host "  ----------------------------------------------------------------"
        Read-Host "  Press Enter AFTER you've added it to GitHub"
    }

    $hostAlias = "github.com-$label"
    $existing = if(Test-Path $SshConfig){ Get-Content $SshConfig -Raw } else { "" }
    if($existing -notmatch "(?m)^Host\s+$([regex]::Escape($hostAlias))\s*$"){
        $keyFwd = $keypath -replace '\\','/'
        $block = "`nHost $hostAlias`n    HostName github.com`n    User git`n    IdentityFile $keyFwd`n    IdentitiesOnly yes`n"
        Add-Content -Path $SshConfig -Value $block -Encoding UTF8
        Ok "Added SSH alias: $hostAlias"
    } else { Ok "SSH alias $hostAlias already present" }

    Write-Host ""
    Say "Testing connection (you should see: Hi $user!)..."
    ssh -o StrictHostKeyChecking=accept-new -T "git@$hostAlias" 2>&1 | ForEach-Object { "    $_" }

    "$label|$user|$email|$keypath|$hostAlias" | Add-Content -Path $AccountsFile -Encoding UTF8
    Ok "Saved account '$label'"
}

function Run-Wizard {
    Write-Host ""
    Say "Git Multi-Account Setup"
    if(-not (Test-Path $AccountsFile)){ New-Item -ItemType File -Path $AccountsFile -Force | Out-Null }
    $more = "y"
    while($more.ToLower() -eq "y"){
        Add-OneAccount
        Write-Host ""
        $more = Ask "Add another account? (y/n)" "n"
    }

    Write-Host ""
    Say "Set the GLOBAL default identity (used for new repos)"
    $accts = Get-Content $AccountsFile | Where-Object { $_ -match '\|' }
    if($accts){
        $labels = $accts | ForEach-Object { ($_ -split '\|')[0] }
        Write-Host "  Accounts: $($labels -join ', ')"
        $pick = Ask "  Which label is the default?" $labels[0]
        $line = $accts | Where-Object { ($_ -split '\|')[0] -eq $pick } | Select-Object -First 1
        if($line){
            $p = $line -split '\|'
            git config --global user.name  $p[1]
            git config --global user.email $p[2]
            Ok "Global default = $pick"
        }
    }
    git config --global --add safe.directory '*' 2>$null

    Install-Helpers
    Write-Host ""
    Ok "Done! Run:  . `$PROFILE   then:  githelp"
}

function Install-Helpers {
    if(-not (Test-Path $PROFILE)){ New-Item -ItemType File -Path $PROFILE -Force | Out-Null }
    $content = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
    if($content -and $content.Contains($MarkStart)){
        $content = [regex]::Replace($content, "(?s)$([regex]::Escape($MarkStart)).*?$([regex]::Escape($MarkEnd))", "")
        Set-Content -Path $PROFILE -Value $content.TrimEnd() -Encoding UTF8
    }
    Add-Content -Path $PROFILE -Value $HelpersBlock -Encoding UTF8
    Ok "Helpers installed into `$PROFILE"
}

# ---- helper block written verbatim into the user's $PROFILE ----
$HelpersBlock = @'
# >>> git-multi-account >>>
$GitAccountsFile = Join-Path $HOME ".git-accounts"
function _GaLine($label){
    if(-not (Test-Path $GitAccountsFile)){ return $null }
    Get-Content $GitAccountsFile | Where-Object { ($_ -split '\|')[0] -eq $label } | Select-Object -First 1
}
function gitwho {
    "user.name : $(git config user.name 2>$null)"
    "user.email: $(git config user.email 2>$null)"
    "origin    : $(git remote get-url origin 2>$null)"
}
function gitaccounts {
    if(-not (Test-Path $GitAccountsFile)){ "No accounts. Run gitsetup."; return }
    "{0,-12} {1,-18} {2}" -f "LABEL","GITHUB USER","EMAIL"
    Get-Content $GitAccountsFile | Where-Object { $_ -match '\|' } | ForEach-Object {
        $p = $_ -split '\|'; "{0,-12} {1,-18} {2}" -f $p[0],$p[1],$p[2]
    }
}
function gituse($label){
    $line = _GaLine $label
    if(-not $line){ "Unknown account: $label (try: gitaccounts)"; return }
    $p = $line -split '\|'; $u=$p[1]; $e=$p[2]; $h=$p[4]
    git config user.name  $u
    git config user.email $e
    $url = git remote get-url origin 2>$null
    if($url){
        $path = $url -replace '.*github\.com[:/]',''
        git remote set-url origin "git@$h`:$path"
    }
    "Switched to '$label' ($u <$e>)"; gitwho
}
function gitclone($label,$url){
    $line = _GaLine $label
    if(-not $line){ "Unknown account: $label (try: gitaccounts)"; return }
    $p = $line -split '\|'; $u=$p[1]; $e=$p[2]; $h=$p[4]
    $or = $url -replace 'https://github.com/','' -replace 'git@github.com:','' -replace 'github.com/','' -replace '\.git$',''
    if(($or.ToCharArray() | Where-Object { $_ -eq '/' }).Count -ne 1){ "Use owner/repo or a full GitHub URL"; return }
    git clone "git@$h`:$or.git"
    if($LASTEXITCODE -eq 0){
        Set-Location (Split-Path $or -Leaf)
        git config user.name $u; git config user.email $e
        "Cloned as '$label' -> $(Get-Location)"
    }
}
function gitnew($label,$repo){
    $line = _GaLine $label
    if(-not $line){ "Unknown account: $label (try: gitaccounts)"; return }
    $p = $line -split '\|'; $u=$p[1]; $e=$p[2]; $h=$p[4]
    git init -b main 2>$null; if($LASTEXITCODE -ne 0){ git init }
    git config user.name $u; git config user.email $e
    if($repo){
        git remote add origin "git@$h`:$u/$repo.git" 2>$null
        if($LASTEXITCODE -ne 0){ git remote set-url origin "git@$h`:$u/$repo.git" }
        "Remote: git@$h`:$u/$repo.git"
    }
    "Initialized here as '$label' ($u <$e>)"
}
function gitsetup { powershell -ExecutionPolicy Bypass -File "$HOME\.git-setup.ps1" }
Set-Alias gitadd-account gitsetup
function githelp {
@"

  Git Multi-Account - commands
  ----------------------------------------------------------
  gitaccounts            list configured accounts
  gitwho                 show current repo identity + remote
  gituse <label>         switch current repo to an account
  gitclone <label> <url> clone a repo as an account (owner/repo or full URL)
  gitnew <label> [repo]  init a NEW repo here as an account (+remote if repo given)
  gitsetup               re-run the wizard (add accounts, fix keys)

  Per-account shortcuts (auto-generated): git-<label>, <label>-clone, <label>-init
  Plain: gs=status  gcm "msg"=commit  gp=push  gl=pull
  ----------------------------------------------------------
"@
}
function gs { git status }
function gcm { param([string]$m) git commit -m $m }
function gp { git push }
function gl { git pull }
# auto-generate per-account shortcuts
if(Test-Path $GitAccountsFile){
    Get-Content $GitAccountsFile | Where-Object { $_ -match '\|' } | ForEach-Object {
        $lbl = ($_ -split '\|')[0]
        Invoke-Expression "function global:git-$lbl { gituse '$lbl' }"
        Invoke-Expression "function global:$lbl-clone { param(`$u) gitclone '$lbl' `$u }"
        Invoke-Expression "function global:$lbl-init { param(`$r) gitnew '$lbl' `$r }"
    }
}
# <<< git-multi-account <<<
'@

# stash a copy where gitsetup expects it
Copy-Item $PSCommandPath (Join-Path $HOME ".git-setup.ps1") -Force -ErrorAction SilentlyContinue

Run-Wizard
