# Archive forecasts by pushing weekly forecasts 
# Push portal-forecast code to GitHub with a weekly tag
# Push portal-forecast code and forecast to Zenodo

current_date=`date -I | head -c 10`

source /blue/ewhite/hpc_maintenance/githubdeploytoken.txt

# Copy version of portal_weekly_forecast.py used to run the forecast into the repo so we know what was run
cp ../portal_weekly_forecast.sh .
cp ../portal_dryrun_forecast.sh .

# Setup on weecologydeploy user
git config user.email "weecologydeploy@weecology.org"
git config user.name "Weecology Deploy Bot"

# Commit changes to portal-forecasts repo. Do not commit forecasts directory
git checkout main
git add data/* models/* portal_weekly_forecast.sh portal_dryrun_forecast.sh

git commit -m "Update forecasts: HiperGator Build $current_date [ci skip]"

# Add deploy remote
# Needed to grant permissions through the deploy token
# Removing the remote ensures that updates to the GitHub Token are added to the remote
git remote remove deploy
git remote add deploy https://${GITHUBTOKEN}@github.com/weecology/portal-forecasts.git

# Create a new portal-forecasts tag for release
git tag $current_date

# If this is a cron event deploy, otherwise just check if we can

# Push updates to upstream
git push --quiet deploy main

# Create a new portal-forecasts release to trigger Zenodo archiving
git push --quiet deploy --tags

# Publish large forecast data directly to Zenodo (bypassing GitHub's 1GB limit)
echo "Publishing forecast data to Zenodo..."

./publish_to_zenodo.sh

echo "Archive process completed successfully!"
echo "Code: https://github.com/weecology/portal-forecasts/releases/tag/$current_date"

