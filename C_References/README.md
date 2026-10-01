# Civil 3D Build References

These Autodesk DLLs are needed to build the Civil 3D plugin. The deployment package does not include them; Civil 3D provides its own copies at runtime.

## Required DLLs

Copy these from your Civil 3D installation directory (typically `C:\Program Files\Autodesk\AutoCAD 2025\`):

| DLL | Purpose |
|-----|---------|
| `accoremgd.dll` | AutoCAD Core Managed |
| `AcDbMgd.dll` | AutoCAD Database Managed |
| `acmgd.dll` | AutoCAD Managed |
| `AecBaseMgd.dll` | AEC Base Managed |
| `AeccDbMgd.dll` | Civil 3D Database Managed |

## Setup and Packaging

From the repository root, run the copy script to populate this folder. It searches standard Autodesk install folders automatically:

```powershell
.\Copy-Civil3DReferences.ps1
```

For a custom installation or to choose between multiple installations, pass its folder explicitly:

```powershell
.\Copy-Civil3DReferences.ps1 -SourceDirectory "C:\Program Files\Autodesk\AutoCAD 2025"
```

To build the plugin and MCP server and create the user deployment zip, run:

```powershell
.\scripts\New-Civil3D-DeploymentPackage.ps1
```

The package script copies references automatically if any are missing, then writes `dist/civil3d-mcp-package.zip`. For a nonstandard Civil 3D installation, pass `-Civil3DInstallPath "<install folder>"`.

To build only the plugin manually:

```powershell
dotnet build .\plugin\Civil3dMcpPlugin\Civil3dMcpPlugin.csproj
```

> **Note**: These DLLs are proprietary Autodesk files and must NOT be committed to version control.
> They are already excluded by `.gitignore`. They are only used on the build machine and are not copied into the deployment package.
