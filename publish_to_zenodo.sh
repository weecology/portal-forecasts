#!/bin/bash

# Publish to Zenodo

set -e  # Exit on any error

# Configuration
ZENODO_SANDBOX_URL="https://sandbox.zenodo.org/api"
ZENODO_PRODUCTION_URL="https://zenodo.org/api"

CURRENT_DATE=$(date -I | head -c 10)
ARCHIVE_NAME="portal-forecasts-${CURRENT_DATE}.zip"

# debugenvironment variable
if [ -n "$ZENODOTOKEN" ]; then
    echo "ZENODOTOKEN set"
else
    echo "Error: No Zenodo token found. Please set ZENODOTOKEN environment variable or create /blue/ewhite/hpc_maintenance/zenododeploytoken.txt"
    exit 1
fi

if [ "${ZENODOENV}" = "sandbox" ]; then
    ZENODO_URL=$ZENODO_SANDBOX_URL
    echo "Using Zenodo SANDBOX environment (ZENODOENV=sandbox)"
else
    ZENODO_URL=$ZENODO_PRODUCTION_URL
    echo "Using Zenodo PRODUCTION environment (ZENODOENV!=sandbox)"
fi

echo "Publishing portal-forecasts to Zenodo..."
echo "Date: $CURRENT_DATE"
echo "Archive: $ARCHIVE_NAME"

# Create temporary directory for archiving
TEMP_DIR=$(mktemp -d)
echo "Temporary directory: $TEMP_DIR"

# Function to copy repository into temp dir with exclusions using tar
copy_project_to_temp() {
    echo "Copying repository into temporary directory with exclusions (tar)..."
    mkdir -p "$TEMP_DIR/portal-forecasts"
    tar -cf - \
        --exclude='./.github' --exclude='./.git' --exclude='./.ruff_cache' \
        --exclude='*.zip' --exclude='*.tar.gz' \
        -C . . | tar -xf - -C "$TEMP_DIR/portal-forecasts"
}

# Copy all files except .github directory
echo "Creating archive excluding .github directory..."
copy_project_to_temp

# Create zip archive
cd "$TEMP_DIR"
zip -r "$ARCHIVE_NAME" portal-forecasts/
ARCHIVE_PATH="$TEMP_DIR/$ARCHIVE_NAME"
ARCHIVE_SIZE=$(stat -c%s "$ARCHIVE_PATH" 2>/dev/null || stat -f%z "$ARCHIVE_PATH")
echo "Archive created: $ARCHIVE_PATH (${ARCHIVE_SIZE} bytes)"

# Use existing DOI based on environment
if [ "${ZENODOENV}" = "sandbox" ]; then
    # Sandbox DOI: 10.5072/zenodo.340647
    RECORD_ID="340647"
    echo "Using existing sandbox DOI: 10.5072/zenodo.$RECORD_ID"
else
    # Production DOI: 10.5281/zenodo.10553210
    RECORD_ID="10553210"
    echo "Using existing production DOI: 10.5281/zenodo.$RECORD_ID"
fi

# Get the deposition ID for this record
echo "Retrieving deposition ID for record $RECORD_ID..."
DEPOSITION_RESPONSE=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $ZENODOTOKEN" \
    "$ZENODO_URL/deposit/depositions/$RECORD_ID")

HTTP_STATUS=$(echo "$DEPOSITION_RESPONSE" | tail -n1)
BODY=$(echo "$DEPOSITION_RESPONSE" | sed '$d')

if [ "$HTTP_STATUS" -lt 200 ] || [ "$HTTP_STATUS" -ge 300 ]; then
    echo "Error retrieving deposition (HTTP $HTTP_STATUS): $BODY"
    exit 1
fi

DEPOSITION_ID=$(echo "$BODY" | jq -r '.id // empty')
if [ -z "$DEPOSITION_ID" ]; then
    echo "Error: Deposition ID not found in response. Response: $BODY"
    exit 1
fi

echo "Found deposition ID: $DEPOSITION_ID for record $RECORD_ID"
ACTION="update"

# Prepare metadata
METADATA=$(cat <<EOF
{
    "metadata": {
        "title": "weecology/portal-forecasts: $CURRENT_DATE",
        "upload_type": "dataset",
        "description": "Weekly ecological forecasts for the Portal Project. This dataset contains forecast predictions, model fits, and evaluation metrics for small mammal populations in the Chihuahuan Desert.",
        "creators": [
            {
                "affiliation": "University of Florida",
                "name": "Ethan P. White",
                "orcid": "0000-0001-6728-7745"
            },
            {
                "affiliation": "University of Florida", 
                "name": "Glenda M. Yenni",
                "orcid": "0000-0001-6969-1848"
            },
            {
                "affiliation": "University of Florida",
                "name": "Shawn D. Taylor", 
                "orcid": "0000-0002-6178-6903"
            },
            {
                "affiliation": "University of Florida",
                "name": "Erica M. Christensen",
                "orcid": "0000-0002-5635-2502"
            },
            {
                "affiliation": "University of Florida",
                "name": "Ellen K. Bledsoe",
                "orcid": "0000-0002-3629-7235"
            },
            {
                "affiliation": "University of Florida",
                "name": "Juniper L. Simonis",
                "orcid": "0000-0001-9798-0460"
            },
            {
                "affiliation": "University of Florida",
                "name": "Hao Ye",
                "orcid": "0000-0002-8630-1458"
            },
            {
                "affiliation": "University of Florida",
                "name": "Henry Senyondo",
                "orcid": "0000-0001-7105-5808"
            },
            {
                "affiliation": "University of Florida",
                "name": "S. K. Morgan Ernest",
                "orcid": "0000-0002-6026-8530"
            }
        ],
        "keywords": [
            "ecology",
            "forecasting", 
            "pipeline",
            "continuous analysis"
        ],
        "license": "cc-zero",
        "version": "$CURRENT_DATE",
        "publication_date": "$CURRENT_DATE",
        "related_identifiers": [
            {
                "relation": "isSupplementTo",
                "identifier": "https://github.com/weecology/portal-forecasts/tree/$CURRENT_DATE",
                "resource_type": "software"
            }
        ]
    }
}
EOF
)

# Update deposition metadata
echo "Updating deposition metadata..."
META_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ZENODOTOKEN" \
    "$ZENODO_URL/deposit/depositions/$DEPOSITION_ID" \
    -d "$METADATA")
META_STATUS=$(echo "$META_RESPONSE" | tail -n1)
META_BODY=$(echo "$META_RESPONSE" | sed '$d')
if [ "$META_STATUS" -lt 200 ] || [ "$META_STATUS" -ge 300 ]; then
    echo "Metadata update failed (HTTP $META_STATUS): $META_BODY"
    exit 1
fi

# Upload the archive file
echo "Uploading archive file..."
# Retrieve the bucket URL for large file upload to avoid 413
BUCKET_URL=$(curl -s -H "Authorization: Bearer $ZENODOTOKEN" \
    "$ZENODO_URL/deposit/depositions/$DEPOSITION_ID" | jq -r '.links.bucket // empty')
if [ -z "$BUCKET_URL" ] || [ "$BUCKET_URL" = "null" ]; then
    echo "Error: Could not retrieve bucket URL for deposition $DEPOSITION_ID"
    exit 1
fi

ARCHIVE_BASENAME=$(basename "$ARCHIVE_PATH")
UPLOAD_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
    -H "Authorization: Bearer $ZENODOTOKEN" \
    --upload-file "$ARCHIVE_PATH" \
    "$BUCKET_URL/$ARCHIVE_BASENAME")
UPLOAD_STATUS=$(echo "$UPLOAD_RESPONSE" | tail -n1)
UPLOAD_BODY=$(echo "$UPLOAD_RESPONSE" | sed '$d')
if [ "$UPLOAD_STATUS" -lt 200 ] || [ "$UPLOAD_STATUS" -ge 300 ]; then
    echo "Upload failed (HTTP $UPLOAD_STATUS): $UPLOAD_BODY"
    exit 1
fi
echo "Upload completed via bucket: $BUCKET_URL/$ARCHIVE_BASENAME"

# Update completed - using existing DOI
echo "Updated existing deposition ID: $DEPOSITION_ID"
if [ "${ZENODOENV}" = "sandbox" ]; then
    echo "DOI: 10.5072/zenodo.$RECORD_ID"
    echo "URL: https://sandbox.zenodo.org/record/$RECORD_ID"
else
    echo "DOI: 10.5281/zenodo.$RECORD_ID"
    echo "URL: https://zenodo.org/record/$RECORD_ID"
fi

# Cleanup
echo "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

echo "Zenodo publishing completed successfully!"
echo "Deposition ID: $DEPOSITION_ID"
if [ "${ZENODOENV}" = "sandbox" ]; then
    echo "DOI: 10.5072/zenodo.$RECORD_ID"
else
    echo "DOI: 10.5281/zenodo.$RECORD_ID"
fi
