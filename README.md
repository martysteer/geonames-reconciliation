# GeoNames Reconciliation Service

A local reconciliation service for [GeoNames](https://www.geonames.org/) geographic data, compatible with [OpenRefine](https://openrefine.org/) and the [W3C Reconciliation Service API v0.2](https://www.w3.org/community/reports/reconciliation/CG-FINAL-specs-0.2-20230410/).

This service allows you to match place names in your datasets against the GeoNames database of over 13 million geographic features.

## Features

- **Full-text search** with FTS5 for fast, fuzzy matching
- **Type filtering** by GeoNames feature codes (cities, mountains, countries, etc.)
- **OpenRefine compatible** via datasette-reconcile plugin
- **Self-contained** Python virtual environment
- **Offline operation** - works without internet after initial setup

## Quick Start

```bash
# Clone or download this directory, then:
make all      # Downloads data (~400MB), builds database, sets up environment
make serve    # Start the reconciliation server
```

Then in OpenRefine:
1. Open a column dropdown → **Reconcile** → **Start reconciling...**
2. Click **Add Standard Service...**
3. Enter: `http://127.0.0.1:8001/geonames/geonames/-/reconcile`

## Requirements

- **macOS** or **Linux** (Windows via WSL)
- **Python 3.8+** (preferably managed via pyenv)
- **curl** and **unzip** (standard on most systems)
- **~5GB disk space** (400MB download, 1.5GB extracted, 3GB database)

### Optional: pyenv

If you have [pyenv](https://github.com/pyenv/pyenv) installed, the Makefile will automatically use it to ensure a consistent Python version.

```bash
# Install pyenv (macOS)
brew install pyenv

# Install pyenv (Linux)
curl https://pyenv.run | bash
```

## Installation

### Full Setup (Recommended)

```bash
make all
```

This will:
1. Create a Python virtual environment with all dependencies
2. Download `allCountries.zip` from GeoNames (~400MB)
3. Extract the data (~1.5GB text file)
4. Build a SQLite database with FTS5 indexes (~3GB)
5. Generate the datasette metadata configuration

### Quick Setup (If Files Already Exist)

If you've already downloaded the files:

```bash
make setup
```

## Usage

### Start the Server

```bash
make serve
```

The server will start at `http://127.0.0.1:8001/`

### Reconciliation Endpoint

```
http://127.0.0.1:8001/geonames/geonames/-/reconcile
```

### Test the Service

```bash
# With the server running in another terminal:
make test-reconcile
```

Or manually:

```bash
curl "http://127.0.0.1:8001/geonames/geonames/-/reconcile?queries=%7B%22q0%22%3A%7B%22query%22%3A%22London%22%7D%7D"
```

## GeoNames Feature Types

GeoNames uses a two-level classification:
- **Feature Class** (single letter): A=Administrative, P=Populated place, H=Hydrographic, etc.
- **Feature Code**: More specific type (e.g., P.PPL = populated place, P.PPLC = capital)

Common types you can filter by:

| Type | Description |
|------|-------------|
| `P.PPL` | Populated place (city/town/village) |
| `P.PPLC` | Capital city |
| `P.PPLA` | Seat of first-order administrative division |
| `A.PCLI` | Independent political entity (country) |
| `A.ADM1` | First-order admin division (state/province) |
| `A.ADM2` | Second-order admin division (county/district) |
| `H.STM` | Stream/river |
| `H.LK` | Lake |
| `T.MT` | Mountain |
| `T.HLL` | Hill |

Full list: https://www.geonames.org/export/codes.html

## Directory Structure

```
GeoNames/
├── Makefile                    # Build automation
├── README.md                   # This file
├── geonames.metadata.json      # Datasette configuration (generated)
├── .venv/                      # Python virtual environment (generated)
├── .python-version             # pyenv version file (generated)
├── data/
│   └── geonames.db            # SQLite database with FTS (generated)
├── allCountries.zip           # Downloaded GeoNames data
├── allCountries.txt           # Extracted data (~13M records)
└── featureCodes_en.txt        # Feature code descriptions
```

## Makefile Commands

```bash
make help           # Show all available commands

# Setup
make all            # Complete setup
make setup          # Quick setup (if files exist)
make venv           # Create virtual environment only
make download       # Download data only
make extract        # Extract zip only
make sqlite         # Build database only
make metadata       # Generate metadata only

# Server
make serve          # Start server (localhost)
make serve-public   # Start server (network accessible)
make test-reconcile # Test the endpoint

# Information
make list           # Show file status
make versions       # Show package versions
make sqlite-stats   # Database statistics
make sqlite-test-fts # Test FTS search

# Cleanup
make clean          # Remove generated files
make clean-all      # Remove everything
make clean-venv     # Remove venv only
make clean-db       # Remove database only
```

## Customization

### Using a Smaller Dataset

GeoNames provides smaller extracts:
- `cities500.zip` - Cities with population > 500
- `cities1000.zip` - Cities with population > 1000
- `cities5000.zip` - Cities with population > 5000
- `cities15000.zip` - Cities with population > 15000
- Individual country files (e.g., `GB.zip`, `US.zip`)

Edit the `GEONAMES_URL` in the Makefile to use a different source.

### Changing the Port

```bash
PORT=8080 make serve
```

Or edit the `PORT` variable in the Makefile.

## Troubleshooting

### "Virtual environment not set up"

```bash
make venv
```

### Server won't start

Check if another process is using port 8001:
```bash
lsof -i :8001
```

### FTS search returns no results

The FTS index might not be built. Rebuild the database:
```bash
make sqlite-rebuild
```

### Out of memory during database build

The full GeoNames dataset is large. Try:
1. Using a smaller dataset (cities5000.zip)
2. Increasing swap space
3. Running on a machine with more RAM

## Data License

GeoNames data is available under [Creative Commons Attribution 4.0 License](https://creativecommons.org/licenses/by/4.0/).

When using this data, please credit GeoNames: https://www.geonames.org/

## References

- [GeoNames](https://www.geonames.org/) - Geographic database
- [datasette](https://datasette.io/) - Tool for exploring and publishing data
- [datasette-reconcile](https://github.com/drkane/datasette-reconcile) - Reconciliation API plugin
- [W3C Reconciliation API](https://www.w3.org/community/reports/reconciliation/CG-FINAL-specs-0.2-20230410/) - Specification
- [OpenRefine](https://openrefine.org/) - Data cleaning tool

## See Also

- [FAST Reconciliation Service](../FAST/) - Subject headings reconciliation
- [OpenRefine Reconciliation Documentation](https://docs.openrefine.org/manual/reconciling)
