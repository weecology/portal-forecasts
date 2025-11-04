#!/usr/bin/env python3

import os
import sys
import json
import requests
import subprocess
import tempfile
import shutil
import time
from datetime import datetime
from pathlib import Path
from urllib3.util.retry import Retry
from requests.adapters import HTTPAdapter

# Configuration
ZENODO_SANDBOX_URL = "https://sandbox.zenodo.org/api"
ZENODO_PRODUCTION_URL = "https://zenodo.org/api"
SANDBOX_CONCEPT_RECORD_ID = "340647"
PRODUCTION_CONCEPT_RECORD_ID = "10553210"
TEMPDIR = "/orange/ewhite/PortalForecasts/archive_directory"

def load_token():
    """Load ZENODOTOKEN from environment or file based on ZENODOENV"""
    # Check environment variable first
    token = os.environ.get('ZENODOTOKEN')
    if token:
        return token
    
    # Determine token file based on environment
    zenodo_env = os.environ.get('ZENODOENV', 'production')
    token_file = ("/blue/ewhite/hpc_maintenance/zenodosandboxtoken.txt" 
                  if zenodo_env == 'sandbox' 
                  else "/blue/ewhite/hpc_maintenance/githubdeploytoken.txt")
    # Read token from file
    with open(token_file, 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith('ZENODOTOKEN=') and not line.startswith('#'):
                return line.split('=', 1)[1].strip('"')
    
    return None

def load_zenodo_metadata():
    """Load metadata from .zenodo.json file"""
    with open('.zenodo.json', 'r') as f:
        return json.load(f)


def get_latest_published_version(record_id, zenodo_url):
    """Get the latest published version from Zenodo"""
    response = requests.get(f"{zenodo_url}/records/{record_id}")
    if response.status_code == 404 or response.status_code == 410:
        return None
    response.raise_for_status()
    concept_data = response.json()
    latest_link = concept_data.get('links', {}).get('latest')
    if not latest_link:
        return None
    latest_record_id = latest_link.split('/')[-3]
    return int(latest_record_id)

def create_archive():
    """Create the portal-forecasts archive"""
    current_date = datetime.now().strftime("%Y-%m-%d")
    archive_name = f"portal-forecasts-{current_date}.zip"
    temp_dir = TEMPDIR
    os.makedirs(temp_dir, exist_ok=True)
    
    print(f"📦 Creating archive: {archive_name}")
    print(f"📁 Using directory: {temp_dir}")
    archive_path = os.path.join(temp_dir, archive_name)
    
    # Use zip to create archive with exclusions
    cmd = [
        "zip", "-r", archive_path,
        ".",
        "-x", ".git/*", 
        "-x", ".ruff_cache/*",
        "-x", "fits/*forecast*",
        "-x", "forecasts/forecasts_evaluations.csv",
        "-x", "resources/*",
        "-x", "www/*",
        "-x", "tmp/*",
        "-x", "*.log",
        "-x", "forecasts_temp/*"
    ]
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"❌ Archive creation failed: {result.stderr}")
        return None
    
    # Get archive size
    archive_size = os.path.getsize(archive_path)
    print(f"✅ Archive created: {archive_path} ({archive_size} bytes)")
    return archive_path

def test_token_auth(token, zenodo_url):
    """Test token authentication"""
    print("🔍 Testing token authentication...")
    
    headers = {'Authorization': f'Bearer {token}'}
    response = requests.get(f"{zenodo_url}/deposit/depositions", headers=headers)
    print(f"Status Code: {response.status_code}")
    
    if response.status_code == 200:
        print("✅ Token authentication successful")
        return True
    else:
        print(f"❌ Token authentication failed: {response.text}")
        return False

def create_new_version(token, zenodo_url, record_id):
    """Create a new version of existing record"""
    print(f"🔄 Creating new version of record {record_id}...")
    headers = {
        'Content-Type': 'application/json',
        'Authorization': f'Bearer {token}'
    }
    
    response = requests.post(
        f"{zenodo_url}/deposit/depositions/{record_id}/actions/newversion",
        headers=headers
    ) 
    print(f"Status Code: {response.status_code}")
    
    if response.status_code == 201:
        data = response.json()
        deposition_id = data['id']
        print(f"✅ New version created with deposition ID: {deposition_id}")
        return deposition_id, data
    else:
        print(f"❌ Failed to create new version: {response.text}")
        return None, None

def create_new_record(token, zenodo_url, concept_record_id):
    """Create a completely new record (like GitHub integration)"""
    print(f"🆕 Creating new record for concept {concept_record_id}...")
    headers = {
        'Content-Type': 'application/json',
        'Authorization': f'Bearer {token}'
    }
    
    # Create a new empty deposition
    response = requests.post(
        f"{zenodo_url}/deposit/depositions",
        headers=headers,
        json={}  # Empty JSON body creates new deposition
    )
    
    print(f"Status Code: {response.status_code}")
    
    if response.status_code == 201:
        data = response.json()
        deposition_id = data['id']
        conceptrecid = data['conceptrecid']
        print(f"✅ New record created with deposition ID: {deposition_id}")
        print(f"📋 Concept Record ID: {conceptrecid}")
        return deposition_id, data
    else:
        print(f"❌ Failed to create new record: {response.text}")
        return None, None

def update_metadata(token, zenodo_url, deposition_id, version_tag):
    """Update deposition metadata"""
    print("📝 Updating deposition metadata...")
    current_date = datetime.now().strftime("%Y-%m-%d")
    zenodo_metadata = load_zenodo_metadata()
    version = version_tag
    
    # Use creators directly from .zenodo.json (no conversion needed)
    creators = zenodo_metadata.get("creators", [])
    print(f"📋 Using {len(creators)} creators directly from .zenodo.json")
    
    # Convert keywords to subjects format
    subjects = []
    for keyword in zenodo_metadata.get("keywords", []) + ["rodents", "population dynamics", "time series", "ecological forecasting"]:
        subjects.append({"subject": keyword})
    
    metadata = {
        "metadata": {
            "title": f"weecology/portal-forecasts: {version}",
            "upload_type": "dataset",
            "publication_date": current_date,
            "description": "Weekly forecasts for the Portal Project rodent population data. This dataset contains automated forecasts generated using multiple ecological forecasting models for the Portal Project's long-term rodent population study site in Arizona, USA.",
            "creators": creators,
            "access_right": "open",
            "license": zenodo_metadata.get("license", "cc-zero"),
            "subjects": subjects,
            "version": version,
            "notes": "This release contains the latest automated forecasts from the Portal Project forecasting pipeline. The forecasts are generated weekly and include predictions for multiple rodent species at the Portal Project study site. Data includes both abundance and biomass forecasts with associated uncertainty estimates.",
            "related_identifiers": [
                {
                    "identifier": f"https://github.com/weecology/portal-forecasts/tree/{version}",
                    "relation": "isSupplementedBy",
                    "scheme": "url"
                },
                {
                    "identifier": "https://portalproject.weecology.org/",
                    "relation": "isSupplementedBy",
                    "scheme": "url"
                }
            ],
            "communities": [
                {
                    "identifier": "weecology"
                }
            ]
        }
    }
    
    headers = {
        'Content-Type': 'application/json',
        'Authorization': f'Bearer {token}'
    }
    
    response = requests.put(
        f"{zenodo_url}/deposit/depositions/{deposition_id}",
        headers=headers,
        data=json.dumps(metadata)
    )
    
    print(f"Status Code: {response.status_code}")
    if 200 <= response.status_code < 300:
        print("✅ Metadata updated successfully")
        return True
    else:
        print(f"❌ Metadata update failed: {response.text}")
        return False

def clear_existing_files(token, zenodo_url, deposition_id):
    """Clear all existing files from the deposition"""
    print("🗑️ Clearing existing files...")
    headers = {'Authorization': f'Bearer {token}'}
    
    # Get list of existing files
    response = requests.get(f"{zenodo_url}/deposit/depositions/{deposition_id}/files", headers=headers)
    response.raise_for_status()
    files = response.json()
    
    if not files:
        print("✅ No existing files to clear")
        return True
 
    print(f"📋 Found {len(files)} existing files to clear")
    # Delete each file
    for file_info in files:
        file_id = file_info['id']
        filename = file_info['filename']
        print(f"🗑️ Deleting file: {filename}")
        
        delete_response = requests.delete(
            f"{zenodo_url}/deposit/depositions/{deposition_id}/files/{file_id}",
            headers=headers
        )
        
        if delete_response.status_code == 204:
            print(f"✅ Deleted: {filename}")
        else:
            print(f"❌ Failed to delete {filename}: {delete_response.status_code} - {delete_response.text}")
            return False
    
    print("✅ All existing files cleared successfully")
    return True

def upload_file(token, zenodo_url, deposition_id, archive_path):
    """Upload archive file using bucket API with retry logic"""
    print("📤 Uploading archive file...")
    
    headers = {'Authorization': f'Bearer {token}'}
    response = requests.get(f"{zenodo_url}/deposit/depositions/{deposition_id}", headers=headers)
    response.raise_for_status()
    bucket_url = response.json()['links']['bucket']
    
    if not bucket_url:
        print("❌ No bucket URL found")
        return False
    
    upload_url = f"{bucket_url}/{os.path.basename(archive_path)}"
    
    session = requests.Session()
    retry_strategy = Retry(
        total=5,
        backoff_factor=2,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["PUT"]
    )
    session.mount("https://", HTTPAdapter(max_retries=retry_strategy))
    
    attempt = 0
    max_attempts = 3
    
    while attempt < max_attempts:
        attempt += 1
        try:
            with open(archive_path, 'rb') as f:
                response = session.put(
                    upload_url,
                    data=f,
                    headers=headers,
                    timeout=(30, 3600),
                    stream=False
                )
            
            if 200 <= response.status_code < 300:
                print(f"✅ Upload completed")
                return True
            
            print(f"❌ Upload failed with status {response.status_code}")
            
        except requests.exceptions.SSLError:
            print(f"❌ SSL Error on attempt {attempt}/{max_attempts}")
        except requests.exceptions.RequestException as e:
            print(f"❌ Request error: {e}")
        
        if attempt < max_attempts:
            wait_time = 2 ** attempt
            time.sleep(wait_time)
    
    return False

def publish_deposition(token, zenodo_url, deposition_id):
    """Publish the deposition"""
    print("🚀 Publishing deposition...")
    
    headers = {'Authorization': f'Bearer {token}'}
    response = requests.post(
        f"{zenodo_url}/deposit/depositions/{deposition_id}/actions/publish",
        headers=headers
    )
    
    print(f"Status Code: {response.status_code}")
    if 200 <= response.status_code < 300:
        data = response.json()
        new_record_id = data.get('id', deposition_id)
        print(f"✅ Published successfully!")
        print(f"🆔 New Record ID: {new_record_id}")
        return new_record_id, data
    else:
        print(f"❌ Publish failed: {response.text}")
        return None, None

def main():
    """Main function"""
    print("🚀 Portal Forecasts Zenodo Publisher")
    print("=" * 35)
    
    # Get version tag from command line arguments
    if len(sys.argv) < 2:
        print("❌ Error: Version tag is required")
        print("Usage: python3 publish_to_zenodo.py <version_tag>")
        sys.exit(1)
    
    version_tag = sys.argv[1]
    
    # Load token
    token = load_token()
    if not token:
        sys.exit(1)
    
    # Determine environment
    zenodo_env = os.environ.get('ZENODOENV', 'production')
    if zenodo_env == 'sandbox':
        zenodo_url = ZENODO_SANDBOX_URL
        concept_record_id = SANDBOX_CONCEPT_RECORD_ID
        print("🔬 Using Zenodo SANDBOX environment")
    else:
        zenodo_url = ZENODO_PRODUCTION_URL
        concept_record_id = PRODUCTION_CONCEPT_RECORD_ID
        print("🌐 Using Zenodo PRODUCTION environment")
    
    print(f"📝 Version tag to publish: {version_tag}")
    
    # Get latest record ID for creating new version
    latest_record_id = None
    print(f"🔍 Getting latest record ID from concept record {concept_record_id}...")
    latest_record_id = get_latest_published_version(concept_record_id, zenodo_url)
    
    # Determine mode: production always uses new version, sandbox uses new record if no latest_record_id
    if latest_record_id:
        print(f"✅ Using latest record ID: {latest_record_id}")
        use_new_record = False
        mode = "New Version (Manual style)"
    elif zenodo_env == 'sandbox':
        print("⚠️  Could not get latest record ID, will create new record instead")
        use_new_record = True
        mode = "New Record (GitHub style)"
    else:
        print("❌ Could not get latest record ID")
        sys.exit(1)
    
    print(f"🔄 Publishing mode: {mode}")
    
    # Test token authentication
    if not test_token_auth(token, zenodo_url):
        sys.exit(1)
    
    # Create archive
    archive_path = create_archive()
    if not archive_path:
        sys.exit(1)
    
    # Create new version or new record based on mode
    if use_new_record:
        # GitHub style: Create completely new record
        deposition_id, deposition_data = create_new_record(token, zenodo_url, concept_record_id)
    else:
        # Manual style: Create new version of existing record
        deposition_id, deposition_data = create_new_version(token, zenodo_url, latest_record_id)
    
    if not deposition_id:
        sys.exit(1)
    
    # Update metadata
    if not update_metadata(token, zenodo_url, deposition_id, version_tag):
        sys.exit(1)
    
    # Clear existing files (only needed for new version approach)
    if not use_new_record:
        clear_existing_files(token, zenodo_url, deposition_id)
    
    # Upload file
    if not upload_file(token, zenodo_url, deposition_id, archive_path):
        sys.exit(1)

    # Publish
    new_record_id, publish_data = publish_deposition(token, zenodo_url, deposition_id)
    if not new_record_id:
        sys.exit(1)
    
    # Print final results
    print("\n" + "=" * 50)
    print("🎉 Publishing completed successfully!")
    print(f"🆔 Deposition ID: {deposition_id}")
    print(f"🆔 New Record ID: {new_record_id}")
    
    if zenodo_env == 'sandbox':
        print(f"🔗 DOI: 10.5072/zenodo.{new_record_id}")
        print(f"🌐 URL: https://sandbox.zenodo.org/record/{new_record_id}")
    else:
        print(f"🔗 DOI: 10.5281/zenodo.{new_record_id}")
        print(f"🌐 URL: https://zenodo.org/record/{new_record_id}")
    
    # Exit with success code
    sys.exit(0)

if __name__ == "__main__":
    main()
