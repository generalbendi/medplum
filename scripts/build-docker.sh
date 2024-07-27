#!/usr/bin/env sh

# Ensure all necessary environment variables are set
for var in ECR_REPOSITORY AWS_ACCOUNT_ID AWS_REGION DOCKERHUB_REPOSITORY DOCKERHUB_USERNAME DOCKERHUB_TOKEN; do
  value=$(eval echo \$$var)
  if [ -z "$value" ]; then
    echo "$var is missing"
    exit 1
  fi
done

# Fail on error
set -e

# Echo commands
set -x

# Build server tarball
tar \
  --exclude='*.ts' \
  --exclude='*.tsbuildinfo' \
  -czf medplum-server.tar.gz \
  package.json \
  package-lock.json \
  packages/core/package.json \
  packages/core/dist \
  packages/definitions/package.json \
  packages/definitions/dist \
  packages/fhir-router/package.json \
  packages/fhir-router/dist \
  packages/server/package.json \
  packages/server/dist

# Target platforms
PLATFORMS="linux/amd64" # "linux/arm64 linux/arm/v7"

# Docker Hub tags
DOCKERHUB_TAGS="--tag $DOCKERHUB_REPOSITORY:latest"

# AWS ECR repository URL
ECR_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}"

# Build tags for AWS ECR
ECR_TAGS="--tag ${ECR_URL}:latest"

# If this is a release, tag with version
# Release is specified with a "--release" argument
for arg in "$@"; do
  if [ "$arg" = "--release" ]; then
    VERSION=$(node -p "require('./package.json').version")
    DOCKERHUB_TAGS="$DOCKERHUB_TAGS --tag $DOCKERHUB_REPOSITORY:$VERSION"
    ECR_TAGS="$ECR_TAGS --tag ${ECR_URL}:$VERSION"
    break
  fi
done

# Function to check Docker login status
is_logged_in() {
  registry="$1"
  docker info --format '{{json .AuthConfig}}' | jq -r ".auths[\"${registry}\"].auth" | grep -qv null
}

# Docker Hub login
if ! is_logged_in "https://index.docker.io/v1/"; then
  echo "${DOCKERHUB_TOKEN}" | docker login --username "${DOCKERHUB_USERNAME}" --password-stdin
else
  echo "Already logged in to Docker Hub."
fi

# AWS ECR login
if ! is_logged_in "${ECR_URL}"; then
  aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${ECR_URL}"
else
  echo "Already logged in to AWS ECR."
fi

# Build and push Docker images
docker buildx build --platform "$PLATFORMS" --tag "$DOCKERHUB_REPOSITORY:latest" --tag "$ECR_URL:latest" --push .
