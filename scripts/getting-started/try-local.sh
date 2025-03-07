#!/bin/bash
#
# This file and its contents are licensed under the Apache License 2.0.
# Please see the included NOTICE for copyright information and
# LICENSE-APACHE for a copy of the license.
#

set -euo pipefail

# Global Variables
CONTAINER_NAME="timescaledb"
POSTGRES_PASSWORD="tsdb"
IMAGE_NAME="timescale/timescaledb:latest-pg17"
DB_PORT=5432
DB_USER="postgres"

# Color Codes
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Welcome Message
welcome() {
    echo "${YELLOW}"
    echo "|----------------------------------------------------------|"
    echo "|                                                          |"
    echo "|          ████████  ██████  ██████   ██████               |"
    echo "|             ██     ██      ██   ██  ██   ██              |"
    echo "|             ██     ██████  ██   ██  ██████               |"
    echo "|             ██         ██  ██   ██  ██   ██              |"
    echo "|             ██     ██████  ██████   ██████               |"
    echo "|                                                          |"
    echo "|----------------------------------------------------------|"
    echo "${NC}\n"
    echo "${RED}⚠${NC} This script is not intended for production use."
    echo ""
    echo "------------------------------------------------------------"
    echo ""
    echo "Try Timescale Cloud: https://tsdb.co/get-started-guide"
    echo "Other options: https://tsdb.co/tsdb-self-hosted"
    echo ""
    echo "------------------------------------------------------------"
    echo ""
    echo "Container name   : ${CONTAINER_NAME}"
    echo "Image name       : ${IMAGE_NAME}"
    echo "Postgres user    : ${DB_USER}"
    echo "Postgres password: ${POSTGRES_PASSWORD}"
    echo "Postgres port    : ${DB_PORT}"
    echo ""
    echo "------------------------------------------------------------"
    echo ""
}

# Function to check OS compatibility
check_os() {
    case "$(uname -s)" in
        Linux|Darwin|MINGW*|CYGWIN*|MSYS*) return 0 ;;
        *) printf "${RED}Unsupported OS. This script supports Linux, macOS, and Windows.\n${NC}" >&2; return 1 ;;
    esac
}

# Function to check if Docker is installed and running
check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        printf "${RED}Docker is not installed. Please install Docker and try again.\n${NC}" >&2
        return 1
    fi
    if ! docker info >/dev/null 2>&1; then
        printf "${RED}Docker is not running. Please start Docker and try again.\n${NC}" >&2
        return 1
    fi
}

# Function to start TimescaleDB container
start_timescaledb() {
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        printf "Container '%s' is already running.\n" "$CONTAINER_NAME"
        return 0
    fi

    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        printf "Starting existing container '%s'...\n" "$CONTAINER_NAME"
        docker start "$CONTAINER_NAME"
    else
        printf "Creating and starting container '%s'...\n" "$CONTAINER_NAME"
        docker run -d --name "$CONTAINER_NAME" \
            -p "$DB_PORT":5432 \
            -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
            "$IMAGE_NAME"
    fi
}

# Wait for TimescaleDB to have fully started
wait_for_timescaledb() {
    is_ready_string="accepting connections"
    timescaledb_ready=0
    while [ $timescaledb_ready -le 0 ]
    do
        timescaledb_response=$(docker exec "$CONTAINER_NAME" pg_isready -U "$DB_USER")
        if [[ "$timescaledb_response" == *"$is_ready_string"* ]]; then
            echo "TimescaleDB ready..."
            timescaledb_ready=1
        fi
        sleep 1
    done
}

# Function to log into PostgreSQL
login_postgres() {
    printf "Logging into TimescaleDB...\n"
    docker exec -it "$CONTAINER_NAME" psql -U "$DB_USER"
}

# Main Execution
main() {
    welcome
    check_os || exit 1
    check_docker || exit 1
    start_timescaledb || exit 1
    wait_for_timescaledb || exit 1
    login_postgres
}

main
