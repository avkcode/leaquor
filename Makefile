# Makefile for Leaquor Project

# Variables
PROJECT_NAME = leaquor
DOCKER_IMAGE = $(PROJECT_NAME)-image
DOCKER_CONTAINER = $(PROJECT_NAME)-container
JULIA_SCRIPT = leaquor.jl
PATTERNS_FILE = patterns.yaml

TEST_REPO_URL = https://github.com/Plazmaz/leaky-repo.git
TEST_REPO_DIR = leaky-repo

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
	@echo "  test           Run tests using the test repository"
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

# Test target to validate the script
test: docker-build clone-test-repo
	@echo "Running tests..."
	docker run --rm \
        	-v $(PWD)/$(JULIA_SCRIPT):/app/$(JULIA_SCRIPT) \
        	-v $(PWD)/$(TEST_REPO_DIR):/app/$(TEST_REPO_DIR) \
        	--name $(DOCKER_CONTAINER) \
        	$(DOCKER_IMAGE) \
        	julia /app/$(JULIA_SCRIPT) --dir /app/$(TEST_REPO_DIR) \
			--patterns patterns.yaml \
			--output-file results.json \
	       		--log-file /app/test.log
	@echo "Tests completed. Check test.log for details."

# Clone the test repository
clone-test-repo:
	@if [ ! -d "$(TEST_REPO_DIR)" ]; then \
		echo "Cloning test repository from $(TEST_REPO_URL)..."; \
		git clone $(TEST_REPO_URL) $(TEST_REPO_DIR); \
	else \
		echo "Test repository already exists. Skipping clone."; \
	fi

# Clean up temporary files and build artifacts
clean:
	@echo "Cleaning up..."
	rm -rf *.log *.tmp $(TEST_REPO_DIR)
	docker rmi -f $(DOCKER_IMAGE) || true
	docker rm -f $(DOCKER_CONTAINER) || true

# Target: Create a Git tag and release on GitHub
.PHONY: release
release:
	@echo "Creating Git tag and releasing on GitHub..."
	@read -p "Enter the version number (e.g., v1.0.0): " version; \
	git tag -a $$version -m "Release $$version"; \
	git push origin $$version; \
	gh release create $$version --generate-notes
	@echo "Release $$version created and pushed to GitHub."

.PHONY: all help install run docker-build docker-run test clean
