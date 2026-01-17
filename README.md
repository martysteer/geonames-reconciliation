# GeoNames Reconciliation Service

A local reconciliation service for [GeoNames](https://www.geonames.org/) geographic data, compatible with [OpenRefine](https://openrefine.org/) and the [W3C Reconciliation Service API v0.2](https://www.w3.org/community/reports/reconciliation/CG-FINAL-specs-0.2-20230410/).

Match place names against 13+ million geographic features with full-text search.

## Features
- **Full-text search** with [FTS5](https://sqlite.org/fts5.html) for fast, fuzzy matching
- **Type filtering** by GeoNames feature class (populated places, administrative, hydrographic, etc.)
- **OpenRefine compatible** via datasette-reconcile plugin
- **Self-contained** Python or Docker virtual environment
- **Offline operation** - works without internet after initial setup

## Quick Start

### Option 1: Docker (recommended)

```bash
docker compose up -d        # First run downloads data and builds DB (~10 min)
docker compose logs -f      # Watch progress
```

### Option 2: Native (macOS/Linux)

```bash
make build                  # Downloads data, creates venv, builds DB
make serve                  # Start server
```

The service will be available at:
```
http://127.0.0.1:8001/geonames/geonames/-/reconcile
```

## Using with OpenRefine

1. Column dropdown → **Reconcile** → **Start reconciling...**
2. Click **Add Standard Service...**
3. Enter: `http://127.0.0.1:8001/geonames/geonames/-/reconcile`

## Testing

A sample dataset `test-data.csv` is included with ~8000 geographic place names for testing:

1. Start the service (`docker compose up -d` or `make serve`)
2. Open OpenRefine and create a new project from `test-data.csv`
3. Reconcile the **City** or **Country** column against the service
4. Optionally filter by type (e.g., `P` for populated places, `A` for administrative)

The test data includes historical names (Batavia→Jakarta, Canton→Guangzhou), modern place names, and various administrative levels - useful for validating fuzzy matching and type filtering.

## Commands

| Docker | Native | Description |
|--------|--------|-------------|
| `docker compose up -d` | `make build && make serve` | Build and run |
| `docker compose down` | Ctrl+C | Stop |
| `docker compose run --rm geonames make status` | `make status` | Show stats |
| `docker compose run --rm geonames make update` | `make update` | Re-download data |
| `docker compose down -v` | `make clean-all` | Remove everything |

## Feature Types

Filter reconciliation by GeoNames feature class:

| Type | Description |
|------|-------------|
| `P` | Populated places (cities, towns, villages) |
| `A` | Administrative divisions (countries, states) |
| `H` | Hydrographic (rivers, lakes, seas) |
| `T` | Terrain (mountains, valleys, islands) |
| `L` | Areas (parks, reserves, regions) |
| `S` | Structures (buildings, airports) |
| `R` | Roads/railroads |
| `V` | Vegetation (forests, grasslands) |
| `U` | Undersea features |

## Requirements

**Docker:** Docker Desktop (Windows, macOS, Linux)

**Native:** Python 3.10+, curl, unzip, make (macOS/Linux only)

**Disk space:** ~5GB (400MB download → 1.5GB extracted → 3GB database)

## Data License

GeoNames data is [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Credit: https://www.geonames.org/

## References

- [datasette](https://datasette.io/) - Tool for exploring and publishing data
- [datasette-reconcile](https://github.com/drkane/datasette-reconcile) - Reconciliation API plugin
- [GeoNames](https://www.geonames.org/) - Geographic database
- [OpenRefine](https://openrefine.org/) - Data cleaning tool

- [OpenRefine Reconciliation Documentation](https://docs.openrefine.org/manual/reconciling)
- [SQLite FTS5](https://sqlite.org/fts5.html) - SQLite full text search
- [W3C Reconciliation API](https://www.w3.org/community/reports/reconciliation/CG-FINAL-specs-0.2-20230410/) - Specification
