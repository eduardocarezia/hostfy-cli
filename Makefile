.PHONY: build build-all clean test install dev

VERSION ?= 1.0.0
BINARY_NAME = hostfy
BUILD_DIR = build
MAIN_PATH = ./cmd/hostfy

# Go build flags
LDFLAGS = -ldflags "-s -w -X github.com/eduardocarezia/hostfy-cli/internal/cli.Version=$(VERSION)"

# Default target
all: build

# Build for current platform
build:
	@echo "Building $(BINARY_NAME)..."
	@go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME) $(MAIN_PATH)
	@echo "Built: $(BUILD_DIR)/$(BINARY_NAME)"

# Build for all platforms
build-all: clean
	@echo "Building for all platforms..."
	@mkdir -p $(BUILD_DIR)

	@echo "Building linux/amd64..."
	@GOOS=linux GOARCH=amd64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-linux-amd64 $(MAIN_PATH)

	@echo "Building linux/arm64..."
	@GOOS=linux GOARCH=arm64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-linux-arm64 $(MAIN_PATH)

	@echo "Building linux/arm..."
	@GOOS=linux GOARCH=arm go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-linux-arm $(MAIN_PATH)

	@echo "Building darwin/amd64..."
	@GOOS=darwin GOARCH=amd64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-darwin-amd64 $(MAIN_PATH)

	@echo "Building darwin/arm64..."
	@GOOS=darwin GOARCH=arm64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-darwin-arm64 $(MAIN_PATH)

	@echo "All builds complete!"
	@ls -la $(BUILD_DIR)/

# Clean build artifacts
clean:
	@echo "Cleaning..."
	@rm -rf $(BUILD_DIR)
	@go clean

# Run tests
test:
	@go test -v ./...

# Install locally
install: build
	@echo "Installing to /usr/local/bin..."
	@sudo cp $(BUILD_DIR)/$(BINARY_NAME) /usr/local/bin/$(BINARY_NAME)
	@sudo chmod +x /usr/local/bin/$(BINARY_NAME)
	@echo "Installed!"

# Development run
dev:
	@go run $(MAIN_PATH) $(ARGS)

# Download dependencies
deps:
	@echo "Downloading dependencies..."
	@go mod download
	@go mod tidy
	@echo "Dependencies ready!"

# Format code
fmt:
	@go fmt ./...

# Lint code
lint:
	@golangci-lint run

# Generate checksums
checksums: build-all
	@echo "Generating checksums..."
	@cd $(BUILD_DIR) && sha256sum * > checksums.txt
	@cat $(BUILD_DIR)/checksums.txt

# Create release
release: checksums
	@echo "Release $(VERSION) ready in $(BUILD_DIR)/"
