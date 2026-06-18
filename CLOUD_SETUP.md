# 🚀 Google Cloud Environment Setup Guide

This guide walks you through setting up and running the image OCR & translation pipeline on Google Cloud Platform (GCP).

---

## Prerequisites

- A Google Cloud Project with billing enabled
- `gcloud` CLI installed ([install here](https://cloud.google.com/sdk/docs/install))
- Python 3.8+ installed locally
- Appropriate IAM permissions in your GCP project

---

## Step 1: Set Up Google Cloud Project

### 1.1 Create or Select a Project

```bash
# List existing projects
gcloud projects list

# Create a new project (optional)
gcloud projects create gemini-api-project --name="Gemini API Project"

# Set the current project
gcloud config set project YOUR_PROJECT_ID
export PROJECT_ID=$(gcloud config get-value project)
echo $PROJECT_ID
```

### 1.2 Enable Required APIs

```bash
gcloud services enable \
  vision.googleapis.com \
  translate.googleapis.com \
  bigquery.googleapis.com \
  storage-api.googleapis.com \
  storage.googleapis.com \
  cloudresourcemanager.googleapis.com
```

---

## Step 2: Create a Service Account

### 2.1 Create Service Account

```bash
SERVICE_ACCOUNT_NAME="ml-api-sa"

gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
  --display-name="Machine Learning API Service Account"
```

### 2.2 Grant Required Roles

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataEditor"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/bigquery.user"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/serviceusage.serviceUsageConsumer"
```

### 2.3 Create and Download Service Account Key

```bash
gcloud iam service-accounts keys create key.json \
  --iam-account=${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com

echo "✅ Service account key saved to: key.json"
echo "⚠️  Keep this file secure and never commit it to version control!"
```

---

## Step 3: Set Up Cloud Storage

### 3.1 Create GCS Bucket

```bash
BUCKET_NAME="${PROJECT_ID}-image-bucket"

gsutil mb -p $PROJECT_ID gs://$BUCKET_NAME/

echo "✅ Bucket created: gs://$BUCKET_NAME/"
```

### 3.2 Upload Test Images (Optional)

```bash
# Upload a single image
gsutil cp image.png gs://$BUCKET_NAME/

# Upload all images from a directory
gsutil -m cp -r images/* gs://$BUCKET_NAME/
```

### 3.3 Verify Bucket Contents

```bash
gsutil ls -r gs://$BUCKET_NAME/
```

---

## Step 4: Set Up BigQuery Dataset and Table

### 4.1 Create Dataset

```bash
PROJECT_ID=$(gcloud config get-value project)

bq mk \
  --dataset \
  --location=US \
  --description="Image Classification Dataset" \
  ${PROJECT_ID}:image_classification_dataset
```

### 4.2 Create Table

```bash
bq mk \
  --table \
  ${PROJECT_ID}:image_classification_dataset.image_text_detail \
  schema.json
```

Where `schema.json` contains:

```json
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
```

### 4.3 Verify Table Creation

```bash
bq show --schema --format=prettyjson ${PROJECT_ID}:image_classification_dataset.image_text_detail
```

---

## Step 5: Local Setup & Testing

### 5.1 Configure Environment Variables

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/key.json"
export PROJECT_ID=$(gcloud config get-value project)
export BUCKET_NAME="${PROJECT_ID}-image-bucket"

# Verify
echo $PROJECT_ID
echo $BUCKET_NAME
```

### 5.2 Install Python Dependencies

```bash
pip install -r requirements.txt
```

### 5.3 Test the Script

```bash
python3 app/analyze-images-v2.py $PROJECT_ID $BUCKET_NAME
```

---

## Step 6: Deploy to Cloud Run (Optional)

### 6.1 Create Dockerfile

See `docker/Dockerfile` in the repository.

### 6.2 Build and Push Container Image

```bash
PROJECT_ID=$(gcloud config get-value project)
SERVICE_NAME="gemini-api-processor"

gcloud builds submit --tag gcr.io/$PROJECT_ID/$SERVICE_NAME
```

### 6.3 Deploy to Cloud Run

```bash
gcloud run deploy $SERVICE_NAME \
  --image gcr.io/$PROJECT_ID/$SERVICE_NAME \
  --platform managed \
  --region us-central1 \
  --service-account=${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
  --set-env-vars="PROJECT_ID=$PROJECT_ID,BUCKET_NAME=$BUCKET_NAME"
```

---

## Step 7: Monitor & Troubleshoot

### 7.1 View Cloud Logging

```bash
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=gemini-api-processor" \
  --limit 50 \
  --format json
```

### 7.2 Check BigQuery Results

```bash
bq query --use_legacy_sql=false '
  SELECT * FROM `'${PROJECT_ID}'.image_classification_dataset.image_text_detail`
  ORDER BY processing_timestamp DESC
  LIMIT 10
'
```

### 7.3 Monitor GCS Uploads

```bash
gsutil du -s gs://$BUCKET_NAME/
gsutil ls -Lr gs://$BUCKET_NAME/ | tail -20
```

---

## Cost Optimization Tips

1. **Set up Budget Alerts:**
   ```bash
   gcloud billing budgets create --billing-account=YOUR_BILLING_ACCOUNT_ID
   ```

2. **Use Cloud Storage Lifecycle Rules:**
   ```bash
   gsutil lifecycle set lifecycle.json gs://$BUCKET_NAME/
   ```

3. **Archive Results to Cloud Archive Storage:**
   - Move processed images to `gs-nearline-storage` after processing

4. **Implement Request Batching:**
   - Group multiple images in a single API call when possible

---

## Cleanup (Destroy Resources)

⚠️ **Warning: This will delete all resources**

```bash
# Delete Cloud Run service
gcloud run services delete gemini-api-processor --region us-central1

# Delete GCS bucket
gsutil -m rm -r gs://$BUCKET_NAME

# Delete BigQuery dataset
bq rm -r -d --force image_classification_dataset

# Delete service account
gcloud iam service-accounts delete ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com
```

---

## Troubleshooting

### "GOOGLE_APPLICATION_CREDENTIALS file does not exist"
```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/key.json"
```

### "Permission denied" errors
- Verify service account has all required roles
- Check IAM policy: `gcloud projects get-iam-policy $PROJECT_ID`

### "Quota exceeded" errors
- Check API quotas: `gcloud compute project-info describe --project=$PROJECT_ID`
- Request quota increase in GCP Console

### BigQuery insert errors
- Verify table schema matches data structure
- Check dataset and table exist: `bq ls --datasets` and `bq ls image_classification_dataset`

---

## Additional Resources

- [Google Cloud Vision API Docs](https://cloud.google.com/vision/docs)
- [Google Cloud Translation API Docs](https://cloud.google.com/translate/docs)
- [BigQuery Documentation](https://cloud.google.com/bigquery/docs)
- [Cloud Storage Documentation](https://cloud.google.com/storage/docs)
- [gcloud CLI Reference](https://cloud.google.com/sdk/gcloud)

---

**Last Updated:** 2026-06-18
