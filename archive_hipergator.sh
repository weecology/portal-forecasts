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

# Copy version of portal_weekly_forecast.py used to run the forecast into the repo so we know what was run
cp ../portal_weekly_forecast.sh .
cp ../portal_dryrun_forecast.sh .

# Setup on weecologydeploy user
git config user.email "weecologydeploy@weecology.org"
git config user.name "Weecology Deploy Bot"

# Commit changes to portal-forecasts repo. Do not commit forecasts directory
git checkout main 2>/dev/null || echo "Already on main branch"
git add data/* models/* portal_weekly_forecast.sh portal_dryrun_forecast.sh

git commit -m "Update forecasts: HiperGator Build $current_date [ci skip]"

# Add deploy remote
# Needed to grant permissions through the deploy token
# Removing the remote ensures that updates to the GitHub Token are added to the remote
git remote remove deploy 2>/dev/null || true
git remote add deploy https://${GITHUBTOKEN}@github.com/weecology/portal-forecasts.git

# Create a new portal-forecasts tag for release (only if it doesn't exist)
if ! git tag -l | grep -q "^$current_date$"; then
    git tag $current_date
    echo "Created new tag: $current_date"
else
    echo "Tag $current_date already exists, skipping tag creation"
fi

# Publish large forecast data directly to Zenodo (bypassing GitHub's 1GB limit)
echo "Publishing forecast data to Zenodo..."
python3 publish_to_zenodo.py $current_date --new-record 2>&1 || exit 1

if [ "$ZENODOENV" = "sandbox" ]; then
    echo "Sandbox does not need to push to GitHub"
else
    git push --quiet deploy main
    git push --quiet deploy --tags
fi

echo "Archive process completed successfully!"
echo "Code: https://github.com/weecology/portal-forecasts/releases/tag/$current_date"

