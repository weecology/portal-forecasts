#!/bin/bash

# Publish to Zenodo

set -e  # Exit on any error

# Configuration
ZENODO_SANDBOX_URL="https://sandbox.zenodo.org/api"
ZENODO_PRODUCTION_URL="https://zenodo.org/api"

CURRENT_DATE=$(date -I | head -c 10)
ARCHIVE_NAME="portal-forecasts-${CURRENT_DATE}.zip"

# Source Zenodo token
# Option 1: From environment variable
if [ -n "$ZENODOTOKEN" ]; then
    echo "Using ZENODOTOKEN from environment"
# Option 2: From token file
elif [ -f "/blue/ewhite/hpc_maintenance/zenododeploytoken.txt" ]; then
    source /blue/ewhite/hpc_maintenance/zenododeploytoken.txt
    echo "Using Zenodo token from file"
else
    echo "Error: No Zenodo token found. Please set ZENODOTOKEN environment variable or create /blue/ewhite/hpc_maintenance/zenododeploytoken.txt"
    exit 1
fi

# Use sandbox for testing, production for real releases
# Set ZENODO_USE_PRODUCTION=true for production releases
if [ "${ZENODO_USE_PRODUCTION:-true}" = "true" ]; then
    ZENODO_URL=$ZENODO_PRODUCTION_URL
    echo "Using Zenodo PRODUCTION environment"
else
    ZENODO_URL=$ZENODO_SANDBOX_URL
    echo "Using Zenodo SANDBOX environment (set ZENODO_USE_PRODUCTION=false for testing)"
fi

echo "Publishing portal-forecasts to Zenodo..."
echo "Date: $CURRENT_DATE"
echo "Archive: $ARCHIVE_NAME"

# Create temporary directory for archiving
TEMP_DIR=$(mktemp -d)
echo "Temporary directory: $TEMP_DIR"

# Copy all files except .github directory
echo "Creating archive excluding .github directory..."
rsync -av --exclude='.github' --exclude='.git' --exclude='.ruff_cache' \
    --exclude='*.zip' --exclude='*.tar.gz' \
    . "$TEMP_DIR/portal-forecasts/"

# Create zip archive
cd "$TEMP_DIR"
zip -r "$ARCHIVE_NAME" portal-forecasts/
ARCHIVE_PATH="$TEMP_DIR/$ARCHIVE_NAME"
ARCHIVE_SIZE=$(stat -c%s "$ARCHIVE_PATH" 2>/dev/null || stat -f%z "$ARCHIVE_PATH")
echo "Archive created: $ARCHIVE_PATH (${ARCHIVE_SIZE} bytes)"

# Check if we need to create a new deposition or update existing
echo "Checking for existing depositions..."

# Get list of existing depositions
EXISTING_DEPOSITIONS=$(curl -s -H "Authorization: Bearer $ZENODOTOKEN" \
    "$ZENODO_URL/deposit/depositions")

# Check if a deposition for this date already exists
EXISTING_ID=$(echo "$EXISTING_DEPOSITIONS" | jq -r --arg date "$CURRENT_DATE" \
    '.[] | select(.metadata.title | contains($date)) | .id' 2>/dev/null || echo "")

if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "null" ]; then
    echo "Found existing deposition ID: $EXISTING_ID"
    DEPOSITION_ID=$EXISTING_ID
    ACTION="update"
else
    echo "Creating new deposition..."
    
    # Create new deposition
    echo "Creating new deposition with token: ${ZENODOTOKEN:0:10}..."
    DEPOSITION_RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $ZENODOTOKEN" \
        "$ZENODO_URL/deposit/depositions" \
        -d '{}')
    
    DEPOSITION_ID=$(echo "$DEPOSITION_RESPONSE" | jq -r '.id')
    echo "Created new deposition ID: $DEPOSITION_ID"
    ACTION="create"
fi

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
curl -s -X PUT \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ZENODOTOKEN" \
    "$ZENODO_URL/deposit/depositions/$DEPOSITION_ID" \
    -d "$METADATA"

# Upload the archive file
echo "Uploading archive file..."
UPLOAD_RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer $ZENODOTOKEN" \
    -F "file=@$ARCHIVE_PATH" \
    "$ZENODO_URL/deposit/depositions/$DEPOSITION_ID/files")

echo "Upload response: $UPLOAD_RESPONSE"

# Publish the deposition (only for new depositions)
if [ "$ACTION" = "create" ]; then
    echo "Publishing deposition..."
    PUBLISH_RESPONSE=$(curl -s -X POST \
        -H "Authorization: Bearer $ZENODOTOKEN" \
        "$ZENODO_URL/deposit/depositions/$DEPOSITION_ID/actions/publish")
    
    echo "Publish response: $PUBLISH_RESPONSE"
    
    # Extract DOI from response
    DOI=$(echo "$PUBLISH_RESPONSE" | jq -r '.doi' 2>/dev/null || echo "DOI not found")
    echo "Published! DOI: $DOI"
    echo "URL: https://zenodo.org/record/$DEPOSITION_ID"
else
    echo "Updated existing deposition ID: $DEPOSITION_ID"
    echo "URL: https://zenodo.org/record/$DEPOSITION_ID"
fi

# Cleanup
echo "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

echo "Zenodo publishing completed successfully!"
echo "Deposition ID: $DEPOSITION_ID"
if [ -n "$DOI" ]; then
    echo "DOI: $DOI"
fi