How to build/rebuild:

Rebuild and push images for all postgres versions:
```bash
./rebuild_push_images.sh
```

Or do it manually:
```bash
export NANCY_DOCKER_PG_VERSION=9.6

docker build \
  --build-arg "PG_SERVER_VERSION=${NANCY_DOCKER_PG_VERSION}" \
  -t "postgresmen/postgres-nancy:${NANCY_DOCKER_PG_VERSION}" .

docker login # you must be registered, go to hub.docker.com

docker push "postgresmen/postgres-nancy:${NANCY_DOCKER_PG_VERSION}"
```
