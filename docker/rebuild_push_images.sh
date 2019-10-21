#!/bin/bash
# Rebuild all images and push to Docker Hub
set -e -u -o pipefail

VERSIONS="9.6 10 11 12"

if [[ ! -z ${1+x} ]]; then
  VERSIONS="$1"
fi

# support of CI secrets (login & password for Docker Hub registry)
if [[ ! -z ${DOCKER_LOGIN+x} ]] && [[ ! -z ${DOCKER_PASSWORD+x} ]]; then
  docker login --username "${DOCKER_LOGIN}" --password "${DOCKER_PASSWORD}"
else
  # you must be loged in with Docker Desktop
  docker login
fi

for version in $VERSIONS; do
  docker build \
  --build-arg "PG_SERVER_VERSION=${version}" \
  -t "postgresmen/postgres-nancy:${version}" .
  
  docker push "postgresmen/postgres-nancy:${version}"
done


