# Installs the Civil 3D Autodesk bundle and MCP server from this extracted package.
# The package is self-contained apart from the per-user Node.js runtime installation.

$ErrorActionPreference = 'Stop'
$packageRoot = $PSScriptRoot

. (Join-Path $packageRoot 'Deploy-Civil3D-Common.ps1')

$bundleSource = Join-Path $packageRoot 'Civil3dMcp.bundle'
$serverSource = Join-Path $packageRoot 'server'
if (-not (Test-Path (Join-Path $bundleSource 'PackageContents.xml'))) {
    throw "Civil 3D plugin bundle is missing from this package: $bundleSource"
}
if (-not (Test-Path (Join-Path $serverSource 'build\index.js'))) {
    throw "MCP server build is missing from this package: $serverSource"
}
if (-not (Test-Path (Join-Path $serverSource 'skills'))) {
    throw "MCP skills are missing from this package: $serverSource"
}

Write-Section 'Installing Civil 3D plugin bundle'
$bundleInstallRoot = Join-Path $env:APPDATA 'Autodesk\ApplicationPlugins'
$bundleDestination = Join-Path $bundleInstallRoot 'Civil3dMcp.bundle'
Ensure-Dir $bundleDestination
Copy-Item -Path (Join-Path $bundleSource '*') -Destination $bundleDestination -Recurse -Force
Write-Host "[OK] Installed Civil 3D bundle to $bundleDestination"

Write-Section 'Installing MCP server'
$serverInstallRoot = Join-Path $env:LOCALAPPDATA 'mcp-servers\civil3d-mcp'
Ensure-Dir $serverInstallRoot
Copy-Item -Path (Join-Path $serverSource '*') -Destination $serverInstallRoot -Recurse -Force
Write-Host "[OK] Copied MCP server to $serverInstallRoot"

Write-Section 'Checking Node.js prerequisite'
$nodePath = Ensure-Node22Path -InstallIfMissing
if (-not $nodePath) {
    throw 'Node.js v22 could not be located or installed.'
}
Write-Host "[OK] Node.js available at $nodePath"

Write-Section 'Installing MCP server dependencies'
Install-ServerDependencies -ServerRoot $serverInstallRoot -NodePath $nodePath

Write-Section 'Registering with Codex CLI / ChatGPT Desktop'
Update-CodexMcpConfig -ServerEntryPath (Join-Path $serverInstallRoot 'build\index.js') -NodePath $nodePath

Write-Section 'Done'
Write-Host 'Restart Civil 3D and Codex CLI / ChatGPT Desktop to load the plugin and MCP server.' -ForegroundColor Green