# Makefile for Leaquor Project

# Variables
PROJECT_NAME = leaquor
DOCKER_IMAGE = $(PROJECT_NAME)-image
DOCKER_CONTAINER = $(PROJECT_NAME)-container
JULIA_SCRIPT = leaquor.jl
PATTERNS_FILE = patterns.yaml

# Default target
all: help

# Help target to display available commands
help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Available targets:"
	@echo "  install        Install Julia dependencies"
	@echo "  run            Run the script locally"
	@echo "  docker-build   Build the Docker image"
	@echo "  docker-run     Run the Docker container"
	@echo "  clean          Remove temporary files and build artifacts"
	@echo "  help           Display this help message"

# Install Julia dependencies
install:
	julia -e 'using Pkg; \
        Pkg.add("Glob"); \
        Pkg.add("JSON"); \
        Pkg.add("YAML"); \
        Pkg.add("LibGit2");'

# Run the script locally
run:
	@echo "Running Leaquor locally..."
	julia $(JULIA_SCRIPT) --help

# Build the Docker image
docker-build:
	@echo "Building Docker image $(DOCKER_IMAGE)..."
	docker build -t $(DOCKER_IMAGE) .

# Run the Docker container
docker-run:
	@echo "Running Docker container $(DOCKER_CONTAINER)..."
	docker run --rm -v $(PWD):/app $(DOCKER_IMAGE) --help

# Clean up temporary files and build artifacts
clean:
	@echo "Cleaning up..."
	rm -rf *.log *.tmp
	docker rmi -f $(DOCKER_IMAGE) || true
	docker rm -f $(DOCKER_CONTAINER) || true

.PHONY: all help install run docker-build docker-run clean
