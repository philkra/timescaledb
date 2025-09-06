#!/bin/bash

# TimescaleDB Docker Setup Script
# Usage: curl -fsSL <your-url>/install.sh | sh
# Or: curl -fsSL <your-url>/install.sh | bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONTAINER_NAME="timescaledb-server"
POSTGRES_PASSWORD="password"
POSTGRES_DB="timescaledb"
POSTGRES_USER="postgres"
HOST_PORT="5432"
TIMESCALE_IMAGE="timescale/timescaledb:latest-pg16"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    else
        log_error "Unsupported operating system: $OSTYPE"
        exit 1
    fi
    log_info "Detected OS: $OS"
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        echo "Please install Docker first:"
        if [[ "$OS" == "macos" ]]; then
            echo "  - Download Docker Desktop from: https://www.docker.com/products/docker-desktop"
            echo "  - Or install via Homebrew: brew install --cask docker"
        else
            echo "  - Ubuntu/Debian: sudo apt-get install docker.io"
            echo "  - CentOS/RHEL: sudo yum install docker"
            echo "  - Or follow official guide: https://docs.docker.com/engine/install/"
        fi
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        echo "Please start Docker daemon:"
        if [[ "$OS" == "macos" ]]; then
            echo "  - Start Docker Desktop application"
        else
            echo "  - sudo systemctl start docker"
            echo "  - sudo service docker start"
        fi
        exit 1
    fi

    log_success "Docker is installed and running"
}

stop_existing_container() {
    if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
        log_warning "Stopping existing container: $CONTAINER_NAME"
        docker stop "$CONTAINER_NAME" > /dev/null 2>&1
    fi

    if docker ps -aq -f name="$CONTAINER_NAME" | grep -q .; then
        log_warning "Removing existing container: $CONTAINER_NAME"
        docker rm "$CONTAINER_NAME" > /dev/null 2>&1
    fi
}

check_port() {
    if command -v lsof &> /dev/null; then
        if lsof -Pi :$HOST_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
            log_warning "Port $HOST_PORT is already in use"
            read -p "Do you want to use a different port? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                read -p "Enter new port number: " HOST_PORT
                log_info "Using port: $HOST_PORT"
            else
                log_warning "Continuing with port $HOST_PORT (may cause conflicts)"
            fi
        fi
    fi
}

pull_image() {
    log_info "Pulling TimescaleDB image: $TIMESCALE_IMAGE"
    if ! docker pull "$TIMESCALE_IMAGE"; then
        log_error "Failed to pull TimescaleDB image"
        exit 1
    fi
    log_success "Successfully pulled TimescaleDB image"
}

start_container() {
    log_info "Starting TimescaleDB container..."
    
    if docker run -d \
        --name "$CONTAINER_NAME" \
        -p "${HOST_PORT}:5432" \
        -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
        -e POSTGRES_DB="$POSTGRES_DB" \
        -e POSTGRES_USER="$POSTGRES_USER" \
        -v timescaledb-data:/var/lib/postgresql/data \
        "$TIMESCALE_IMAGE" > /dev/null; then
        
        log_success "TimescaleDB container started successfully!"
    else
        log_error "Failed to start TimescaleDB container"
        exit 1
    fi
}

wait_for_database() {
    log_info "Waiting for database to be ready..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker exec "$CONTAINER_NAME" pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" > /dev/null 2>&1; then
            log_success "Database is ready!"
            return 0
        fi
        
        echo -n "."
        sleep 1
        ((attempt++))
    done
    
    echo
    log_error "Database failed to start within $max_attempts seconds"
    return 1
}

show_connection_info() {
    echo
    echo "=================================================="
    echo -e "${GREEN}TimescaleDB is now running!${NC}"
    echo "=================================================="
    echo
    echo "Connection Details:"
    echo "  Host: localhost"
    echo "  Port: $HOST_PORT"
    echo "  Database: $POSTGRES_DB"
    echo "  Username: $POSTGRES_USER"
    echo "  Password: $POSTGRES_PASSWORD"
    echo
    echo "Connection String:"
    echo "  postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:$HOST_PORT/$POSTGRES_DB"
    echo
    echo "Connect using psql:"
    echo "  docker exec -it $CONTAINER_NAME psql -U $POSTGRES_USER -d $POSTGRES_DB"
    echo
    echo "Or connect from host (if psql is installed):"
    echo "  psql -h localhost -p $HOST_PORT -U $POSTGRES_USER -d $POSTGRES_DB"
    echo
    echo "Useful Commands:"
    echo "  Stop container:    docker stop $CONTAINER_NAME"
    echo "  Start container:   docker start $CONTAINER_NAME"
    echo "  Remove container:  docker rm $CONTAINER_NAME"
    echo "  View logs:         docker logs $CONTAINER_NAME"
    echo
    echo "Data is persisted in Docker volume: timescaledb-data"
    echo "=================================================="
}

# Main execution
main() {
    echo "=================================================="
    echo "TimescaleDB Docker Setup Script"
    echo "=================================================="
    echo
    
    check_os
    check_docker
    check_port
    stop_existing_container
    pull_image
    start_container
    
    if wait_for_database; then
        show_connection_info
        
        # Test TimescaleDB extension
        log_info "Testing TimescaleDB extension..."
        if docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "CREATE EXTENSION IF NOT EXISTS timescaledb;" > /dev/null 2>&1; then
            log_success "TimescaleDB extension is working!"
        else
            log_warning "TimescaleDB extension test failed, but PostgreSQL is running"
        fi
        
        echo
        log_success "Setup completed successfully!"
        echo
        echo "You can now connect to your TimescaleDB instance."
        echo "Visit https://docs.timescale.com/ for documentation and tutorials."
    else
        log_error "Setup failed!"
        exit 1
    fi
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "TimescaleDB Docker Setup Script"
        echo
        echo "Usage: $0 [options]"
        echo
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --password     Set PostgreSQL password (default: password)"
        echo "  --port         Set host port (default: 5432)"
        echo "  --name         Set container name (default: timescaledb-server)"
        echo
        echo "Examples:"
        echo "  $0"
        echo "  $0 --password mypassword --port 5433"
        echo
        echo "Or install via curl:"
        echo "  curl -fsSL <your-url>/install.sh | sh"
        exit 0
        ;;
    --password)
        POSTGRES_PASSWORD="$2"
        shift 2
        ;;
    --port)
        HOST_PORT="$2"
        shift 2
        ;;
    --name)
        CONTAINER_NAME="$2"
        shift 2
        ;;
esac

# Run main function
main