#!/usr/bin/env python3

import os
import sys
import json
import requests
import subprocess
import tempfile
import shutil
from datetime import datetime
from pathlib import Path

# Configuration
ZENODO_SANDBOX_URL = "https://sandbox.zenodo.org/api"
ZENODO_PRODUCTION_URL = "https://zenodo.org/api"
SANDBOX_CONCEPT_RECORD_ID = "340647"
PRODUCTION_CONCEPT_RECORD_ID = "10553210"

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
    # Read token from file later try source()
    try:
        with open(token_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line.startswith('ZENODOTOKEN=') and not line.startswith('#'):
                    return line.split('=', 1)[1].strip('"')
    except FileNotFoundError:
        pass
    except Exception as e:
        print(f"❌ Error reading token file: {e}")
    
    return None

def get_latest_published_version(record_id, sandbox=False):
    """Get the latest published version from Zenodo"""
    base_url = ZENODO_SANDBOX_URL if sandbox else ZENODO_PRODUCTION_URL
    
    try:
        # Get the record
        response = requests.get(f"{base_url}/records/{record_id}")
        response.raise_for_status()
        record_data = response.json()
        
        # Get the concept record (latest version)
        conceptrecid = record_data['conceptrecid']
        response = requests.get(f"{base_url}/records/{conceptrecid}")
        response.raise_for_status()
        latest_data = response.json()
        
        return latest_data['id']
    except Exception as e:
        print(f"❌ Error getting latest version: {e}")
        return None

def create_archive():
    """Create the portal-forecasts archive"""
    current_date = datetime.now().strftime("%Y-%m-%d")
    archive_name = f"portal-forecasts-{current_date}.zip"
    temp_dir = "/orange/ewhite/PortalForecasts/archive_directory"
    os.makedirs(temp_dir, exist_ok=True)
    
    print(f"📦 Creating archive: {archive_name}")
    print(f"📁 Using directory: {temp_dir}")
    archive_path = os.path.join(temp_dir, archive_name)
    
    try:
        # Use tar to create archive with exclusions
        cmd = [
            "tar", "-czf", archive_path,
            "--exclude=./.github",
            "--exclude=./.git", 
            "--exclude=./.ruff_cache",
            "--exclude=*.zip",
            "--exclude=*.tar.gz",
            "--exclude=./resources",
            "--exclude=./www",
            "--exclude=./tmp",
            "--exclude=*.log",
            "--exclude=forecasts_temp",
            "."
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"❌ Archive creation failed: {result.stderr}")
            return None
        
        # Get archive size
        archive_size = os.path.getsize(archive_path)
        print(f"✅ Archive created: {archive_path} ({archive_size} bytes)")
        return archive_path
        
    except Exception as e:
        print(f"❌ Error creating archive: {e}")
        return None

def test_token_auth(token, zenodo_url):
    """Test token authentication"""
    print("🔍 Testing token authentication...")
    
    headers = {'Authorization': f'Bearer {token}'}
    try:
        response = requests.get(f"{zenodo_url}/deposit/depositions", headers=headers)
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            print("✅ Token authentication successful")
            return True
        else:
            print(f"❌ Token authentication failed: {response.text}")
            return False
    except Exception as e:
        print(f"❌ Authentication test failed: {e}")
        return False

def create_new_version(token, zenodo_url, record_id):
    """Create a new version of existing record"""
    print(f"🔄 Creating new version of record {record_id}...")
    headers = {
        'Content-Type': 'application/json',
        'Authorization': f'Bearer {token}'
    }
    
    try:
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
            
    except Exception as e:
        print(f"❌ Error creating new version: {e}")
        return None, None

def update_metadata(token, zenodo_url, deposition_id):
    """Update deposition metadata"""
    print("📝 Updating deposition metadata...")
    
    metadata = {
        "metadata": {
            "title": "Portal Forecasts",
            "upload_type": "dataset",
            "description": "Weekly forecasts for the Portal Project rodent population data",
            "creators": [
                {
                    "name": "Weecology",
                    "affiliation": "University of Florida"
                }
            ],
            "access_right": "open",
            "license": "CC-BY-4.0",
            "keywords": ["ecology", "forecasting", "rodents", "population dynamics"]
        }
    }
    
    headers = {
        'Content-Type': 'application/json',
        'Authorization': f'Bearer {token}'
    }
    
    try:
        response = requests.put(
            f"{zenodo_url}/deposit/depositions/{deposition_id}",
            headers=headers,
            data=json.dumps(metadata)
        )
        
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            print("✅ Metadata updated successfully")
            return True
        else:
            print(f"❌ Metadata update failed: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ Error updating metadata: {e}")
        return False

def upload_file(token, zenodo_url, deposition_id, archive_path):
    """Upload archive file using bucket API"""
    print("📤 Uploading archive file...")
    # Get bucket URL
    headers = {'Authorization': f'Bearer {token}'}
    try:
        response = requests.get(f"{zenodo_url}/deposit/depositions/{deposition_id}", headers=headers)
        response.raise_for_status()
        data = response.json()
        bucket_url = data['links']['bucket']
        if not bucket_url:
            print("❌ No bucket URL found")
            return False
    except Exception as e:
        print(f"❌ Error getting bucket URL: {e}")
        return False
    
    # Upload file to bucket
    archive_basename = os.path.basename(archive_path)
    upload_url = f"{bucket_url}/{archive_basename}"
    
    try:
        with open(archive_path, 'rb') as f:
            response = requests.put(upload_url, data=f, headers=headers)
        
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            print(f"✅ Upload completed: {upload_url}")
            return True
        else:
            print(f"❌ Upload failed: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ Error uploading file: {e}")
        return False

def publish_deposition(token, zenodo_url, deposition_id):
    """Publish the deposition"""
    print("🚀 Publishing deposition...")
    
    headers = {'Authorization': f'Bearer {token}'}
    try:
        response = requests.post(
            f"{zenodo_url}/deposit/depositions/{deposition_id}/actions/publish",
            headers=headers
        )
        
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 202:
            data = response.json()
            new_record_id = data.get('id', deposition_id)
            print(f"✅ Published successfully!")
            print(f"🆔 New Record ID: {new_record_id}")
            return new_record_id, data
        else:
            print(f"❌ Publish failed: {response.text}")
            return None, None
            
    except Exception as e:
        print(f"❌ Error publishing: {e}")
        return None, None

def main():
    """Main function"""
    print("🚀 Portal Forecasts Zenodo Publisher")
    print("=" * 35)
    
    # Load token
    token = load_token()
    if not token:
        sys.exit(1)
    
    # Determine environment
    zenodo_env = os.environ.get('ZENODOENV', 'production')
    if zenodo_env == 'sandbox':
        zenodo_url = ZENODO_SANDBOX_URL
        record_id = SANDBOX_CONCEPT_RECORD_ID
        print("🔬 Using Zenodo SANDBOX environment")
    else:
        zenodo_url = ZENODO_PRODUCTION_URL
        print("🌐 Using Zenodo PRODUCTION environment")
        
        # Get latest record ID for production
        print(f"🔍 Getting latest record ID from concept record {PRODUCTION_CONCEPT_RECORD_ID}...")
        latest_record_id = get_latest_published_version(PRODUCTION_CONCEPT_RECORD_ID, sandbox=False)
        if not latest_record_id:
            print("❌ Could not get latest record ID")
            sys.exit(1)
        record_id = latest_record_id
        print(f"✅ Using latest production record ID: {record_id}")
    
    # Test token authentication
    if not test_token_auth(token, zenodo_url):
        sys.exit(1)
    
    # Create archive
    archive_path = create_archive()
    if not archive_path:
        sys.exit(1)
    
    # Create new version
    deposition_id, deposition_data = create_new_version(token, zenodo_url, record_id)
    if not deposition_id:
        sys.exit(1)
    
    # Update metadata
    if not update_metadata(token, zenodo_url, deposition_id):
        sys.exit(1)
    
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

if __name__ == "__main__":
    main()
