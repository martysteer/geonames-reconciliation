# Makefile for GeoNames Reconciliation Service
#
# Creates a datasette-based reconciliation endpoint for GeoNames geographic data
# compatible with OpenRefine's reconciliation API (W3C Reconciliation Service API v0.2)
#
# Directory structure:
#   allCountries.zip          - Downloaded source data
#   allCountries.txt          - Extracted tab-separated data
#   data/geonames.db          - SQLite database with FTS indexes
#   geonames.metadata.json    - Datasette metadata for reconciliation
#
# Usage:
#   make all             - Complete setup: venv + download + database + ready to run
#   make venv            - Create Python virtual environment with dependencies
#   make download        - Download allCountries.zip from GeoNames
#   make extract         - Extract the zip file
#   make sqlite          - Build SQLite database with FTS indexes
#   make serve           - Start datasette reconciliation server
#   make clean           - Remove generated files (keeps downloads)
#   make clean-all       - Remove everything including downloads
#   make help            - Show this help

# =============================================================================
# Configuration
# =============================================================================
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# Python version to use with pyenv
PYTHON_VERSION := 3.12.4
VENV_NAME := geonames-reconcile
VENV_DIR := .venv

# Data source
GEONAMES_URL := https://download.geonames.org/export/dump/allCountries.zip
GEONAMES_ZIP := allCountries.zip
GEONAMES_TXT := allCountries.txt

# Feature codes for mapping GeoNames classes to human-readable types
FEATURE_CODES_URL := https://download.geonames.org/export/dump/featureCodes_en.txt
FEATURE_CODES_TXT := featureCodes_en.txt

# Output files
DATA_DIR := data
SQLITE_DB := $(DATA_DIR)/geonames.db
METADATA_JSON := geonames.metadata.json

# Datasette port
PORT := 8001

# Mark source files as precious
.PRECIOUS: $(GEONAMES_ZIP) $(GEONAMES_TXT)

# =============================================================================
# Virtual Environment Setup
# =============================================================================
.PHONY: venv
venv: $(VENV_DIR)/.done

$(VENV_DIR)/.done:
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "Setting up Python virtual environment"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo ""
	@if command -v pyenv >/dev/null 2>&1; then \
		echo "Using pyenv to manage Python version..."; \
		pyenv install -s $(PYTHON_VERSION); \
		pyenv local $(PYTHON_VERSION); \
		echo "$(PYTHON_VERSION)" > .python-version; \
	else \
		echo "pyenv not found, using system Python..."; \
	fi
	@echo "Creating virtual environment in $(VENV_DIR)..."
	python3 -m venv $(VENV_DIR)
	@echo "Upgrading pip..."
	$(VENV_DIR)/bin/pip install --upgrade pip
	@echo "Installing dependencies..."
	$(VENV_DIR)/bin/pip install \
		datasette \
		datasette-reconcile \
		sqlite-utils \
		csvkit \
		httpx
	@touch $@
	@echo ""
	@echo "✓ Virtual environment ready!"
	@echo "  Activate with: source $(VENV_DIR)/bin/activate"
	@echo ""

.PHONY: check-venv
check-venv:
	@if [ ! -f "$(VENV_DIR)/.done" ]; then \
		echo "Virtual environment not set up. Run 'make venv' first."; \
		exit 1; \
	fi

# =============================================================================
# Download and Extract
# =============================================================================
.PHONY: download
download: $(GEONAMES_ZIP) $(FEATURE_CODES_TXT)

$(GEONAMES_ZIP):
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "Downloading GeoNames data"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "  URL: $(GEONAMES_URL)"
	@echo "  This is a large file (~400MB compressed, ~1.5GB extracted)"
	@echo ""
	curl -L --progress-bar -o $(GEONAMES_ZIP) "$(GEONAMES_URL)"
	@echo ""
	@echo "✓ Downloaded: $$(du -h $(GEONAMES_ZIP) | cut -f1)"

$(FEATURE_CODES_TXT):
	@echo "Downloading feature codes..."
	curl -L --progress-bar -o $(FEATURE_CODES_TXT) "$(FEATURE_CODES_URL)"

.PHONY: extract
extract: $(GEONAMES_TXT)

$(GEONAMES_TXT): $(GEONAMES_ZIP)
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "Extracting $(GEONAMES_ZIP)"
	@echo "═══════════════════════════════════════════════════════════════"
	unzip -o $(GEONAMES_ZIP)
	@# Touch the file so its timestamp is newer than the zip
	@touch $(GEONAMES_TXT)
	@echo ""
	@echo "✓ Extracted: $$(wc -l < $(GEONAMES_TXT) | tr -d ' ') records"

# =============================================================================
# SQLite Database
# =============================================================================
$(DATA_DIR):
	mkdir -p $(DATA_DIR)

.PHONY: sqlite
sqlite: check-venv $(SQLITE_DB)

$(SQLITE_DB): $(GEONAMES_TXT) $(FEATURE_CODES_TXT) | $(DATA_DIR)
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "Building SQLite database with FTS indexes"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo ""
	@echo "This will take several minutes for the full dataset..."
	@echo ""
	@rm -f $(SQLITE_DB)
	@echo "Step 1/5: Importing feature codes..."
	@# Feature codes file has no header, format: code<TAB>name<TAB>description
	@echo "code	name	description" > /tmp/feature_codes_header.txt
	@cat /tmp/feature_codes_header.txt $(FEATURE_CODES_TXT) | \
		$(VENV_DIR)/bin/sqlite-utils insert $(SQLITE_DB) feature_codes - --tsv
	@rm -f /tmp/feature_codes_header.txt
	@echo "Step 2/5: Importing GeoNames data (this takes a while)..."
	@# GeoNames file has no header - create one and import
	@echo "geonameid	name	asciiname	alternatenames	latitude	longitude	feature_class	feature_code	country_code	cc2	admin1_code	admin2_code	admin3_code	admin4_code	population	elevation	dem	timezone	modification_date" > /tmp/geonames_header.txt
	@cat /tmp/geonames_header.txt $(GEONAMES_TXT) | \
		$(VENV_DIR)/bin/sqlite-utils insert $(SQLITE_DB) geonames - --tsv
	@rm -f /tmp/geonames_header.txt
	@echo "Step 3/5: Creating search field and indexes..."
	@$(VENV_DIR)/bin/sqlite-utils add-column $(SQLITE_DB) geonames searchText text 2>/dev/null || true
	@$(VENV_DIR)/bin/sqlite-utils add-column $(SQLITE_DB) geonames type text 2>/dev/null || true
	@$(VENV_DIR)/bin/sqlite-utils add-column $(SQLITE_DB) geonames id text 2>/dev/null || true
	@echo "Step 4/5: Populating derived fields..."
	sqlite3 $(SQLITE_DB) " \
		UPDATE geonames SET \
			id = CAST(geonameid AS TEXT), \
			type = feature_class || '.' || feature_code, \
			searchText = name || ' ' || COALESCE(asciiname, '') || ' ' || COALESCE(alternatenames, ''); \
	"
	@echo "  Creating indexes..."
	sqlite3 $(SQLITE_DB) "CREATE INDEX IF NOT EXISTS idx_geonames_id ON geonames(id);"
	sqlite3 $(SQLITE_DB) "CREATE INDEX IF NOT EXISTS idx_geonames_type ON geonames(type);"
	sqlite3 $(SQLITE_DB) "CREATE INDEX IF NOT EXISTS idx_geonames_country ON geonames(country_code);"
	sqlite3 $(SQLITE_DB) "CREATE INDEX IF NOT EXISTS idx_geonames_feature ON geonames(feature_class);"
	@echo "Step 5/5: Creating FTS5 full-text search index..."
	$(VENV_DIR)/bin/sqlite-utils enable-fts $(SQLITE_DB) geonames searchText name --fts5 --create-triggers
	@echo ""
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "✓ Database created: $(SQLITE_DB)"
	@echo "  Size: $$(du -h $(SQLITE_DB) | cut -f1)"
	@echo "  Records: $$(sqlite3 $(SQLITE_DB) 'SELECT COUNT(*) FROM geonames;')"
	@echo "═══════════════════════════════════════════════════════════════"

.PHONY: sqlite-rebuild
sqlite-rebuild:
	@rm -f $(SQLITE_DB)
	@$(MAKE) sqlite

.PHONY: sqlite-stats
sqlite-stats: $(SQLITE_DB)
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "GeoNames Database Statistics"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo ""
	@echo "Database: $(SQLITE_DB)"
	@echo "Size: $$(du -h $(SQLITE_DB) | cut -f1)"
	@echo ""
	@echo "Total records: $$(sqlite3 $(SQLITE_DB) 'SELECT COUNT(*) FROM geonames;')"
	@echo ""
	@echo "Records by feature class:"
	@sqlite3 -column -header $(SQLITE_DB) " \
		SELECT feature_class, COUNT(*) as count \
		FROM geonames \
		GROUP BY feature_class \
		ORDER BY count DESC;"
	@echo ""
	@echo "Top 10 countries:"
	@sqlite3 -column -header $(SQLITE_DB) " \
		SELECT country_code, COUNT(*) as count \
		FROM geonames \
		WHERE country_code != '' \
		GROUP BY country_code \
		ORDER BY count DESC \
		LIMIT 10;"

.PHONY: sqlite-test-fts
sqlite-test-fts: $(SQLITE_DB)
	@echo "Testing FTS search..."
	@echo ""
	@echo "Query: 'London'"
	@sqlite3 -header -column $(SQLITE_DB) " \
		SELECT g.id, g.name, g.country_code, g.type, g.population \
		FROM geonames g \
		INNER JOIN geonames_fts fts ON g.rowid = fts.rowid \
		WHERE geonames_fts MATCH 'London' \
		ORDER BY g.population DESC \
		LIMIT 10;"

# =============================================================================
# Metadata - Already provided as geonames.metadata.json
# =============================================================================
.PHONY: metadata
metadata: $(METADATA_JSON)

$(METADATA_JSON):
	@echo "ERROR: $(METADATA_JSON) not found!"
	@echo "This file should be included in the repository."
	@echo "Please restore it from git or recreate it."
	@exit 1

# =============================================================================
# Datasette Server
# =============================================================================
.PHONY: serve
serve: check-venv $(SQLITE_DB) $(METADATA_JSON)
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "Starting GeoNames Reconciliation Service"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo ""
	@echo "Reconciliation endpoint:"
	@echo "  http://127.0.0.1:$(PORT)/geonames/geonames/-/reconcile"
	@echo ""
	@echo "Add to OpenRefine:"
	@echo "  1. Open a column dropdown → Reconcile → Start reconciling..."
	@echo "  2. Click 'Add Standard Service...'"
	@echo "  3. Enter: http://127.0.0.1:$(PORT)/geonames/geonames/-/reconcile"
	@echo ""
	@echo "Browse data:"
	@echo "  http://127.0.0.1:$(PORT)/"
	@echo ""
	@echo "Press Ctrl+C to stop the server"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo ""
	$(VENV_DIR)/bin/datasette $(SQLITE_DB) \
		--metadata $(METADATA_JSON) \
		--port $(PORT) \
		--setting sql_time_limit_ms 5000 \
		--setting max_returned_rows 1000

.PHONY: serve-public
serve-public: check-venv $(SQLITE_DB) $(METADATA_JSON)
	@echo "Starting server accessible from network..."
	$(VENV_DIR)/bin/datasette $(SQLITE_DB) \
		--metadata $(METADATA_JSON) \
		--port $(PORT) \
		--host 0.0.0.0 \
		--setting sql_time_limit_ms 5000

# =============================================================================
# Main targets
# =============================================================================
.PHONY: all
all: venv download extract sqlite
	@echo ""
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "✓ GeoNames Reconciliation Service is ready!"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo ""
	@echo "Start the server with:"
	@echo "  make serve"
	@echo ""
	@echo "Or activate the environment and run manually:"
	@echo "  source $(VENV_DIR)/bin/activate"
	@echo "  datasette $(SQLITE_DB) --metadata $(METADATA_JSON)"
	@echo ""

# Quick setup without downloading (if files already exist)
.PHONY: setup
setup: venv sqlite

# =============================================================================
# Test reconciliation
# =============================================================================
.PHONY: test-reconcile
test-reconcile: check-venv $(SQLITE_DB)
	@echo "Testing reconciliation endpoint..."
	@echo ""
	@$(VENV_DIR)/bin/python3 -c " \
import json; \
import httpx; \
queries = {'q0': {'query': 'London'}, 'q1': {'query': 'Paris'}, 'q2': {'query': 'Tokyo'}}; \
try: \
    r = httpx.post('http://127.0.0.1:$(PORT)/geonames/geonames/-/reconcile', data={'queries': json.dumps(queries)}, timeout=10); \
    print('Response:'); \
    print(json.dumps(r.json(), indent=2)); \
except httpx.ConnectError: \
    print('Server not running. Start with: make serve'); \
"

# =============================================================================
# Utilities
# =============================================================================
.PHONY: list
list:
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "GeoNames Reconciliation Service - File Status"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo ""
	@echo "Source files:"
	@if [ -f $(GEONAMES_ZIP) ]; then \
		echo "  ✓ $(GEONAMES_ZIP) ($$(du -h $(GEONAMES_ZIP) | cut -f1))"; \
	else \
		echo "  ✗ $(GEONAMES_ZIP) (not downloaded - run 'make download')"; \
	fi
	@if [ -f $(GEONAMES_TXT) ]; then \
		echo "  ✓ $(GEONAMES_TXT) ($$(wc -l < $(GEONAMES_TXT) | tr -d ' ') records)"; \
	else \
		echo "  ✗ $(GEONAMES_TXT) (not extracted - run 'make extract')"; \
	fi
	@echo ""
	@echo "Database:"
	@if [ -f $(SQLITE_DB) ]; then \
		echo "  ✓ $(SQLITE_DB) ($$(du -h $(SQLITE_DB) | cut -f1))"; \
	else \
		echo "  ✗ $(SQLITE_DB) (not created - run 'make sqlite')"; \
	fi
	@echo ""
	@echo "Configuration:"
	@if [ -f $(METADATA_JSON) ]; then \
		echo "  ✓ $(METADATA_JSON)"; \
	else \
		echo "  ✗ $(METADATA_JSON) (missing!)"; \
	fi
	@echo ""
	@echo "Virtual environment:"
	@if [ -f $(VENV_DIR)/.done ]; then \
		echo "  ✓ $(VENV_DIR) (ready)"; \
	else \
		echo "  ✗ $(VENV_DIR) (not created - run 'make venv')"; \
	fi

.PHONY: versions
versions: check-venv
	@echo "Installed versions:"
	@$(VENV_DIR)/bin/python3 --version
	@$(VENV_DIR)/bin/pip show datasette | grep -E "^(Name|Version):"
	@$(VENV_DIR)/bin/pip show datasette-reconcile | grep -E "^(Name|Version):"
	@$(VENV_DIR)/bin/pip show sqlite-utils | grep -E "^(Name|Version):"

# =============================================================================
# Clean up
# =============================================================================
.PHONY: clean
clean:
	@echo "Cleaning generated files (keeping downloads)..."
	rm -rf $(DATA_DIR)
	rm -f $(FEATURE_CODES_TXT)
	@echo "✓ Cleaned. Run 'make clean-all' to also remove downloads and venv."

.PHONY: clean-all
clean-all: clean
	@echo "Removing downloads and virtual environment..."
	rm -f $(GEONAMES_ZIP)
	rm -f $(GEONAMES_TXT)
	rm -rf $(VENV_DIR)
	rm -f .python-version
	@echo "✓ All files removed."

.PHONY: clean-venv
clean-venv:
	rm -rf $(VENV_DIR)
	rm -f .python-version

.PHONY: clean-db
clean-db:
	rm -f $(SQLITE_DB)

# =============================================================================
# Help
# =============================================================================
.PHONY: help
help:
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "GeoNames Reconciliation Service"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo ""
	@echo "A datasette-based reconciliation endpoint for GeoNames data,"
	@echo "compatible with OpenRefine's W3C Reconciliation API."
	@echo ""
	@echo "Quick Start:"
	@echo "  make all           - Complete setup (downloads ~400MB, builds DB)"
	@echo "  make serve         - Start reconciliation server"
	@echo ""
	@echo "Setup Targets:"
	@echo "  all                - Full setup: venv + download + database"
	@echo "  setup              - Quick setup if files exist (venv + database)"
	@echo "  venv               - Create Python virtual environment"
	@echo "  download           - Download allCountries.zip from GeoNames"
	@echo "  extract            - Extract the zip file"
	@echo "  sqlite             - Build SQLite database with FTS"
	@echo ""
	@echo "Server:"
	@echo "  serve              - Start datasette server (localhost only)"
	@echo "  serve-public       - Start server accessible from network"
	@echo "  test-reconcile     - Test the reconciliation endpoint"
	@echo ""
	@echo "Database:"
	@echo "  sqlite-stats       - Show database statistics"
	@echo "  sqlite-test-fts    - Test full-text search"
	@echo "  sqlite-rebuild     - Rebuild database from scratch"
	@echo ""
	@echo "Utilities:"
	@echo "  list               - Show file status"
	@echo "  versions           - Show installed package versions"
	@echo ""
	@echo "Cleanup:"
	@echo "  clean              - Remove generated files (keeps downloads)"
	@echo "  clean-all          - Remove everything including downloads"
	@echo "  clean-venv         - Remove virtual environment only"
	@echo "  clean-db           - Remove database only"
	@echo ""
	@echo "Data Source:"
	@echo "  $(GEONAMES_URL)"
	@echo ""
	@echo "Reconciliation Endpoint (after 'make serve'):"
	@echo "  http://127.0.0.1:$(PORT)/geonames/geonames/-/reconcile"
	@echo ""
