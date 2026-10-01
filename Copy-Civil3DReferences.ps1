[CmdletBinding()]
param(
    [string]$SourceDirectory,

    [string]$DestinationDirectory = (Join-Path $PSScriptRoot 'C_References')
)

$ErrorActionPreference = 'Stop'

$requiredFiles = @(
    'accoremgd.dll',
    'AcDbMgd.dll',
    'acmgd.dll',
    'AecBaseMgd.dll',
    'AeccDbMgd.dll'
)

if (-not $SourceDirectory) {
    $autodeskRoots = @()
    if ($env:ProgramFiles) {
        $autodeskRoots += Join-Path $env:ProgramFiles 'Autodesk'
    }
    if (${env:ProgramFiles(x86)}) {
        $autodeskRoots += Join-Path ${env:ProgramFiles(x86)} 'Autodesk'
    }

    $installRoots = foreach ($autodeskRoot in ($autodeskRoots | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $autodeskRoot -PathType Container) {
            Get-ChildItem -LiteralPath $autodeskRoot -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^(AutoCAD|Civil 3D)(\s|$)' }
        }
    }

    $candidateDirectories = foreach ($installRoot in $installRoots) {
        Get-ChildItem -LiteralPath $installRoot.FullName -Filter 'AeccDbMgd.dll' -File -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object { $_.DirectoryName }
    }

    $validCandidates = @(
        $candidateDirectories | Sort-Object -Unique | Where-Object {
            $candidate = $_
            @($requiredFiles | Where-Object {
                Test-Path -LiteralPath (Join-Path $candidate $_) -PathType Leaf
            }).Count -eq $requiredFiles.Count
        }
    )

    if ($validCandidates.Count -eq 0) {
        throw 'Could not find a Civil 3D installation with all required DLLs under the standard Autodesk folders in Program Files. For a custom installation, rerun with -SourceDirectory <path>.'
    }
    if ($validCandidates.Count -gt 1) {
        throw "Found multiple Civil 3D reference folders: $($validCandidates -join '; '). Rerun with -SourceDirectory <path> to choose one."
    }

    $SourceDirectory = $validCandidates[0]
}

if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
    throw "Source directory not found: $SourceDirectory"
}

$missingFiles = @(
    $requiredFiles | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $SourceDirectory $_) -PathType Leaf)
    }
)

if ($missingFiles.Count -gt 0) {
    throw "Missing required DLLs in '$SourceDirectory': $($missingFiles -join ', ')"
}

if (-not (Test-Path -LiteralPath $DestinationDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
}

foreach ($file in $requiredFiles) {
    Copy-Item -LiteralPath (Join-Path $SourceDirectory $file) -Destination $DestinationDirectory -Force
}

Write-Host "Copied $($requiredFiles.Count) Civil 3D reference DLLs to '$DestinationDirectory'."