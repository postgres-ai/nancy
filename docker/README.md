How to build/rebuild:

```bash
docker build --build-arg PG_SERVER_VERSION=9.6 -t postgresmen/postgres-with-stuff:pg9.6 .
docker login # you must be registered, go to hub.docker.com
docker push postgresmen/postgres-with-stuff:pg9.6
```
