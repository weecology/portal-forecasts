# Archive forecasts by pushing weekly forecasts 
# Push portal-forecast code to GitHub with a weekly tag
# Push portal-forecast code and forecast to Zenodo

current_date=`date -I | head -c 10`

# Source the appropriate token based on environment variable
if [ "$ZENODOENV" = "sandbox" ]; then
    echo "Using Zenodo sandbox environment"
    source /blue/ewhite/hpc_maintenance/zenodosandboxtoken.txt
    # Verify ZENODOTOKEN is set and not empty
    if [ -z "$ZENODOTOKEN" ]; then
        echo "Error: ZENODOTOKEN not set after sourcing sandbox token file"
        exit 1
    fi
    echo "ZENODOTOKEN loaded from sandbox token file"
else
    echo "Using Zenodo production environment"
    source /blue/ewhite/hpc_maintenance/githubdeploytoken.txt
    # Verify ZENODOTOKEN is set and not empty
    if [ -z "$ZENODOTOKEN" ]; then
        echo "Error: ZENODOTOKEN not set after sourcing production token file"
        exit 1
    fi
    echo "ZENODOTOKEN loaded from production token file"
fi

rm -f /orange/ewhite/PortalForecasts/archive_directory/* 2>/dev/null

# Setup on weecologydeploy user
git config user.email "weecologydeploy@weecology.org"
git config user.name "Weecology Deploy Bot"

# Commit changes to portal-forecasts repo. Do not commit forecasts directory
echo "Switching to main branch..."
git checkout main 2>/dev/null || echo "Already on main branch"
echo "Adding files to git..."
git add data/* models/* portal_weekly_forecast.sh portal_dryrun_forecast.sh 2>&1 || exit 1

echo "Committing changes..."
git commit -m "Update forecasts: HiperGator Build $current_date [ci skip]"  2>/dev/null || echo "Nothing committed"

# Add deploy remote
# Needed to grant permissions through the deploy token
# Removing the remote ensures that updates to the GitHub Token are added to the remote
echo "Removing existing deploy remote..."
git remote remove deploy 2>/dev/null || echo "No existing deploy remote to remove"
echo "Adding deploy remote..."
git remote add deploy https://${GITHUBTOKEN}@github.com/weecology/portal-forecasts.git 2>&1 || exit 1

# Create a new portal-forecasts tag for release (only if it doesn't exist)
echo "Checking for existing tags..."
if ! git tag -l | grep -q "^$current_date$"; then
    echo "Creating new tag: $current_date"
    git tag $current_date 2>&1 || exit 1
    echo "Created new tag: $current_date"
else
    echo "Tag $current_date already exists, skipping tag creation"
fi

# Publish large forecast data directly to Zenodo (bypassing GitHub's 1GB limit)
echo "Publishing forecast data to Zenodo..."
if ! python3 publish_to_zenodo.py $current_date 2>&1; then
    echo "ERROR: Failed to publish to Zenodo. Exit code: $?"
    exit 1
fi

if [ "$ZENODOENV" = "sandbox" ]; then
    echo "Sandbox does not need to push to GitHub"
else
    echo "Pushing to GitHub main branch..."
    git push deploy main 2>&1 || exit 1
    echo "Pushing tags to GitHub..."
    git push deploy --tags 2>&1 || exit 1
fi

echo "Archive process completed successfully!"
echo "Code: https://github.com/weecology/portal-forecasts/releases/tag/$current_date"

