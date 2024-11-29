FROM nginx:alpine

ADD waziup.conf innotec21.conf kijanibox.conf kijanispace.conf wordpress.conf /etc/nginx/conf.d/

ADD nginx.conf /etc/nginx/nginx.conf

ADD letsencrypt.conf /etc/nginx/letsencrypt.conf

# Static website files, externally mounted
VOLUME /var/www/waziup.org
