#!/usr/bin/env sh

# CI/CD deploy script
# This script should only be called from the CI/CD server.
# Assumes that current working directory is project root.
# Inspects files changed in the most recent commit
# and deploys the appropriate service

# Echo commands
set -x

COMMIT_MESSAGE=$(git log -1 --pretty=%B)
echo "$COMMIT_MESSAGE"

FILES_CHANGED=$(git diff --name-only HEAD HEAD~1)
echo "$FILES_CHANGED"

DEPLOY_APP=true
DEPLOY_GRAPHIQL=true
DEPLOY_SERVER=true

#
# Inspect files changed
#

if echo "$FILES_CHANGED" | grep -q 'build.yml'; then
  DEPLOY_SERVER=true
fi

if echo "$FILES_CHANGED" | grep -q 'Dockerfile'; then
  DEPLOY_SERVER=true
fi

if echo "$FILES_CHANGED" | grep -q 'cicd-deploy.sh'; then
  DEPLOY_APP=true
  DEPLOY_GRAPHIQL=true
  DEPLOY_SERVER=true
fi

if echo "$FILES_CHANGED" | grep -q 'deploy-introspection-schema.sh'; then
  DEPLOY_GRAPHIQL=true
fi

if echo "$FILES_CHANGED" | grep -q 'packages/app'; then
  DEPLOY_APP=true
fi

if echo "$FILES_CHANGED" | grep -q 'packages/core'; then
  DEPLOY_APP=true
  DEPLOY_SERVER=true
fi

if echo "$FILES_CHANGED" | grep -q 'packages/definitions'; then
  DEPLOY_APP=true
  DEPLOY_SERVER=true
fi

if echo "$FILES_CHANGED" | grep -q 'packages/fhir-router'; then
  DEPLOY_SERVER=true
fi

if echo "$FILES_CHANGED" | grep -q 'packages/fhirtypes'; then
  DEPLOY_APP=true
  DEPLOY_SERVER=true
fi

if echo "$FILES_CHANGED" | grep -q 'packages/graphiql'; then
  DEPLOY_GRAPHIQL=true
fi

if echo "$FILES_CHANGED" | grep -q 'packages/server'; then
  DEPLOY_SERVER=true
fi

if echo "$FILES_CHANGED" | grep -q 'packages/react'; then
  DEPLOY_APP=true
fi

#
# Send a slack message
#

ESCAPED_COMMIT_MESSAGE=$(echo "$COMMIT_MESSAGE" | sed 's/"/\\"/g')

PAYLOAD=$(
  cat <<-EOM
{
  "text": "Deploying ${ESCAPED_COMMIT_MESSAGE}",
  "blocks": [
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "Deploying ${ESCAPED_COMMIT_MESSAGE}\\n\\n* Deploy app: ${DEPLOY_APP}\\n* Deploy graphiql: ${DEPLOY_GRAPHIQL}\\n* Deploy server: ${DEPLOY_SERVER}"
      }
    }
  ]
}
EOM
)

curl -X POST -H 'Content-type: application/json' --data "$PAYLOAD" "$SLACK_WEBHOOK_URL"

#
# Run the appropriate deploy scripts
#

if [ "$DEPLOY_APP" = true ]; then
  echo "Deploy app"
  npm run build -- --force --filter=@medplum/app
  . ./scripts/deploy-app.sh
fi

if [ "$DEPLOY_GRAPHIQL" = true ]; then
  echo "Deploy GraphiQL"
  npm run build -- --force --filter=@medplum/graphiql
  . ./scripts/deploy-graphiql.sh
fi

if [ "$DEPLOY_SERVER" = true ]; then
  echo "Deploy server"
  npm run build -- --force --filter=@medplum/server
  . ./scripts/build-docker.sh
  . ./scripts/deploy-server.sh
fi
