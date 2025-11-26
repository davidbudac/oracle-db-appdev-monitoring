# Windows Build Guide for oracledb_exporter

This guide provides detailed instructions for building the `oracledb_exporter` on Windows with CGO and the godror Oracle driver.

## Prerequisites

### 1. Install Go

1. Download Go for Windows from [https://go.dev/dl/](https://go.dev/dl/)
2. Run the installer (e.g., `go1.24.9.windows-amd64.msi`)
3. Follow the installation wizard (default options are fine)
4. Verify installation by opening PowerShell and running:
   ```powershell
   go version
   ```
   You should see something like: `go version go1.24.9 windows/amd64`

### 2. Install Git

1. Download Git for Windows from [https://git-scm.com/download/win](https://git-scm.com/download/win)
2. Run the installer
3. Use default options (or customize as needed)
4. Verify installation:
   ```powershell
   git --version
   ```

### 3. Install GitHub CLI (gh)

1. Download from [https://cli.github.com/](https://cli.github.com/)
2. Or install via winget:
   ```powershell
   winget install --id GitHub.cli
   ```
3. Verify installation:
   ```powershell
   gh --version
   ```
4. Authenticate with GitHub:
   ```powershell
   gh auth login
   ```
   Follow the prompts to authenticate

### 4. Install GCC (MinGW-w64)

The godror driver requires CGO, which needs a C compiler.

**Option A: Install via MSYS2 (Recommended)**

1. Download MSYS2 from [https://www.msys2.org/](https://www.msys2.org/)
2. Run the installer (e.g., `msys2-x86_64-20240727.exe`)
3. After installation, open "MSYS2 UCRT64" terminal
4. Update the package database:
   ```bash
   pacman -Syu
   ```
5. Install MinGW-w64 GCC:
   ```bash
   pacman -S mingw-w64-ucrt-x86_64-gcc
   ```
6. Add to PATH:
   - Open Windows Settings → System → About → Advanced system settings
   - Click "Environment Variables"
   - Under "System variables", find "Path" and click "Edit"
   - Add: `C:\msys64\ucrt64\bin`
   - Click OK to save

**Option B: Install MinGW-w64 directly**

1. Download from [https://github.com/niXman/mingw-builds-binaries/releases](https://github.com/niXman/mingw-builds-binaries/releases)
2. Extract to `C:\mingw64`
3. Add `C:\mingw64\bin` to your PATH (see step 6 above)

7. Verify installation (close and reopen PowerShell):
   ```powershell
   gcc --version
   ```
   You should see something like: `gcc (Rev10, Built by MSYS2 project) 13.2.0`

### 5. Install Oracle Instant Client

The godror driver requires Oracle Instant Client libraries.

1. Download Oracle Instant Client Basic for Windows x64 from:
   [https://www.oracle.com/database/technologies/instant-client/winx64-64-downloads.html](https://www.oracle.com/database/technologies/instant-client/winx64-64-downloads.html)

2. Download "Basic Package" (e.g., `instantclient-basic-windows.x64-21.13.0.0.0dbru.zip`)

3. Extract to a permanent location, e.g., `C:\oracle\instantclient_21_13`

4. Add to PATH:
   - Open Windows Settings → System → About → Advanced system settings
   - Click "Environment Variables"
   - Under "System variables", find "Path" and click "Edit"
   - Add: `C:\oracle\instantclient_21_13`
   - Click OK to save

5. Set PKG_CONFIG_PATH (required for godror):
   - In "Environment Variables", under "System variables", click "New"
   - Variable name: `PKG_CONFIG_PATH`
   - Variable value: `C:\oracle\instantclient_21_13`
   - Click OK

6. Verify installation (close and reopen PowerShell):
   ```powershell
   where.exe oci.dll
   ```
   You should see: `C:\oracle\instantclient_21_13\oci.dll`

### 6. Install pkg-config for Windows

The godror build process uses pkg-config to find Oracle libraries.

1. Download pkg-config for Windows:
   - If using MSYS2, install via:
     ```bash
     pacman -S mingw-w64-ucrt-x86_64-pkg-config
     ```

   - Or download from [https://github.com/pkgconf/pkgconf/releases](https://github.com/pkgconf/pkgconf/releases)
   - Extract `pkg-config.exe` to a directory in your PATH (e.g., `C:\mingw64\bin`)

2. Verify installation:
   ```powershell
   pkg-config --version
   ```

### 7. Create pkg-config file for Oracle

Create a file `oci8.pc` to help pkg-config find Oracle libraries:

1. Create directory: `C:\oracle\instantclient_21_13\lib\pkgconfig`
2. Create file: `C:\oracle\instantclient_21_13\lib\pkgconfig\oci8.pc`
3. Add the following content (adjust version and paths as needed):

```
prefix=C:/oracle/instantclient_21_13
libdir=${prefix}
includedir=${prefix}/sdk/include

Name: oci8
Description: Oracle Instant Client
Version: 21.13
Libs: -L${libdir} -loci
Cflags: -I${includedir}
```

4. Update PKG_CONFIG_PATH to include this directory:
   - In "Environment Variables", edit `PKG_CONFIG_PATH`
   - Change to: `C:\oracle\instantclient_21_13\lib\pkgconfig`

## Building the Project

### 1. Clone the Repository

```powershell
cd C:\
git clone https://github.com/davidbudac/oracle-db-appdev-monitoring.git
cd oracle-db-appdev-monitoring
```

### 2. Install Go Dependencies

```powershell
go mod download
```

### 3. Build Manually (Optional)

To build manually without creating a release:

```powershell
$env:CGO_ENABLED = "1"
go build -tags godror -o oracledb_exporter.exe main.go
```

### 4. Test the Build

```powershell
.\oracledb_exporter.exe --version
```

## Creating a Release

### Quick Method

Use the PowerShell script:

```powershell
.\create-release-windows.ps1 v1.0.0
```

This script will:
1. Check for and delete existing releases/tags
2. Build the Windows binary with godror/CGO
3. Create a zip archive
4. Create and push a git tag
5. Create a GitHub release with the binary attached

### Manual Method

If you prefer to do it step by step:

```powershell
# Set environment variables
$env:CGO_ENABLED = "1"
$env:GOOS = "windows"
$env:GOARCH = "amd64"

# Build
go build -tags godror -o oracledb_exporter-windows-amd64.exe main.go

# Create archive
Compress-Archive -Path oracledb_exporter-windows-amd64.exe -DestinationPath oracledb_exporter-windows-amd64.zip

# Create tag and release
git tag v1.0.0
git push origin v1.0.0
gh release create v1.0.0 oracledb_exporter-windows-amd64.zip --title "v1.0.0" --generate-notes
```

## Troubleshooting

### Issue: "gcc: command not found"

**Solution:** Ensure GCC is installed and in your PATH. Close and reopen PowerShell after modifying PATH.

### Issue: "oci.h: No such file or directory"

**Solution:**
1. Download Oracle Instant Client SDK (in addition to Basic)
2. Extract to the same directory as Basic (e.g., `C:\oracle\instantclient_21_13`)
3. Verify `sdk\include\oci.h` exists

### Issue: "cannot find -loci"

**Solution:**
1. Verify Oracle Instant Client is in PATH
2. Check that `oci.dll` exists in the Instant Client directory
3. Verify PKG_CONFIG_PATH is set correctly
4. Check that `oci8.pc` file exists and has correct paths

### Issue: "pkg-config: command not found"

**Solution:** Install pkg-config (see Prerequisites step 6)

### Issue: Build succeeds but exe fails to run

**Solution:**
1. Ensure Oracle Instant Client directory is in PATH
2. Copy required DLLs from Instant Client to the same directory as the exe
3. Or ensure the exe is run from a location where it can find the DLLs

### Issue: "The system cannot execute the specified program"

**Solution:** You may be missing Visual C++ Redistributables. Download and install:
[https://aka.ms/vs/17/release/vc_redist.x64.exe](https://aka.ms/vs/17/release/vc_redist.x64.exe)

## Environment Variables Summary

After completing the setup, you should have these environment variables set:

- **PATH** should include:
  - `C:\msys64\ucrt64\bin` (or your MinGW-w64 bin directory)
  - `C:\oracle\instantclient_21_13` (or your Instant Client directory)

- **PKG_CONFIG_PATH**: `C:\oracle\instantclient_21_13\lib\pkgconfig`

## Verifying Your Setup

Run this checklist to verify everything is installed correctly:

```powershell
# Check Go
go version

# Check Git
git --version

# Check GitHub CLI
gh --version

# Check GCC
gcc --version

# Check pkg-config
pkg-config --version

# Check Oracle Instant Client
where.exe oci.dll

# Check if pkg-config can find Oracle
pkg-config --cflags --libs oci8
```

If all commands succeed, you're ready to build!

## Additional Resources

- [godror documentation](https://github.com/godror/godror)
- [Oracle Instant Client documentation](https://www.oracle.com/database/technologies/instant-client.html)
- [Go CGO documentation](https://pkg.go.dev/cmd/cgo)
- [MinGW-w64 documentation](https://www.mingw-w64.org/)
