
WAZIUP Proxy
============

This proxy is the entry point to the waziup platform in a Cloud configuration.
It handles the routing of traffic to internal components (api, keycloak, dashboard).

Usage
-----

The proxy is intended to be run as a docker container in a Cloud.
To create the container:
```
docker build -t waziup/proxy .
docker push waziup/proxy
```


