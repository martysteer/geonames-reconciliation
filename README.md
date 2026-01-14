# GeoNames Reconciliation Service

A local reconciliation service for [GeoNames](https://www.geonames.org/) geographic data, compatible with [OpenRefine](https://openrefine.org/) and the [W3C Reconciliation Service API v0.2](https://www.w3.org/community/reports/reconciliation/CG-FINAL-specs-0.2-20230410/).

This service allows you to match place names in your datasets against the GeoNames database of over 13 million geographic features.

## Features

- **Full-text search** with [FTS5](https://sqlite.org/fts5.html) for fast, fuzzy matching
- **Type filtering** by GeoNames feature class (populated places, administrative, hydrographic, etc.)
- **OpenRefine compatible** via datasette-reconcile plugin
- **Self-contained** Python virtual environment
- **Offline operation** - works without internet after initial setup

## Requirements

- **macOS** or **Linux** (Windows via WSL)
- **Python 3.8+** (preferably managed via pyenv)
- **curl** and **unzip** (standard on most systems)
- **~5GB disk space** (400MB download, 1.5GB extracted, 3GB database)

## Installation & Usage

```bash
make all      # Downloads data (~400MB), builds database, sets up environment
make serve    # Start the reconciliation server
```

Then in OpenRefine:
1. Open a column dropdown → **Reconcile** → **Start reconciling...**
2. Click **Add Standard Service...**
3. Enter: `http://127.0.0.1:8001/geonames/geonames/-/reconcile`

If the data files already exist, use `make setup` for a quicker build.

Run `make help` to see all available commands.

## GeoNames Feature Types

This service uses GeoNames top-level feature classes for type filtering:

| Type | Description |
|------|-------------|
| `P` | Populated places (cities, towns, villages) |
| `A` | Administrative divisions (countries, states, districts) |
| `H` | Hydrographic features (rivers, lakes, seas) |
| `T` | Terrain/topographic features (mountains, valleys, islands) |
| `L` | Area/region (parks, reserves, regions) |
| `S` | Spot/structure (buildings, farms, airports) |
| `R` | Road/railroad (roads, trails, railways) |
| `V` | Vegetation (forests, grasslands, vineyards) |
| `U` | Undersea features (trenches, ridges, seamounts) |

Full feature code list: https://www.geonames.org/export/codes.html

## Directory Structure

```
GeoNames/
├── Makefile                    # Build automation
├── README.md                   # This file
├── geonames.metadata.json      # Datasette reconciliation service configuration
├
├── geonames.db                 # SQLite database with FTS (generated)
├── .venv/                      # Python virtual environment (generated)
├── .python-version             # pyenv version file (generated)
├── allCountries.zip            # Downloaded GeoNames data (downloaded)
├── allCountries.txt            # Extracted data (~13M records) (extracted)
└── featureCodes_en.txt         # Feature code descriptions (generated)
```

## Data License

GeoNames data is available under [Creative Commons Attribution 4.0 License](https://creativecommons.org/licenses/by/4.0/).

When using this data, please credit GeoNames: https://www.geonames.org/

## References

- [GeoNames](https://www.geonames.org/) - Geographic database
- [datasette](https://datasette.io/) - Tool for exploring and publishing data
- [datasette-reconcile](https://github.com/drkane/datasette-reconcile) - Reconciliation API plugin
- [W3C Reconciliation API](https://www.w3.org/community/reports/reconciliation/CG-FINAL-specs-0.2-20230410/) - Specification
- [OpenRefine](https://openrefine.org/) - Data cleaning tool
- [SQLite FTS5](https://sqlite.org/fts5.html) - SQLite full text search

## See Also

- [FAST Reconciliation Service](../FAST/) - Subject headings reconciliation
- [OpenRefine Reconciliation Documentation](https://docs.openrefine.org/manual/reconciling)
