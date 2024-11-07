FROM nginx:alpine

ADD waziup.conf /etc/nginx/conf.d/waziup.conf

ADD nginx.conf /etc/nginx/nginx.conf

ADD letsencrypt.conf /etc/nginx/letsencrypt.conf

# Static website files, externally mounted
VOLUME /var/www/waziup.org
