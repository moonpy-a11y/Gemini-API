.PHONY: help setup-gcp setup-local run-analysis deploy clean

# Color output
GREEN := \033[0;32m
YELLOW := \033[0;33m
NC := \033[0m # No Color

help:
	@echo "$(GREEN)Gemini API - Google Cloud Commands$(NC)"
	@echo ""
	@echo "Setup Commands:"
	@echo "  make setup-gcp          - Automated GCP setup (requires gcloud CLI)"
	@echo "  make setup-local        - Install local Python dependencies"
	@echo ""
	@echo "Execution Commands:"
	@echo "  make run-analysis       - Run image analysis with GCP APIs"
	@echo "  make run-local          - Run in local mode (no GCP required)"
	@echo ""
	@echo "Deployment Commands:"
	@echo "  make deploy-docker      - Build and deploy Docker image"
	@echo "  make deploy-cloudrun    - Deploy to Cloud Run"
	@echo ""
	@echo "Utility Commands:"
	@echo "  make list-images        - List images in GCS bucket"
	@echo "  make query-results      - Query results from BigQuery"
	@echo "  make clean              - Clean up generated files"
	@echo ""

# Setup GCP environment
setup-gcp:
	@echo "$(GREEN)Setting up Google Cloud environment...$(NC)"
	@chmod +x setup.sh
	@./setup.sh

# Setup local environment
setup-local:
	@echo "$(GREEN)Installing Python dependencies...$(NC)"
	@pip install -r requirements.txt

# Run image analysis
run-analysis:
	@if [ -z "$(PROJECT_ID)" ] || [ -z "$(BUCKET_NAME)" ]; then \
		echo "$(YELLOW)Usage: make run-analysis PROJECT_ID=<id> BUCKET_NAME=<name>$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Running image analysis...$(NC)"
	@python3 app/analyze-images-v2.py $(PROJECT_ID) $(BUCKET_NAME)

# Run in local mode
run-local:
	@echo "$(GREEN)Running in local simulation mode...$(NC)"
	@python3 app/local-analyze.py

# Upload sample images
upload-images:
	@if [ -z "$(BUCKET_NAME)" ]; then \
		echo "$(YELLOW)Usage: make upload-images BUCKET_NAME=<name>$(NC)"; \
		exit 1; \
	fi
	@if [ ! -d "images" ]; then \
		echo "$(YELLOW)Creating sample images directory...$(NC)"; \
		mkdir -p images; \
	fi
	@echo "$(GREEN)Uploading images to gs://$(BUCKET_NAME)...$(NC)"
	@gsutil -m cp images/* gs://$(BUCKET_NAME)/

# List images in bucket
list-images:
	@if [ -z "$(BUCKET_NAME)" ]; then \
		echo "$(YELLOW)Usage: make list-images BUCKET_NAME=<name>$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Images in gs://$(BUCKET_NAME):$(NC)"
	@gsutil ls -h gs://$(BUCKET_NAME)/

# Query results from BigQuery
query-results:
	@if [ -z "$(PROJECT_ID)" ] || [ -z "$(DATASET)" ] || [ -z "$(TABLE)" ]; then \
		echo "$(YELLOW)Usage: make query-results PROJECT_ID=<id> DATASET=<name> TABLE=<name>$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Querying BigQuery results...$(NC)"
	@bq query --use_legacy_sql=false 'SELECT * FROM \`$(PROJECT_ID).$(DATASET).$(TABLE)\` ORDER BY processing_timestamp DESC LIMIT 20'

# Build Docker image
build-docker:
	@if [ -z "$(PROJECT_ID)" ]; then \
		echo "$(YELLOW)Usage: make build-docker PROJECT_ID=<id>$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Building Docker image...$(NC)"
	@docker build -f docker/Dockerfile -t gcr.io/$(PROJECT_ID)/gemini-api-processor:latest .

# Deploy to Cloud Run
deploy-cloudrun:
	@if [ -z "$(PROJECT_ID)" ] || [ -z "$(BUCKET_NAME)" ]; then \
		echo "$(YELLOW)Usage: make deploy-cloudrun PROJECT_ID=<id> BUCKET_NAME=<name>$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Deploying to Cloud Run...$(NC)"
	@gcloud run deploy gemini-api-processor \
		--image gcr.io/$(PROJECT_ID)/gemini-api-processor:latest \
		--platform managed \
		--region us-central1 \
		--set-env-vars="PROJECT_ID=$(PROJECT_ID),BUCKET_NAME=$(BUCKET_NAME)"

# Clean up
clean:
	@echo "$(GREEN)Cleaning up...$(NC)"
	@find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -delete
	@find . -type f -name ".pytest_cache" -delete
	@rm -rf build/ dist/ *.egg-info/
	@echo "$(GREEN)Cleanup complete!$(NC)"

# Full setup (GCP + Local)
setup: setup-gcp setup-local
	@echo ""
	@echo "$(GREEN)✅ Setup complete! Next steps:$(NC)"
	@echo "  1. Load environment: source .env"
	@echo "  2. Upload images: make upload-images BUCKET_NAME=<name>"
	@echo "  3. Run analysis: make run-analysis PROJECT_ID=<id> BUCKET_NAME=<name>"

# View logs
logs:
	@if [ -z "$(SERVICE_NAME)" ]; then \
		echo "$(YELLOW)Usage: make logs SERVICE_NAME=<name>$(NC)"; \
		exit 1; \
	fi
	@gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=$(SERVICE_NAME)" \
		--limit 50 --format json

# Health check
health-check:
	@echo "$(GREEN)Checking GCP connectivity...$(NC)"
	@gcloud auth list
	@echo ""
	@echo "$(GREEN)Checking gcloud version...$(NC)"
	@gcloud --version
	@echo ""
	@echo "$(GREEN)Checking Python version...$(NC)"
	@python3 --version
