# Civil 3D MCP Server — Code Execution Architecture

An MCP server that enables AI assistants to **write and execute C# code** directly inside Autodesk Civil 3D. Instead of fixed tools, the AI generates code that runs with full API access.

## Architecture

```
┌─────────────────┐     stdio      ┌──────────────────┐     TCP/JSON-RPC    ┌──────────────────┐
│   AI Assistant   │ ◄────────────► │  MCP Server (TS) │ ◄──────────────────► │  Civil 3D Plugin │
│ (Claude, Cline)  │               │   3 meta-tools    │     port 8080       │  Roslyn Engine   │
└─────────────────┘               └──────────────────┘                      └──────────────────┘
                                         │                                         │
                                    Skills Library                           C# Code Execution
                                   (.skill.md files)                      (full Civil 3D API)
```

## 3 Meta-Tools

| Tool | Purpose | Safety |
|------|---------|--------|
| `civil3d_execute` | Execute C# code with **write** access (transaction committed) | ⚠️ Modifies drawing |
| `civil3d_query` | Execute C# code **read-only** (no commit) | ✅ No side effects |
| `civil3d_skills` | Browse/search/read code skill templates | ✅ Metadata only |

### How It Works

1. **AI reads a skill** → Gets a documented C# code template
2. **AI adapts the code** → Fills in parameters, combines patterns
3. **AI sends code** → Via `civil3d_execute` or `civil3d_query`
4. **Roslyn compiles + runs** → Inside Civil 3D with full API access
5. **Results return as JSON** → Back to the AI

### Example Interaction

```
User: "What surfaces are in my drawing?"

AI: Uses civil3d_query with:
  var surfaces = new List<object>();
  foreach (ObjectId id in CivilDoc.GetSurfaceIds()) {
    var s = Transaction.GetObject(id, OpenMode.ForRead) as TinSurface;
    surfaces.Add(new { s.Name, s.Layer });
  }
  return surfaces;

Result: [{ "Name": "EG", "Layer": "C-TOPO-EG" }, ...]
```

## Skills Library

Skills are documented C# code templates in `skills/`:

```
skills/
├── surfaces/           # Surface operations
├── alignments/         # Alignment + station/offset
├── points/             # COGO points
├── geometry/           # Lines, polylines, text
├── drawing/            # Drawing info
└── workflows/          # Complex multi-object operations
```

### Script Globals

Code executed via `civil3d_execute` or `civil3d_query` has access to:

| Global | Type | Description |
|--------|------|-------------|
| `Document` | `Document` | Active AutoCAD document |
| `CivilDoc` | `CivilDocument` | Active Civil 3D document |
| `Database` | `Database` | Document database |
| `Transaction` | `Transaction` | Active transaction |
| `Editor` | `Editor` | Document editor |

All Civil 3D namespaces are auto-imported.

## Build and Deployment

### Create a Deployment Package
Run this on a Windows build machine with the .NET SDK, Node.js/npm, and access to the Civil 3D reference DLLs:

```powershell
.\scripts\New-Civil3D-DeploymentPackage.ps1
```

The script finds or copies the required DLLs into `C_References`, builds the plugin and MCP server, and creates `dist/civil3d-mcp-package.zip`. For a nonstandard Autodesk install path, pass `-Civil3DInstallPath "<install folder>"`. The DLLs are build-time references and are not included in the deployment archive.

### Install for Users
1. Share the generated zip and have the user extract it.
2. Double-click `Deploy-Civil3D-Package.bat` in the extracted folder. The installer adds the plugin bundle under `%APPDATA%\Autodesk\ApplicationPlugins`, copies the server and skills under `%LOCALAPPDATA%\mcp-servers\civil3d-mcp`, installs Node.js 22 if needed, installs server dependencies, and registers the MCP server in Codex CLI / ChatGPT Desktop's config.
3. Restart Civil 3D and the MCP client. The Autodesk bundle loads the plugin when Civil 3D starts. If Node.js or server dependencies need downloading, the installer requires internet access.

### Runtime Protocol
The MCP client starts `civil3d-mcp` over stdio. The server forwards tool requests to the plugin over TCP/JSON-RPC at `localhost:8080`. Civil 3D must be running with the plugin loaded for drawing tools to work. Run `C3DMCPSTATUS` in Civil 3D to verify the listener.

For development or troubleshooting, load `Civil3dMcpPlugin.dll` with `NETLOAD`; the build output is under `plugin/Civil3dMcpPlugin/bin/`.

### Configure Other MCP Clients
The installer registers Codex CLI / ChatGPT Desktop automatically. For another MCP client, configure the absolute path to `node.exe` and the installed server entry point (adjust the Windows user and Node.js version):

```json
{
  "mcpServers": {
    "civil3d": {
      "command": "C:\\Users\\<user>\\AppData\\Local\\node-v22.<version>-win-x64\\node.exe",
      "args": ["C:\\Users\\<user>\\AppData\\Local\\mcp-servers\\civil3d-mcp\\build\\index.js"]
    }
  }
}
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CIVIL3D_HOST` | `localhost` | Plugin host |
| `CIVIL3D_PORT` | `8080` | Plugin port |
| `CIVIL3D_CONNECT_TIMEOUT` | `5000` | Connection timeout (ms) |
| `CIVIL3D_COMMAND_TIMEOUT` | `120000` | Execution timeout (ms) |
| `LOG_LEVEL` | `info` | Log level |

## Security

The Roslyn sandbox blocks:
- Process execution (`Process.Start`)
- File deletion (`File.Delete`)
- Network requests (`HttpClient`, `Sockets`)
- Registry access
- Dynamic assembly loading

All Civil 3D API operations are allowed.

## License

  MIT
