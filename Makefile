PROJECT_NAME = leaquor
DOCKER_IMAGE = $(PROJECT_NAME)-image
DOCKER_CONTAINER = $(PROJECT_NAME)-container
JULIA_SCRIPT = leaquor.jl
PATTERNS_FILE = patterns.yaml

TEST_REPO_URL = https://github.com/Plazmaz/leaky-repo.git
TEST_REPO_DIR = leaky-repo

DOCKER_HUB_USERNAME ?= leaquor
DOCKER_HUB_REPO ?= $(DOCKER_HUB_USERNAME)/$(PROJECT_NAME)
JULIA_VERSION ?= v1.11.5  # Default Julia version to install

# Default target
all: help

help:
	@echo "Available targets:"
	@echo "  test             - Run unit tests"
	@echo "  docker-build     - Build the Docker image"
	@echo "  docker-run       - Run the Docker container"
	@echo "  docker-push      - Push the Docker image to Docker Hub"
	@echo "  release          - Create a GitHub release"
	@echo "  open-issue       - Open a new issue on GitHub"
	@echo "  create-pr        - Create a pull request"
	@echo "  list-issues      - List open issues"
	@echo "  list-prs         - List open pull requests"
	@echo "  deploy-docs      - Deploy documentation to GitHub Pages"
	@echo "  check-workflows  - Check GitHub Actions workflow status"
	@echo "  generate-changelog - Generate a changelog"

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

# Push the Docker image to Docker Hub
docker-push: docker-build
	@echo "Logging into Docker Hub..."
	@docker login -u $(DOCKER_HUB_USERNAME)
	@echo "Tagging image for Docker Hub..."
	docker tag $(DOCKER_IMAGE) $(DOCKER_HUB_REPO):latest
	@echo "Pushing image to Docker Hub..."
	docker push $(DOCKER_HUB_REPO):latest
	@echo "Image pushed successfully to $(DOCKER_HUB_REPO):latest"

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

# Open a new issue on GitHub
open-issue:
	@echo "Opening a new issue on GitHub..."
	@if [ -z "$(TITLE)" ] || [ -z "$(BODY)" ]; then \
        	echo "Error: TITLE and BODY must be provided. Use 'make open-issue TITLE=\"<title>\" BODY=\"<body>\"'"; \
       		exit 1; \
    	fi
	gh issue create --title "$(TITLE)" --body "$(BODY)"
	@echo "Issue created successfully."

# Create a pull request
create-pr:
	@echo "Creating a pull request..."
	@if [ -z "$(BRANCH)" ] || [ -z "$(BASE)" ] || [ -z "$(TITLE)" ]; then \
        	echo "Error: BRANCH, BASE, and TITLE must be provided. Use 'make create-pr BRANCH=<branch> BASE=<base> TITLE=\"<title>\"'"; \
        	exit 1; \
    	fi
	gh pr create --base $(BASE) --head $(BRANCH) --title "$(TITLE)" --body "$(BODY)"
	@echo "Pull request created successfully."

# List open issues
list-issues:
	@echo "Listing open issues..."
	gh issue list --state open

# List open pull requests
list-prs:
	@echo "Listing open pull requests..."
	gh pr list --state open

# Deploy documentation to GitHub Pages
deploy-docs:
	@echo "Deploying documentation to GitHub Pages..."
	gh repo set-default
	gh pages deploy ./docs --cname your-custom-domain.com
	@echo "Documentation deployed to GitHub Pages."

# Check GitHub Actions workflow status
check-workflows:
	@echo "Checking GitHub Actions workflow status..."
	gh run list --workflow=all

# Generate a changelog
generate-changelog:
	@echo "Generating changelog..."
	@if [ -z "$(FROM)" ] || [ -z "$(TO)" ]; then \
        	echo "Error: FROM and TO must be provided. Use 'make generate-changelog FROM=<tag/commit> TO=<tag/commit>'"; \
        	exit 1; \
    	fi
	gh api repos/$(OWNER)/$(REPO)/pulls --jq '.[] | select(.merged_at != null) | "- \(.title) (#\(.number))"' > CHANGELOG.md
	@echo "Changelog generated in CHANGELOG.md."

.PHONY: all help install run docker-build docker-run test clean
