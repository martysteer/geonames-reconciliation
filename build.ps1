<# 
.SYNOPSIS
    GeoNames Reconciliation Service - Build Script for Windows

.DESCRIPTION
    Creates a datasette-based reconciliation endpoint for GeoNames geographic data
    compatible with OpenRefine's reconciliation API (W3C Reconciliation Service API v0.2)

.PARAMETER Command
    The build command to run:
    - build     : Complete setup: venv + download + database
    - serve     : Start datasette reconciliation server
    - test      : Test FTS and reconciliation endpoint
    - status    : Show file status and database statistics
    - update    : Re-download source data and rebuild database
    - clean     : Remove database only (quick reset)
    - clean-all : Remove everything including downloads and venv
    - venv      : Create Python virtual environment only
    - help      : Show this help message

.PARAMETER Public
    If specified with 'serve', binds to 0.0.0.0 for network access

.EXAMPLE
    .\build.ps1 build
    .\build.ps1 serve
    .\build.ps1 serve -Public
    .\build.ps1 status

.NOTES
    Requires: Python 3.10+, Internet connection for initial setup
    Author: Generated for GeoNames Reconciliation Service
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('build', 'serve', 'test', 'status', 'update', 'clean', 'clean-all', 'venv', 'help', '')]
    [string]$Command = 'help',
    
    [switch]$Public
)

# =============================================================================
# Configuration
# =============================================================================
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'  # Speeds up Invoke-WebRequest

$Config = @{
    PythonVersion    = '3.12.4'
    VenvDir          = '.venv'
    GeoNamesUrl      = 'https://download.geonames.org/export/dump/allCountries.zip'
    GeoNamesZip      = 'allCountries.zip'
    GeoNamesTxt      = 'allCountries.txt'
    FeatureCodesUrl  = 'https://download.geonames.org/export/dump/featureCodes_en.txt'
    FeatureCodesTxt  = 'featureCodes_en.txt'
    SqliteDb         = 'geonames.db'
    MetadataJson     = 'geonames.metadata.json'
    Port             = 8001
}

# Derived paths
$VenvPython = Join-Path $Config.VenvDir 'Scripts\python.exe'
$VenvPip = Join-Path $Config.VenvDir 'Scripts\pip.exe'
$VenvDatasette = Join-Path $Config.VenvDir 'Scripts\datasette.exe'
$VenvSqliteUtils = Join-Path $Config.VenvDir 'Scripts\sqlite-utils.exe'
$VenvDone = Join-Path $Config.VenvDir '.done'

# =============================================================================
# Helper Functions
# =============================================================================
function Write-Banner {
    param([string]$Message)
    Write-Host ''
    Write-Host ('=' * 65) -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host ('=' * 65) -ForegroundColor Cyan
    Write-Host ''
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Step {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Gray
}

function Test-CommandExists {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Get-FileSize {
    param([string]$Path)
    if (Test-Path $Path) {
        $size = (Get-Item $Path).Length
        if ($size -gt 1GB) { return '{0:N2} GB' -f ($size / 1GB) }
        if ($size -gt 1MB) { return '{0:N2} MB' -f ($size / 1MB) }
        if ($size -gt 1KB) { return '{0:N2} KB' -f ($size / 1KB) }
        return "$size bytes"
    }
    return 'N/A'
}

function Get-LineCount {
    param([string]$Path)
    if (Test-Path $Path) {
        # Efficient line counting for large files
        $count = 0
        $reader = [System.IO.StreamReader]::new($Path)
        try {
            while ($null -ne $reader.ReadLine()) { $count++ }
        }
        finally {
            $reader.Close()
        }
        return $count
    }
    return 0
}

function Invoke-SqliteQuery {
    param(
        [string]$Database,
        [string]$Query,
        [switch]$Header,
        [switch]$Column
    )
    
    # Try to find sqlite3 - check common locations
    $sqlite3 = $null
    $searchPaths = @(
        'sqlite3',
        'sqlite3.exe',
        "$env:LOCALAPPDATA\Programs\sqlite\sqlite3.exe",
        "$env:ProgramFiles\sqlite\sqlite3.exe",
        'C:\sqlite\sqlite3.exe'
    )
    
    foreach ($path in $searchPaths) {
        if (Test-CommandExists $path) {
            $sqlite3 = $path
            break
        }
    }
    
    if (-not $sqlite3) {
        # Fall back to Python's sqlite3 module
        $pythonQuery = @"
import sqlite3
conn = sqlite3.connect('$Database')
cursor = conn.execute('''$Query''')
for row in cursor:
    print('\t'.join(str(x) for x in row))
conn.close()
"@
        & $VenvPython -c $pythonQuery
        return
    }
    
    $args = @($Database, $Query)
    if ($Header) { $args = @('-header') + $args }
    if ($Column) { $args = @('-column') + $args }
    & $sqlite3 @args
}

# =============================================================================
# Build Functions
# =============================================================================
function Install-Venv {
    if (Test-Path $VenvDone) {
        Write-Step 'Virtual environment already exists'
        return
    }
    
    Write-Banner 'Setting up Python virtual environment'
    
    # Find Python
    $python = $null
    foreach ($cmd in @('python', 'python3', 'py')) {
        if (Test-CommandExists $cmd) {
            $version = & $cmd --version 2>&1
            if ($version -match 'Python 3\.(\d+)' -and [int]$Matches[1] -ge 10) {
                $python = $cmd
                Write-Step "Found $version"
                break
            }
        }
    }
    
    if (-not $python) {
        throw 'Python 3.10+ is required but not found. Install from https://python.org'
    }
    
    Write-Step 'Creating virtual environment...'
    & $python -m venv $Config.VenvDir
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create virtual environment' }
    
    Write-Step 'Upgrading pip...'
    & $VenvPip install --upgrade pip -q
    
    Write-Step 'Installing dependencies...'
    & $VenvPip install datasette datasette-reconcile sqlite-utils csvkit httpx -q
    if ($LASTEXITCODE -ne 0) { throw 'Failed to install dependencies' }
    
    # Mark as done
    New-Item -Path $VenvDone -ItemType File -Force | Out-Null
    
    Write-Success 'Virtual environment ready'
}

function Get-GeoNamesData {
    # Download zip if needed
    if (-not (Test-Path $Config.GeoNamesZip)) {
        Write-Step 'Downloading GeoNames data (~400MB)...'
        
        # Use curl.exe if available (faster, shows progress), otherwise Invoke-WebRequest
        if (Test-CommandExists 'curl.exe') {
            & curl.exe -L --progress-bar -o $Config.GeoNamesZip $Config.GeoNamesUrl
        }
        else {
            Invoke-WebRequest -Uri $Config.GeoNamesUrl -OutFile $Config.GeoNamesZip -UseBasicParsing
        }
        
        if (-not (Test-Path $Config.GeoNamesZip)) {
            throw 'Failed to download GeoNames data'
        }
        Write-Success "Downloaded $(Get-FileSize $Config.GeoNamesZip)"
    }
    else {
        Write-Step "Using existing $($Config.GeoNamesZip) ($(Get-FileSize $Config.GeoNamesZip))"
    }
    
    # Download feature codes if needed
    if (-not (Test-Path $Config.FeatureCodesTxt)) {
        Write-Step 'Downloading feature codes...'
        Invoke-WebRequest -Uri $Config.FeatureCodesUrl -OutFile $Config.FeatureCodesTxt -UseBasicParsing
    }
    
    # Extract if needed
    if (-not (Test-Path $Config.GeoNamesTxt)) {
        Write-Step 'Extracting...'
        Expand-Archive -Path $Config.GeoNamesZip -DestinationPath '.' -Force
        
        if (-not (Test-Path $Config.GeoNamesTxt)) {
            throw 'Failed to extract GeoNames data'
        }
        Write-Success 'Extracted successfully'
    }
    else {
        Write-Step "Using existing $($Config.GeoNamesTxt)"
    }
}

function Build-Database {
    if (Test-Path $Config.SqliteDb) {
        Write-Step "Database already exists ($(Get-FileSize $Config.SqliteDb))"
        return
    }
    
    Write-Banner 'Building SQLite database (this takes several minutes)...'
    
    # Ensure we have the data
    Get-GeoNamesData
    
    # Create header files for TSV import
    $geoNamesHeader = "geonameid`tname`tasciiname`talternatenames`tlatitude`tlongitude`tfeature_class`tfeature_code`tcountry_code`tcc2`tadmin1_code`tadmin2_code`tadmin3_code`tadmin4_code`tpopulation`televation`tdem`ttimezone`tmodification_date"
    $featureHeader = "code`tname`tdescription"
    
    # Import feature codes
    Write-Step 'Importing feature codes...'
    $featureContent = $featureHeader + "`n" + (Get-Content $Config.FeatureCodesTxt -Raw)
    $featureContent | & $VenvSqliteUtils insert $Config.SqliteDb feature_codes - --tsv
    
    # Import GeoNames data (this is the slow part)
    Write-Step 'Importing GeoNames data (this will take a while)...'
    
    # Create a temporary file with header prepended
    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        # Write header
        [System.IO.File]::WriteAllText($tempFile, $geoNamesHeader + "`n")
        
        # Append the data file efficiently
        $writer = [System.IO.File]::AppendText($tempFile)
        $reader = [System.IO.StreamReader]::new($Config.GeoNamesTxt)
        try {
            $lineCount = 0
            while (($line = $reader.ReadLine()) -ne $null) {
                $writer.WriteLine($line)
                $lineCount++
                if ($lineCount % 1000000 -eq 0) {
                    Write-Step "  Processed $($lineCount / 1000000)M lines..."
                }
            }
        }
        finally {
            $reader.Close()
            $writer.Close()
        }
        
        # Import using sqlite-utils
        Get-Content $tempFile -Raw | & $VenvSqliteUtils insert $Config.SqliteDb geonames - --tsv
    }
    finally {
        Remove-Item $tempFile -ErrorAction SilentlyContinue
    }
    
    # Add columns
    Write-Step 'Adding columns and indexes...'
    & $VenvSqliteUtils add-column $Config.SqliteDb geonames searchText text 2>$null
    & $VenvSqliteUtils add-column $Config.SqliteDb geonames type text 2>$null
    & $VenvSqliteUtils add-column $Config.SqliteDb geonames id text 2>$null
    
    # Run SQL updates
    $updateSql = @"
UPDATE geonames SET 
    id = CAST(geonameid AS TEXT),
    type = feature_class,
    searchText = name || ' ' || COALESCE(asciiname, '') || ' ' || COALESCE(alternatenames, '');

CREATE INDEX IF NOT EXISTS idx_geonames_id ON geonames(id);
CREATE INDEX IF NOT EXISTS idx_geonames_type ON geonames(type);
CREATE INDEX IF NOT EXISTS idx_geonames_country ON geonames(country_code);
CREATE INDEX IF NOT EXISTS idx_geonames_name ON geonames(name);
"@
    
    Invoke-SqliteQuery -Database $Config.SqliteDb -Query $updateSql
    
    # Enable FTS
    Write-Step 'Creating FTS index...'
    & $VenvSqliteUtils enable-fts $Config.SqliteDb geonames searchText name --fts5 --create-triggers
    
    # Report success
    $recordCount = (Invoke-SqliteQuery -Database $Config.SqliteDb -Query 'SELECT COUNT(*) FROM geonames;').Trim()
    Write-Host ''
    Write-Success "Database ready: $(Get-FileSize $Config.SqliteDb), $recordCount records"
}

function Start-Server {
    if (-not (Test-Path $VenvDone)) {
        throw 'Virtual environment not found. Run: .\build.ps1 build'
    }
    if (-not (Test-Path $Config.SqliteDb)) {
        throw 'Database not found. Run: .\build.ps1 build'
    }
    if (-not (Test-Path $Config.MetadataJson)) {
        throw "Metadata file not found: $($Config.MetadataJson). Restore from git."
    }
    
    $host_addr = if ($Public) { '0.0.0.0' } else { '127.0.0.1' }
    $endpoint = "http://127.0.0.1:$($Config.Port)/geonames/geonames/-/reconcile"
    
    Write-Banner 'Starting GeoNames Reconciliation Service'
    
    Write-Host "Reconciliation endpoint:"
    Write-Host "  $endpoint" -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Add to OpenRefine:'
    Write-Host "  1. Column dropdown → Reconcile → Start reconciling..."
    Write-Host "  2. Click 'Add Standard Service...'"
    Write-Host "  3. Enter: $endpoint"
    Write-Host ''
    Write-Host 'Press Ctrl+C to stop'
    Write-Banner ''
    
    & $VenvDatasette $Config.SqliteDb `
        --metadata $Config.MetadataJson `
        --port $Config.Port `
        --host $host_addr `
        --setting sql_time_limit_ms 5000 `
        --setting max_returned_rows 1000
}

function Test-Service {
    if (-not (Test-Path $Config.SqliteDb)) {
        throw 'Database not found. Run: .\build.ps1 build'
    }
    
    Write-Banner 'Testing GeoNames Service'
    
    Write-Host 'FTS search for "London":'
    $ftsQuery = @"
SELECT g.id, g.name, g.country_code, g.type, g.population
FROM geonames g
INNER JOIN geonames_fts fts ON g.rowid = fts.rowid
WHERE geonames_fts MATCH 'London'
ORDER BY g.population DESC
LIMIT 5;
"@
    Invoke-SqliteQuery -Database $Config.SqliteDb -Query $ftsQuery -Header -Column
    
    Write-Host ''
    Write-Host 'Reconciliation endpoint test:'
    
    $testScript = @"
import json
import httpx

queries = {'q0': {'query': 'London'}, 'q1': {'query': 'Paris'}}
try:
    r = httpx.post(
        'http://127.0.0.1:$($Config.Port)/geonames/geonames/-/reconcile',
        data={'queries': json.dumps(queries)},
        timeout=10
    )
    print(json.dumps(r.json(), indent=2))
except httpx.ConnectError:
    print('Server not running. Start with: .\\build.ps1 serve')
"@
    
    & $VenvPython -c $testScript
}

function Show-Status {
    Write-Banner 'GeoNames Service Status'
    
    Write-Host 'Files:'
    
    # Check each file
    $files = @(
        @{ Name = 'venv'; Path = $VenvDone },
        @{ Name = $Config.GeoNamesZip; Path = $Config.GeoNamesZip; ShowSize = $true },
        @{ Name = $Config.GeoNamesTxt; Path = $Config.GeoNamesTxt; ShowLines = $true },
        @{ Name = $Config.SqliteDb; Path = $Config.SqliteDb; ShowSize = $true },
        @{ Name = $Config.MetadataJson; Path = $Config.MetadataJson }
    )
    
    foreach ($file in $files) {
        if (Test-Path $file.Path) {
            $info = "  ✓ $($file.Name)"
            if ($file.ShowSize) { $info += " ($(Get-FileSize $file.Path))" }
            if ($file.ShowLines) { $info += " ($(Get-LineCount $file.Path) lines)" }
            Write-Host $info -ForegroundColor Green
        }
        else {
            $suffix = if ($file.Name -eq $Config.MetadataJson) { ' (missing!)' } else { '' }
            Write-Host "  ✗ $($file.Name)$suffix" -ForegroundColor Red
        }
    }
    
    # Database statistics
    if (Test-Path $Config.SqliteDb) {
        Write-Host ''
        Write-Host 'Database:'
        $recordCount = (Invoke-SqliteQuery -Database $Config.SqliteDb -Query 'SELECT COUNT(*) FROM geonames;').Trim()
        Write-Host "  Records: $recordCount"
        
        Write-Host ''
        Write-Host '  By feature class:'
        $classQuery = 'SELECT feature_class, COUNT(*) as count FROM geonames GROUP BY feature_class ORDER BY count DESC;'
        Invoke-SqliteQuery -Database $Config.SqliteDb -Query $classQuery -Column
    }
    
    # Python version
    if (Test-Path $VenvDone) {
        Write-Host ''
        Write-Host 'Versions:'
        $pyVersion = & $VenvPython --version 2>&1
        Write-Host "  $pyVersion"
        
        $dsVersion = & $VenvPip show datasette 2>$null | Select-String 'Version:'
        if ($dsVersion) {
            Write-Host "  datasette $($dsVersion -replace 'Version:\s*', '')"
        }
    }
}

function Remove-Database {
    Write-Step 'Removing database...'
    Remove-Item $Config.SqliteDb -ErrorAction SilentlyContinue
    Write-Success "Done. Run '.\build.ps1 build' to rebuild."
}

function Remove-All {
    Write-Step 'Removing all generated files...'
    Remove-Item $Config.SqliteDb -ErrorAction SilentlyContinue
    Remove-Item $Config.GeoNamesZip -ErrorAction SilentlyContinue
    Remove-Item $Config.GeoNamesTxt -ErrorAction SilentlyContinue
    Remove-Item $Config.FeatureCodesTxt -ErrorAction SilentlyContinue
    Remove-Item '.python-version' -ErrorAction SilentlyContinue
    Remove-Item $Config.VenvDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Success 'All files removed.'
}

function Invoke-Update {
    Remove-Database
    Remove-Item $Config.GeoNamesZip -ErrorAction SilentlyContinue
    Remove-Item $Config.GeoNamesTxt -ErrorAction SilentlyContinue
    Remove-Item $Config.FeatureCodesTxt -ErrorAction SilentlyContinue
    Write-Step 'Re-downloading and rebuilding...'
    Invoke-Build
}

function Invoke-Build {
    Install-Venv
    Get-GeoNamesData
    Build-Database
    
    Write-Host ''
    Write-Banner '✓ GeoNames Reconciliation Service is ready!'
    Write-Host 'Start the server with: .\build.ps1 serve'
    Write-Host ''
}

function Show-Help {
    Write-Banner 'GeoNames Reconciliation Service'
    
    Write-Host 'Datasette-based reconciliation endpoint for GeoNames data,'
    Write-Host 'compatible with OpenRefine''s W3C Reconciliation API.'
    Write-Host ''
    Write-Host 'Usage: .\build.ps1 <command> [-Public]'
    Write-Host ''
    Write-Host 'Commands:'
    Write-Host '  build      Complete setup: venv + download + database' -ForegroundColor White
    Write-Host '  serve      Start server (add -Public for network access)' -ForegroundColor White
    Write-Host '  test       Test FTS search and reconciliation endpoint' -ForegroundColor White
    Write-Host '  status     Show file status and database statistics' -ForegroundColor White
    Write-Host '  update     Re-download source data and rebuild' -ForegroundColor White
    Write-Host '  clean      Remove database only' -ForegroundColor White
    Write-Host '  clean-all  Remove everything including downloads and venv' -ForegroundColor White
    Write-Host '  venv       Create Python virtual environment only' -ForegroundColor White
    Write-Host ''
    Write-Host 'Quick start:'
    Write-Host '  .\build.ps1 build' -ForegroundColor Yellow
    Write-Host '  .\build.ps1 serve' -ForegroundColor Yellow
    Write-Host ''
    Write-Host "Endpoint: http://127.0.0.1:$($Config.Port)/geonames/geonames/-/reconcile"
    Write-Host ''
}

# =============================================================================
# Main Command Dispatcher
# =============================================================================
try {
    switch ($Command) {
        'build'     { Invoke-Build }
        'serve'     { Start-Server }
        'test'      { Test-Service }
        'status'    { Show-Status }
        'update'    { Invoke-Update }
        'clean'     { Remove-Database }
        'clean-all' { Remove-All }
        'venv'      { Install-Venv }
        'help'      { Show-Help }
        ''          { Show-Help }
        default     { Show-Help }
    }
}
catch {
    Write-Host ''
    Write-Host "ERROR: $_" -ForegroundColor Red
    Write-Host ''
    exit 1
}
