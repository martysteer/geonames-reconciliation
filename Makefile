# Makefile for GeoNames Reconciliation Service
#
# Creates a datasette-based reconciliation endpoint for GeoNames geographic data
# compatible with OpenRefine's reconciliation API (W3C Reconciliation Service API v0.2)
#
# Usage (native):
#   make build    - Complete setup: venv + download + database
#   make serve    - Start datasette reconciliation server (use PUBLIC=1 for network access)
#   make test     - Test FTS and reconciliation endpoint
#   make status   - Show file status and database statistics
#   make update   - Re-download source data and rebuild database
#   make clean    - Remove database only (quick reset)
#   make clean-all - Remove everything including downloads and venv
#
# Usage (Docker):
#   docker compose up              - Build and serve (first run downloads data)
#   docker compose run --rm geonames make status

# =============================================================================
# Configuration (override with environment variables for Docker)
# =============================================================================
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

PYTHON_VERSION ?= 3.12.4
VENV_DIR ?= .venv

# Data file paths (override for Docker volume mounts)
DATA_DIR ?= .
GEONAMES_URL := https://download.geonames.org/export/dump/allCountries.zip
GEONAMES_ZIP ?= $(DATA_DIR)/allCountries.zip
GEONAMES_TXT ?= $(DATA_DIR)/allCountries.txt

FEATURE_CODES_URL := https://download.geonames.org/export/dump/featureCodes_en.txt
FEATURE_CODES_TXT ?= $(DATA_DIR)/featureCodes_en.txt

SQLITE_DB ?= $(DATA_DIR)/geonames.db
METADATA_JSON ?= geonames.metadata.json

PORT ?= 8001

# Docker mode: when DOCKER=1, skip venv and use system Python
DOCKER ?=

.PRECIOUS: $(GEONAMES_ZIP) $(GEONAMES_TXT)

# =============================================================================
# Tool paths (venv or system depending on DOCKER mode)
# =============================================================================
ifdef DOCKER
  PYTHON := python3
  PIP := pip
  DATASETTE := datasette
  SQLITE_UTILS := sqlite-utils
  VENV_DONE :=
else
  PYTHON := $(VENV_DIR)/bin/python3
  PIP := $(VENV_DIR)/bin/pip
  DATASETTE := $(VENV_DIR)/bin/datasette
  SQLITE_UTILS := $(VENV_DIR)/bin/sqlite-utils
  VENV_DONE := $(VENV_DIR)/.done
endif

# =============================================================================
# Main Targets
# =============================================================================
.PHONY: build
build: $(VENV_DONE) $(SQLITE_DB)
	@echo ""
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "✓ GeoNames Reconciliation Service is ready!"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo ""
	@echo "Start the server with: make serve"
	@echo ""

.PHONY: serve
serve: $(VENV_DONE) $(SQLITE_DB) $(METADATA_JSON)
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "Starting GeoNames Reconciliation Service"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo ""
	@echo "Reconciliation endpoint:"
	@echo "  http://127.0.0.1:$(PORT)/geonames/geonames/-/reconcile"
	@echo ""
	@echo "Add to OpenRefine:"
	@echo "  1. Column dropdown → Reconcile → Start reconciling..."
	@echo "  2. Click 'Add Standard Service...'"
	@echo "  3. Enter: http://127.0.0.1:$(PORT)/geonames/geonames/-/reconcile"
	@echo ""
	@echo "Press Ctrl+C to stop"
	@echo "═══════════════════════════════════════════════════════════════"
	@HOST=$${PUBLIC:+0.0.0.0}; HOST=$${HOST:-127.0.0.1}; \
	$(DATASETTE) $(SQLITE_DB) \
		--metadata $(METADATA_JSON) \
		--port $(PORT) \
		--host $$HOST \
		--setting sql_time_limit_ms 5000 \
		--setting max_returned_rows 1000

.PHONY: test
test: $(VENV_DONE) $(SQLITE_DB)
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "Testing GeoNames Service"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo ""
	@echo "FTS search for 'London':"
	@sqlite3 -header -column $(SQLITE_DB) " \
		SELECT g.id, g.name, g.country_code, g.type, g.population \
		FROM geonames g \
		INNER JOIN geonames_fts fts ON g.rowid = fts.rowid \
		WHERE geonames_fts MATCH 'London' \
		ORDER BY g.population DESC \
		LIMIT 5;"
	@echo ""
	@echo "Reconciliation endpoint test:"
	@$(PYTHON) -c " \
import json, httpx; \
queries = {'q0': {'query': 'London'}, 'q1': {'query': 'Paris'}}; \
try: \
    r = httpx.post('http://127.0.0.1:$(PORT)/geonames/geonames/-/reconcile', \
        data={'queries': json.dumps(queries)}, timeout=10); \
    print(json.dumps(r.json(), indent=2)); \
except httpx.ConnectError: \
    print('Server not running. Start with: make serve'); \
"

.PHONY: status
status:
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "GeoNames Service Status"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo ""
	@echo "Files:"
ifdef DOCKER
	@echo "  ✓ Docker mode (system Python)"
else
	@if [ -f $(VENV_DIR)/.done ]; then echo "  ✓ venv"; else echo "  ✗ venv"; fi
endif
	@if [ -f $(GEONAMES_ZIP) ]; then echo "  ✓ $(GEONAMES_ZIP) ($$(du -h $(GEONAMES_ZIP) | cut -f1))"; else echo "  ✗ $(GEONAMES_ZIP)"; fi
	@if [ -f $(GEONAMES_TXT) ]; then echo "  ✓ $(GEONAMES_TXT) ($$(wc -l < $(GEONAMES_TXT) | tr -d ' ') lines)"; else echo "  ✗ $(GEONAMES_TXT)"; fi
	@if [ -f $(SQLITE_DB) ]; then echo "  ✓ $(SQLITE_DB) ($$(du -h $(SQLITE_DB) | cut -f1))"; else echo "  ✗ $(SQLITE_DB)"; fi
	@if [ -f $(METADATA_JSON) ]; then echo "  ✓ $(METADATA_JSON)"; else echo "  ✗ $(METADATA_JSON) (missing!)"; fi
	@echo ""
	@if [ -f $(SQLITE_DB) ]; then \
		echo "Database:"; \
		echo "  Records: $$(sqlite3 $(SQLITE_DB) 'SELECT COUNT(*) FROM geonames;')"; \
		echo ""; \
		echo "  By feature class:"; \
		sqlite3 -column $(SQLITE_DB) " \
			SELECT feature_class, COUNT(*) as count \
			FROM geonames GROUP BY feature_class ORDER BY count DESC;"; \
	fi
	@echo ""
ifndef DOCKER
	@if [ -f $(VENV_DIR)/.done ]; then \
		echo "Versions:"; \
		$(PYTHON) --version | sed 's/^/  /'; \
		$(PIP) show datasette 2>/dev/null | grep Version | sed 's/^/  datasette /'; \
	fi
endif

.PHONY: update
update: clean
	@rm -f $(GEONAMES_ZIP) $(GEONAMES_TXT) $(FEATURE_CODES_TXT)
	@echo "Re-downloading and rebuilding..."
	@$(MAKE) build

.PHONY: clean
clean:
	@echo "Removing database..."
	@rm -f $(SQLITE_DB)
	@echo "✓ Done. Run 'make build' to rebuild."

.PHONY: clean-all
clean-all:
	@echo "Removing all generated files..."
	@rm -f $(SQLITE_DB) $(GEONAMES_ZIP) $(GEONAMES_TXT) $(FEATURE_CODES_TXT) .python-version
ifndef DOCKER
	@rm -rf $(VENV_DIR)
endif
	@echo "✓ All files removed."

# =============================================================================
# Virtual Environment (skipped in Docker mode)
# =============================================================================
.PHONY: venv
venv: $(VENV_DONE)

ifndef DOCKER
$(VENV_DIR)/.done:
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "Setting up Python virtual environment"
	@echo "═══════════════════════════════════════════════════════════════"
	@if command -v pyenv >/dev/null 2>&1; then \
		echo "Using pyenv..."; \
		pyenv install -s $(PYTHON_VERSION); \
		pyenv local $(PYTHON_VERSION); \
	fi
	@python3 -m venv $(VENV_DIR)
	@$(PIP) install --upgrade pip -q
	@$(PIP) install datasette datasette-reconcile sqlite-utils csvkit httpx -q
	@touch $@
	@echo "✓ Virtual environment ready"
endif

# =============================================================================
# Data Downloads
# =============================================================================
$(GEONAMES_ZIP):
	@echo "Downloading GeoNames data (~400MB)..."
	@curl -L --progress-bar -o $@ "$(GEONAMES_URL)"

$(FEATURE_CODES_TXT):
	@curl -sL -o $@ "$(FEATURE_CODES_URL)"

$(GEONAMES_TXT): $(GEONAMES_ZIP)
	@echo "Extracting..."
	@unzip -oq $(GEONAMES_ZIP) -d $(DATA_DIR)
	@touch $@

# =============================================================================
# Database Build
# =============================================================================
$(SQLITE_DB): $(VENV_DONE) $(GEONAMES_TXT) $(FEATURE_CODES_TXT)
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "Building SQLite database (this takes several minutes)..."
	@echo "═══════════════════════════════════════════════════════════════"
	@rm -f $(SQLITE_DB)
	@echo "  Importing feature codes..."
	@echo "code	name	description" | cat - $(FEATURE_CODES_TXT) | \
		$(SQLITE_UTILS) insert $(SQLITE_DB) feature_codes - --tsv
	@echo "  Importing GeoNames data..."
	@echo "geonameid	name	asciiname	alternatenames	latitude	longitude	feature_class	feature_code	country_code	cc2	admin1_code	admin2_code	admin3_code	admin4_code	population	elevation	dem	timezone	modification_date" | \
		cat - $(GEONAMES_TXT) | $(SQLITE_UTILS) insert $(SQLITE_DB) geonames - --tsv
	@echo "  Adding columns and indexes..."
	@$(SQLITE_UTILS) add-column $(SQLITE_DB) geonames searchText text 2>/dev/null || true
	@$(SQLITE_UTILS) add-column $(SQLITE_DB) geonames type text 2>/dev/null || true
	@$(SQLITE_UTILS) add-column $(SQLITE_DB) geonames id text 2>/dev/null || true
	@sqlite3 $(SQLITE_DB) " \
		UPDATE geonames SET \
			id = CAST(geonameid AS TEXT), \
			type = feature_class, \
			searchText = name || ' ' || COALESCE(asciiname, '') || ' ' || COALESCE(alternatenames, ''); \
		CREATE INDEX IF NOT EXISTS idx_geonames_id ON geonames(id); \
		CREATE INDEX IF NOT EXISTS idx_geonames_type ON geonames(type); \
		CREATE INDEX IF NOT EXISTS idx_geonames_country ON geonames(country_code); \
		CREATE INDEX IF NOT EXISTS idx_geonames_name ON geonames(name);"
	@echo "  Creating FTS index..."
	@$(SQLITE_UTILS) enable-fts $(SQLITE_DB) geonames searchText name --fts5 --create-triggers
	@echo ""
	@echo "✓ Database ready: $$(du -h $(SQLITE_DB) | cut -f1), $$(sqlite3 $(SQLITE_DB) 'SELECT COUNT(*) FROM geonames;') records"

$(METADATA_JSON):
	@echo "ERROR: $(METADATA_JSON) not found! Restore from git."
	@exit 1

# =============================================================================
# Help
# =============================================================================
.PHONY: help
help:
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "GeoNames Reconciliation Service"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo ""
	@echo "Datasette-based reconciliation endpoint for GeoNames data,"
	@echo "compatible with OpenRefine's W3C Reconciliation API."
	@echo ""
	@echo "Native usage:"
	@echo "  make build      Complete setup: venv + download + database"
	@echo "  make serve      Start server (use PUBLIC=1 for network access)"
	@echo "  make test       Test FTS search and reconciliation endpoint"
	@echo "  make status     Show file status and database statistics"
	@echo "  make update     Re-download source data and rebuild"
	@echo "  make clean      Remove database only"
	@echo "  make clean-all  Remove everything including downloads and venv"
	@echo "  make venv       Create Python virtual environment only"
	@echo ""
	@echo "Docker usage:"
	@echo "  docker compose up           Build and start service"
	@echo "  docker compose run --rm geonames make status"
	@echo ""
	@echo "Quick start:"
	@echo "  make build && make serve"
	@echo ""
	@echo "Endpoint: http://127.0.0.1:$(PORT)/geonames/geonames/-/reconcile"
	@echo ""
