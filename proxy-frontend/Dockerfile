FROM nginx:alpine

ADD waziup.conf innotec21.conf kijanibox.conf kijanispace.conf kijanicooling.conf majiup.conf wordpress.conf osirris.conf wazilab.conf porai.conf /etc/nginx/conf.d/

ADD nginx.conf /etc/nginx/nginx.conf

# Static website files, externally mounted
VOLUME /var/www/waziup.org
