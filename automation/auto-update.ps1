# Unattended daily update pipeline for the pt-BR pokeclicker fork.
# Pulls upstream changes, translates any newly-added strings via a scoped
# headless Claude invocation, rebuilds, and redeploys - logging everything
# so it can be reviewed later. Safe by default: it never pushes/deploys a
# broken merge or a broken build, and always leaves the previous good
# Vercel deployment live if anything fails partway through.

$repoRoot = "C:\Users\GAUST\OneDrive\Documentos\pokecliker"
$subRoot = Join-Path $repoRoot "src\translations"
$logDir = Join-Path $repoRoot "automation\logs"
$lockFile = Join-Path $repoRoot "automation\.update.lock"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = Join-Path $logDir "$stamp.log"
$changesSummary = New-Object System.Collections.Generic.List[string]

function Log($msg) {
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
    Write-Output $line
    Add-Content -Path $logFile -Value $line
}

if (Test-Path $lockFile) {
    $age = (Get-Date) - (Get-Item $lockFile).LastWriteTime
    if ($age.TotalHours -lt 6) {
        Log "Another run appears to be in progress (lock file age: $($age.TotalMinutes) min). Exiting."
        exit 0
    }
    Log "Stale lock file found (age: $($age.TotalHours) h) - assuming a previous run crashed, continuing."
}
New-Item -ItemType File -Force -Path $lockFile | Out-Null

try {
    Log "=== pokeclicker pt-BR auto-update starting ==="

    # ---- 1. Update the translations submodule from upstream ----
    Set-Location $subRoot
    git fetch upstream 2>&1 | ForEach-Object { Log $_ }
    $subBefore = git rev-parse HEAD
    git merge --no-edit upstream/develop 2>&1 | ForEach-Object { Log $_ }
    if ($LASTEXITCODE -ne 0) {
        git merge --abort 2>&1 | Out-Null
        throw "Merge conflict while updating translations submodule from upstream. Left un-merged for manual resolution."
    }
    $subAfter = git rev-parse HEAD
    if ($subBefore -ne $subAfter) {
        $subLog = git log --oneline "$subBefore..$subAfter"
        Log "Translations submodule updated: $subBefore -> $subAfter"
        $changesSummary.Add("Translations submodule: " + ($subLog -join '; '))
    } else {
        Log "Translations submodule already up to date."
    }

    # ---- 2. Update the main repo from upstream ----
    Set-Location $repoRoot
    git fetch upstream 2>&1 | ForEach-Object { Log $_ }
    $mainBefore = git rev-parse HEAD
    git merge --no-edit upstream/develop 2>&1 | ForEach-Object { Log $_ }
    if ($LASTEXITCODE -ne 0) {
        git merge --abort 2>&1 | Out-Null
        throw "Merge conflict while updating main repo from upstream. Left un-merged for manual resolution."
    }
    $mainAfterMerge = git rev-parse HEAD
    if ($mainBefore -ne $mainAfterMerge) {
        $mainLog = git log --oneline "$mainBefore..$mainAfterMerge"
        Log "Main repo updated: $mainBefore -> $mainAfterMerge"
        $changesSummary.Add("Game code: " + ($mainLog -join '; '))
    }

    # ---- 3. Find and translate any newly-untranslated pt-BR strings ----
    node automation/find-missing-translations.js 2>&1 | ForEach-Object { Log $_ }
    $missingCount = 0
    if (Test-Path "automation\missing-translations.json") {
        $report = Get-Content "automation\missing-translations.json" -Raw | ConvertFrom-Json
        $missingCount = ($report.PSObject.Properties | ForEach-Object { $_.Value.Count } | Measure-Object -Sum).Sum
    }

    if ($missingCount -gt 0) {
        Log "Found $missingCount untranslated string(s). Invoking Claude to translate..."
        $prompt = "Read automation/TRANSLATION_GUIDE.md for conventions, then automation/missing-translations.json for the list of missing pt-BR translations. Fill in every listed key in the corresponding src/translations/locales/pt-BR/<file> with a natural Brazilian Portuguese translation, following the guide exactly. Only edit those files, only those keys."
        claude -p $prompt --permission-mode acceptEdits --allowedTools "Read Edit Glob Grep" --add-dir "$subRoot" 2>&1 | ForEach-Object { Log $_ }

        node automation/find-missing-translations.js 2>&1 | ForEach-Object { Log $_ }
        $stillMissing = 0
        if (Test-Path "automation\missing-translations.json") {
            $report2 = Get-Content "automation\missing-translations.json" -Raw | ConvertFrom-Json
            $stillMissing = ($report2.PSObject.Properties | ForEach-Object { $_.Value.Count } | Measure-Object -Sum).Sum
        }
        if ($stillMissing -gt 0) {
            Log "WARNING: $stillMissing string(s) still untranslated after Claude ran. They will fall back to English until next run."
        } else {
            Log "All strings translated successfully."
        }

        Set-Location $subRoot
        $subDirty = git status --porcelain
        if ($subDirty) {
            git add -A
            $translatedNow = $missingCount - $stillMissing
            $commitMsg = "feat(pt-BR): auto-translate $translatedNow new string(s) after upstream update`n`nGenerated unattended by automation/auto-update.ps1 on $stamp."
            git commit -m $commitMsg 2>&1 | ForEach-Object { Log $_ }
            $changesSummary.Add("Auto-translated $translatedNow new string(s) in pt-BR")
        }
        Set-Location $repoRoot
    } else {
        Log "No untranslated strings found."
    }

    # ---- 4. Push submodule, then update+push main repo's submodule pointer ----
    Set-Location $subRoot
    $subUnpushed = git log "origin/develop..HEAD" --oneline
    if ($subUnpushed) {
        git push origin HEAD:develop 2>&1 | ForEach-Object { Log $_ }
        if ($LASTEXITCODE -ne 0) { throw "Failed to push translations submodule to origin." }
    }
    Set-Location $repoRoot

    git add src/translations
    $submodulePointerChanged = git status --porcelain -- src/translations
    if ($submodulePointerChanged) {
        $commitMsg = "chore: update translations submodule pointer`n`n$($changesSummary -join "`n")`n`nGenerated unattended by automation/auto-update.ps1 on $stamp."
        git commit -m $commitMsg 2>&1 | ForEach-Object { Log $_ }
    }

    if ($changesSummary.Count -eq 0) {
        Log "No upstream changes and nothing new to translate. Nothing to do."
        Log "=== Done (no-op) ==="
        exit 0
    }

    git push origin develop 2>&1 | ForEach-Object { Log $_ }
    if ($LASTEXITCODE -ne 0) { throw "Failed to push main repo to origin." }
    Log "Pushed to GitHub (Jianrel/pokeclicker and Jianrel/pokeclicker-translations)."

    # ---- 5. Rebuild ----
    Log "Installing dependencies..."
    npm install 2>&1 | ForEach-Object { Log $_ }
    if ($LASTEXITCODE -ne 0) { throw "npm install failed. Previous deployment left live." }

    if (Test-Path "$repoRoot\build") { Remove-Item -Recurse -Force "$repoRoot\build" }
    Log "Building..."
    npm run build 2>&1 | ForEach-Object { Log $_ }
    if ($LASTEXITCODE -ne 0) { throw "Build failed. Previous deployment left live; source changes were still pushed to GitHub for review." }

    if (Test-Path "$repoRoot\build\package.json") { Remove-Item "$repoRoot\build\package.json" }

    # ---- 6. Deploy ----
    Set-Location "$repoRoot\build"
    Log "Deploying to Vercel (production)..."
    npx --yes vercel --prod --yes 2>&1 | ForEach-Object { Log $_ }
    if ($LASTEXITCODE -ne 0) { throw "Vercel deploy failed. Previous deployment left live; source changes were still pushed to GitHub for review." }

    Set-Location $repoRoot
    Log "=== Update complete ==="
    Log ("Summary: " + ($changesSummary -join " | "))
    Log "Live at: https://pokeclicker-pt-br.vercel.app"
}
catch {
    Log "ABORT: $($_.Exception.Message)"
    Log "Previous deployment left untouched."
}
finally {
    Set-Location $repoRoot
    Remove-Item -Force $lockFile -ErrorAction SilentlyContinue
}
