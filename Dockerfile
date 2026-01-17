# GeoNames Reconciliation Service
# 
# Build:  docker build -t geonames-reconcile .
# Run:    docker compose up
#
# Or without compose:
#   docker run -p 8001:8001 -v geonames-data:/app/data geonames-reconcile

FROM python:3.12-slim

LABEL maintainer="SOAS Library Services"
LABEL description="GeoNames Reconciliation Service for OpenRefine"

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    sqlite3 \
    make \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Install Python dependencies (separate layer for caching)
RUN pip install --no-cache-dir \
    datasette \
    datasette-reconcile \
    sqlite-utils \
    csvkit \
    httpx

# Copy build files
COPY Makefile geonames.metadata.json ./

# Create data directory for volume mount
RUN mkdir -p /app/data

# Environment: Docker mode + data paths
ENV DOCKER=1
ENV DATA_DIR=/app/data
ENV GEONAMES_ZIP=/app/data/allCountries.zip
ENV GEONAMES_TXT=/app/data/allCountries.txt
ENV FEATURE_CODES_TXT=/app/data/featureCodes_en.txt
ENV SQLITE_DB=/app/data/geonames.db

# Expose the datasette port
EXPOSE 8001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8001/ || exit 1

# Default command
CMD ["make", "serve", "PUBLIC=1"]
