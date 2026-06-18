#!/bin/bash

################################################################################
# Google Cloud Setup Automation Script
# This script automates the setup of the Gemini API project on GCP
################################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SERVICE_ACCOUNT_NAME="ml-api-sa"
DATASET_NAME="image_classification_dataset"
TABLE_NAME="image_text_detail"
REGION="us-central1"

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "$1 is not installed. Please install it first."
        exit 1
    fi
}

################################################################################
# Prerequisite Checks
################################################################################

print_header "Checking Prerequisites"

check_command "gcloud"
check_command "bq"
check_command "gsutil"
check_command "python3"

print_success "All prerequisites are installed"

################################################################################
# Set up Google Cloud Project
################################################################################

print_header "Step 1: Google Cloud Project Setup"

PROJECT_ID=$(gcloud config get-value project)

if [ -z "$PROJECT_ID" ]; then
    print_error "No GCP project set. Please run: gcloud config set project PROJECT_ID"
    exit 1
fi

print_success "Using project: $PROJECT_ID"

# Enable APIs
print_header "Enabling Required APIs"

APIS=(
    "vision.googleapis.com"
    "translate.googleapis.com"
    "bigquery.googleapis.com"
    "storage-api.googleapis.com"
    "storage.googleapis.com"
    "cloudresourcemanager.googleapis.com"
)

for api in "${APIS[@]}"; do
    echo "Enabling $api..."
    gcloud services enable $api --quiet
done

print_success "All APIs enabled"

################################################################################
# Create Service Account
################################################################################

print_header "Step 2: Service Account Setup"

SA_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Check if service account already exists
if gcloud iam service-accounts describe $SA_EMAIL &>/dev/null; then
    print_warning "Service account $SA_EMAIL already exists. Skipping creation."
else
    echo "Creating service account..."
    gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
        --display-name="Machine Learning API Service Account" \
        --quiet
    print_success "Service account created: $SA_EMAIL"
fi

# Grant roles
echo "Granting IAM roles..."
ROLES=(
    "roles/storage.admin"
    "roles/bigquery.dataEditor"
    "roles/bigquery.user"
    "roles/serviceusage.serviceUsageConsumer"
)

for role in "${ROLES[@]}"; do
    echo "  - Granting $role..."
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:$SA_EMAIL" \
        --role="$role" \
        --quiet 2>/dev/null || echo "    (Role already assigned)"
done

print_success "IAM roles configured"

################################################################################
# Create Service Account Key
################################################################################

print_header "Step 3: Service Account Key"

KEY_FILE="key.json"

if [ -f "$KEY_FILE" ]; then
    print_warning "Key file already exists: $KEY_FILE"
    read -p "Overwrite existing key? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm $KEY_FILE
    else
        print_warning "Using existing key.json"
        KEY_FILE=""
    fi
fi

if [ ! -z "$KEY_FILE" ]; then
    echo "Creating service account key..."
    gcloud iam service-accounts keys create $KEY_FILE \
        --iam-account=$SA_EMAIL
    print_success "Service account key created: $KEY_FILE"
    print_warning "Keep this file secure! Never commit it to version control."
    print_warning "Add key.json to .gitignore"
fi

################################################################################
# Create Cloud Storage Bucket
################################################################################

print_header "Step 4: Cloud Storage Setup"

BUCKET_NAME="${PROJECT_ID}-image-bucket"

if gsutil ls -b gs://$BUCKET_NAME &>/dev/null; then
    print_warning "Bucket already exists: gs://$BUCKET_NAME"
else
    echo "Creating GCS bucket..."
    gsutil mb -p $PROJECT_ID -l $REGION gs://$BUCKET_NAME
    print_success "Bucket created: gs://$BUCKET_NAME"
fi

################################################################################
# Create BigQuery Dataset
################################################################################

print_header "Step 5: BigQuery Dataset Setup"

if bq ls --dataset | grep -w $DATASET_NAME &>/dev/null; then
    print_warning "Dataset already exists: $DATASET_NAME"
else
    echo "Creating BigQuery dataset..."
    bq mk \
        --dataset \
        --location=$REGION \
        --description="Image Classification Dataset" \
        $DATASET_NAME
    print_success "Dataset created: $DATASET_NAME"
fi

################################################################################
# Create BigQuery Table
################################################################################

print_header "Step 6: BigQuery Table Setup"

if bq ls --table_format=json $DATASET_NAME | grep -q $TABLE_NAME; then
    print_warning "Table already exists: $TABLE_NAME"
else
    echo "Creating BigQuery table..."
    
    # Create schema file
    cat > /tmp/schema.json << 'EOF'
[
  {
    "name": "original_text",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Original text extracted from image"
  },
  {
    "name": "locale",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Language locale detected in image"
  },
  {
    "name": "translated_text",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Text translated to Japanese"
  },
  {
    "name": "file_name",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Source image filename"
  },
  {
    "name": "processing_timestamp",
    "type": "TIMESTAMP",
    "mode": "NULLABLE",
    "description": "When the image was processed"
  }
]
EOF

    bq mk \
        --table \
        --schema=/tmp/schema.json \
        ${PROJECT_ID}:${DATASET_NAME}.${TABLE_NAME}
    
    print_success "Table created: $TABLE_NAME"
    rm /tmp/schema.json
fi

################################################################################
# Environment Setup
################################################################################

print_header "Step 7: Local Environment Setup"

# Create .env file
cat > .env << EOF
# Google Cloud Configuration
export GOOGLE_APPLICATION_CREDENTIALS="$(pwd)/key.json"
export PROJECT_ID="$PROJECT_ID"
export BUCKET_NAME="$BUCKET_NAME"
export DATASET_NAME="$DATASET_NAME"
export TABLE_NAME="$TABLE_NAME"
EOF

print_success "Environment configuration saved to .env"
print_warning "Load environment variables with: source .env"

################################################################################
# Python Dependencies
################################################################################

print_header "Step 8: Python Dependencies"

if command -v pip &> /dev/null; then
    echo "Installing Python dependencies..."
    pip install -r requirements.txt --quiet
    print_success "Python dependencies installed"
else
    print_warning "pip not found. Please run: pip install -r requirements.txt"
fi

################################################################################
# Summary
################################################################################

print_header "Setup Complete! 🎉"

echo ""
echo "Configuration Summary:"
echo "  Project ID:        $PROJECT_ID"
echo "  Service Account:   $SA_EMAIL"
echo "  GCS Bucket:        gs://$BUCKET_NAME"
echo "  BigQuery Dataset:  $DATASET_NAME"
echo "  BigQuery Table:    $TABLE_NAME"
echo ""

echo "Next Steps:"
echo "  1. Load environment variables:"
echo "     ${BLUE}source .env${NC}"
echo ""
echo "  2. Upload test images to the bucket:"
echo "     ${BLUE}gsutil cp image.png gs://$BUCKET_NAME/${NC}"
echo ""
echo "  3. Run the analysis script:"
echo "     ${BLUE}python3 app/analyze-images-v2.py \$PROJECT_ID \$BUCKET_NAME${NC}"
echo ""
echo "  4. View results in BigQuery:"
echo "     ${BLUE}bq query --use_legacy_sql=false 'SELECT * FROM \\\`$PROJECT_ID.$DATASET_NAME.$TABLE_NAME\\\`'${NC}"
echo ""

print_success "Setup complete! Happy processing! 🚀"
