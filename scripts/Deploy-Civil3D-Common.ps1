function Write-Section([string]$Message) {
    Write-Host ''
    Write-Host "=== $Message ===" -ForegroundColor Cyan
}

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Find-Node22Path {
    $localAppData = $env:LOCALAPPDATA
    if ($localAppData) {
        $candidateDirs = Get-ChildItem -LiteralPath $localAppData -Directory -Filter 'node-v22*-win-x64' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending
        foreach ($directory in $candidateDirs) {
            $candidate = Join-Path $directory.FullName 'node.exe'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return $candidate
            }
        }
    }

    $onPath = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($onPath) {
        $version = & $onPath.Source --version 2>$null
        if ($version -match '^v22\.') {
            return $onPath.Source
        }
    }

    return $null
}

function Install-Node22 {
    $releases = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json'
    $latest = $releases |
        Where-Object { $_.version -match '^v22\.\d+\.\d+$' } |
        Sort-Object { [version]$_.version.TrimStart('v') } -Descending |
        Select-Object -First 1
    if (-not $latest) {
        throw 'Could not find a Node.js v22 release.'
    }

    $distName = "node-$($latest.version)-win-x64"
    $zipName = "$distName.zip"
    $zipPath = Join-Path $env:TEMP $zipName
    $zipUrl = "https://nodejs.org/dist/$($latest.version)/$zipName"
    $checksumsUrl = "https://nodejs.org/dist/$($latest.version)/SHASUMS256.txt"

    Write-Host "Downloading Node.js $($latest.version)..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
    $checksums = (Invoke-WebRequest -Uri $checksumsUrl -UseBasicParsing).Content
    $checksumLine = $checksums -split "`r?`n" |
        Where-Object { $_ -match [regex]::Escape($zipName) } |
        Select-Object -First 1
    if (-not $checksumLine) {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        throw "No published checksum found for $zipName."
    }

    $expectedHash = ($checksumLine.Trim() -split '\s+')[0]
    $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash) {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        throw "Checksum verification failed for $zipName."
    }

    Expand-Archive -LiteralPath $zipPath -DestinationPath $env:LOCALAPPDATA -Force
    Remove-Item -LiteralPath $zipPath -Force
    $nodePath = Join-Path (Join-Path $env:LOCALAPPDATA $distName) 'node.exe'
    if (-not (Test-Path -LiteralPath $nodePath -PathType Leaf)) {
        throw "Node.js extraction completed, but node.exe was not found at $nodePath"
    }

    return $nodePath
}

function Ensure-Node22Path {
    param([switch]$InstallIfMissing)

    $nodePath = Find-Node22Path
    if ($nodePath) {
        return $nodePath
    }
    if ($InstallIfMissing) {
        return Install-Node22
    }
    return $null
}

function Install-ServerDependencies {
    param(
        [Parameter(Mandatory = $true)][string]$ServerRoot,
        [Parameter(Mandatory = $true)][string]$NodePath
    )

    $nodeDirectory = Split-Path -Parent $NodePath
    $npmCmd = Join-Path $nodeDirectory 'npm.cmd'
    if (-not (Test-Path -LiteralPath $npmCmd -PathType Leaf)) {
        throw "npm.cmd was not found beside Node.js at $nodeDirectory"
    }

    $originalPath = $env:PATH
    Push-Location $ServerRoot
    try {
        $env:PATH = "$nodeDirectory;$originalPath"
        & $npmCmd ci --omit=dev
        if ($LASTEXITCODE -ne 0) {
            throw "npm ci failed with exit code $LASTEXITCODE"
        }
        Write-Host '[OK] MCP server dependencies installed'
    } finally {
        $env:PATH = $originalPath
        Pop-Location
    }
}

function Update-CodexMcpConfig {
    param(
        [Parameter(Mandatory = $true)][string]$ServerEntryPath,
        [Parameter(Mandatory = $true)][string]$NodePath
    )

    $configPath = Join-Path $env:USERPROFILE '.codex\config.toml'
    $serverEntryToml = $ServerEntryPath -replace '\\', '/'
    $nodePathToml = $NodePath -replace '\\', '/'
    $desiredValues = [ordered]@{
        enabled = 'true'
        command = "`"$nodePathToml`""
        args    = "[`"$serverEntryToml`"]"
    }
    $fullBlock = "[mcp_servers.civil3d]`r`n" +
        (($desiredValues.Keys | ForEach-Object { "$_ = $($desiredValues[$_])" }) -join "`r`n") + "`r`n"

    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        Ensure-Dir (Split-Path -Parent $configPath)
        Set-Content -LiteralPath $configPath -Value $fullBlock -NoNewline -Encoding utf8
        Write-Host "[OK] Created $configPath with the civil3d MCP server entry"
        return
    }

    $content = Get-Content -LiteralPath $configPath -Raw
    $pattern = '(?m)^\[mcp_servers\.civil3d\]\r?\n(?:(?!^\[).*(?:\r?\n|$))*'
    $match = [regex]::Match($content, $pattern)
    if ($match.Success) {
        $blockLines = @($match.Value -split "`r?`n" | Where-Object { $_ -ne '' })
        $bodyLines = @($blockLines | Select-Object -Skip 1)
        $foundKeys = @{}
        $newBody = foreach ($line in $bodyLines) {
            $key = $desiredValues.Keys |
                Where-Object { $line -match "^\s*$_\s*=" } |
                Select-Object -First 1
            if ($key) {
                $foundKeys[$key] = $true
                "$key = $($desiredValues[$key])"
            } else {
                $line
            }
        }
        foreach ($key in $desiredValues.Keys) {
            if (-not $foundKeys.ContainsKey($key)) {
                $newBody = @("$key = $($desiredValues[$key])") + @($newBody)
            }
        }

        $newBlock = (@('[mcp_servers.civil3d]') + @($newBody) -join "`r`n") + "`r`n"
        $updated = $content.Substring(0, $match.Index) + $newBlock +
            $content.Substring($match.Index + $match.Length)
    } else {
        $separator = if ($content.EndsWith("`n")) { "`r`n" } else { "`r`n`r`n" }
        $updated = $content + $separator + $fullBlock
    }

    Set-Content -LiteralPath $configPath -Value $updated -NoNewline -Encoding utf8
    Write-Host "[OK] Updated $configPath with the civil3d MCP server entry"
}