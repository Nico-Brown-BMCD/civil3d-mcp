# Builds the Civil 3D plugin and MCP server, then creates a user-installable zip.

param(
    [string]$OutputZip = (Join-Path $PSScriptRoot '..\dist\civil3d-mcp-package.zip'),
    [string]$Civil3DInstallPath,
    [ValidatePattern('^R\d+\.\d+$')]
    [string]$SeriesMin = 'R25.0'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$referencesRoot = Join-Path $projectRoot 'C_References'
$requiredReferences = @(
    'accoremgd.dll',
    'AcDbMgd.dll',
    'acmgd.dll',
    'AecBaseMgd.dll',
    'AeccDbMgd.dll'
)
$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('civil3d-mcp-package-' + [guid]::NewGuid().ToString('N'))

try {
    Write-Host '=== Checking Civil 3D references ===' -ForegroundColor Cyan
    $missingReferences = @($requiredReferences | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $referencesRoot $_) -PathType Leaf)
    })
    if ($missingReferences.Count -gt 0) {
        $copyScript = Join-Path $projectRoot 'Copy-Civil3DReferences.ps1'
        if (-not (Test-Path -LiteralPath $copyScript -PathType Leaf)) {
            throw "Civil 3D references are missing and the copy script was not found: $copyScript"
        }
        if ($Civil3DInstallPath) {
            & $copyScript -SourceDirectory $Civil3DInstallPath -DestinationDirectory $referencesRoot
        } else {
            & $copyScript -DestinationDirectory $referencesRoot
        }
    }

    $missingReferences = @($requiredReferences | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $referencesRoot $_) -PathType Leaf)
    })
    if ($missingReferences.Count -gt 0) {
        throw "Required Civil 3D references are still missing: $($missingReferences -join ', ')"
    }

    Write-Host '=== Building Civil 3D plugin ===' -ForegroundColor Cyan
    $pluginProject = Join-Path $projectRoot 'plugin\Civil3dMcpPlugin\Civil3dMcpPlugin.csproj'
    & dotnet build $pluginProject --configuration Release "-p:Civil3DReferencesPath=$referencesRoot"
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet build failed with exit code $LASTEXITCODE"
    }

    Write-Host '=== Building MCP server ===' -ForegroundColor Cyan
    Push-Location $projectRoot
    try {
        & npm ci
        if ($LASTEXITCODE -ne 0) {
            throw "npm ci failed with exit code $LASTEXITCODE"
        }
        & npm run build
        if ($LASTEXITCODE -ne 0) {
            throw "npm run build failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }

    $pluginOutput = Join-Path $projectRoot 'plugin\Civil3dMcpPlugin\bin\Release\net8.0-windows'
    $serverBuild = Join-Path $projectRoot 'build'
    if (-not (Test-Path -LiteralPath (Join-Path $pluginOutput 'Civil3dMcpPlugin.dll') -PathType Leaf)) {
        throw "Plugin build output was not found at $pluginOutput"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $serverBuild 'index.js') -PathType Leaf)) {
        throw "MCP server build output was not found at $serverBuild"
    }

    Write-Host '=== Staging package ===' -ForegroundColor Cyan
    $bundleRoot = Join-Path $stagingRoot 'Civil3dMcp.bundle'
    $bundleWindows = Join-Path $bundleRoot 'Contents\Windows'
    New-Item -ItemType Directory -Path $bundleWindows -Force | Out-Null
    Copy-Item -Path (Join-Path $pluginOutput '*') -Destination $bundleWindows -Recurse -Force

    $packageVersion = (Get-Content -LiteralPath (Join-Path $projectRoot 'package.json') -Raw | ConvertFrom-Json).version
    $manifest = [xml]@"
<ApplicationPackage SchemaVersion="1.0" AutodeskProduct="AutoCAD" Name="Civil3D MCP" Description="Civil 3D MCP plugin" AppVersion="$packageVersion" ProductCode="{A12F8A22-263D-4F9B-9E12-8F41B38D8810}" UpgradeCode="{D97B415A-C476-45B4-ABFA-8B1E6D6BB252}">
  <CompanyDetails Name="Civil3D MCP" />
  <Components>
    <RuntimeRequirements OS="Win64" Platform="AutoCAD*" SeriesMin="$SeriesMin" />
    <ComponentEntry AppName="Civil3dMcpPlugin" ModuleName="./Contents/Windows/Civil3dMcpPlugin.dll" LoadOnAutoCADStartup="True" LoadOnCommandInvocation="False" />
  </Components>
</ApplicationPackage>
"@
    $manifest.Save((Join-Path $bundleRoot 'PackageContents.xml'))

    $serverRoot = Join-Path $stagingRoot 'server'
    $serverBuildDestination = Join-Path $serverRoot 'build'
    $serverSkillsDestination = Join-Path $serverRoot 'skills'
    New-Item -ItemType Directory -Path $serverBuildDestination, $serverSkillsDestination -Force | Out-Null
    Copy-Item -Path (Join-Path $serverBuild '*') -Destination $serverBuildDestination -Recurse -Force
    Copy-Item -Path (Join-Path $projectRoot 'skills\*') -Destination $serverSkillsDestination -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $projectRoot 'package.json') -Destination $serverRoot -Force
    Copy-Item -LiteralPath (Join-Path $projectRoot 'package-lock.json') -Destination $serverRoot -Force

    $packageScript = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Deploy-Civil3D-Package.ps1') -Raw
    $commonScript = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Deploy-Civil3D-Common.ps1') -Raw
    $dotSourceLine = ". (Join-Path `$packageRoot 'Deploy-Civil3D-Common.ps1')"
    if (-not $packageScript.Contains($dotSourceLine)) {
        throw 'Deploy-Civil3D-Package.ps1 no longer has the expected common-script dot-source line.'
    }
    $mergedScript = $packageScript.Replace($dotSourceLine, $commonScript)
    Set-Content -LiteralPath (Join-Path $stagingRoot 'Deploy-Civil3D-Package.ps1') -Value $mergedScript -NoNewline
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Deploy-Civil3D-Package.bat') -Destination $stagingRoot -Force

    $OutputZip = [System.IO.Path]::GetFullPath($OutputZip)
    $outputDirectory = Split-Path -Parent $OutputZip
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    if (Test-Path -LiteralPath $OutputZip -PathType Leaf) {
        Remove-Item -LiteralPath $OutputZip -Force
    }

    Write-Host '=== Creating deployment archive ===' -ForegroundColor Cyan
    Compress-Archive -Path (Join-Path $stagingRoot '*') -DestinationPath $OutputZip
    Write-Host "Package created: $OutputZip" -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $stagingRoot -PathType Container) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}