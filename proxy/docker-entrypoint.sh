#!/usr/bin/env sh 
envsubst '$$WAZIUP_BASE_URL' < /etc/nginx/conf.d/waziup.conf.template > /etc/nginx/conf.d/waziup.conf
cat /etc/nginx/conf.d/waziup.conf
nginx -g 'daemon off;'
