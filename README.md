# Platform-deploy

This repo contains instructions to deploy the Waziup platform on Amazon ECS.
It also contains proxies for routing trafic to the Platform.

VM install
----------

install some tools:
```
echo '[mongodb-org-4.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/$releasever/mongodb-org/4.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-4.0.asc' \
    | sudo tee /etc/yum.repos.d/mongodb-org-4.0.repo

sudo yum install vim mysql mongodb-org-shell mongodb-org-tools postgresql
```


Database volume
---------------

Databases files should not be hosted on the VM itself, rather on an attached volume.
This avoids to lose all the data should the VM be terminated.
Create a volume, attach it to the VM and mount it to `/data`:
https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSVolumes.html
https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-using-volumes.html

Then change the permissions:
```
sudo chmod 777 * -R
```

Database security
-----------------

mongoDB must be started with auth in order to avoid any hacking.
https://docs.mongodb.com/manual/tutorial/enable-authentication/

Add admin users:
```
use admin;
db.updateUser(
  "admin",
  {
    pwd: "xxxx",
    roles: [ { role: "userAdminAnyDatabase", db: "admin" }, "readWriteAnyDatabase", "restore" ]
  }
);

use waziup;
db.createUser({user: "admin", pwd: "xxx", roles: [{role: "dbOwner", db: "waziup"}]});
```

Connection to DB:
=======
After this is done, restart the DB with auth. You can now connect to the DB with auth:
```
mongo <IP>/waziup --quiet -u admin -p xxx --authenticationDatabase "admin"
```

Restore backups
---------------

Since backups can be big, you should [mount a S3 bucket on Amazon](https://cloudkul.com/blog/mounting-s3-bucket-linux-ec2-instance/).
Add this command to /etc/rc.local:
```
sudo s3fs waziup -o use_cache=/tmp -o allow_other -o uid=1001 -o mp_umask=002 -o multireq_max=5 /mnt/S3
```

A backup can be restored this way:
```
mongorestore -u admin -p <password> --authenticationDatabase "admin" /mnt/S3/backups/mongobackups/13-07-19/
mysql -u root -p<password> -h 127.0.0.1 < /mnt/S3/backups/mysqlbackups/20-07-19.sql
```

Now add the regular backups:
Copy [this script](./waziup_backup.sh) on the production server.
Add it to crontab:
```
crontab -e
30 1 * * * /home/ec2-user/waziup_backup.sh
```

Database debugging:
-------------------

Find devices without a Keycloak ID:
```
curl "http://35.157.161.231:1026/v2/entities?limit=1000&type=Device" -s -S --header 'Fiware-Service:waziup' | jq '.[]  | select(has("keycloak_id") | not) | .id' -r
```

SSL certificates
----------------

Install letsencrypt on the frontend VM:
```
wget https://dl.eff.org/certbot-auto
sudo mv certbot-auto /usr/local/bin/certbot-auto
sudo chown root /usr/local/bin/certbot-auto
sudo chmod 0755 /usr/local/bin/certbot-auto
```
Let it generate the certificates:
```
sudo certbot certonly \
  --cert-name waziup.io \
  -a webroot -w /etc/letsencrypt/www/_letsencrypt/ \
  --agree-tos --expand --dry-run \
  -d waziup.io \
  -d www.waziup.io \
  -d api.waziup.io \
  -d keycloak.waziup.io \
  -d dashboard.waziup.io \
  -d login.waziup.io \
  -d remote.waziup.io \
  -d diy.waziup.io \
  -d install.waziup.io \
  -d waziup.org \
  -d www.waziup.org \
  -d forum.waziup.io \
  -d downloads.waziup.io \
  -d lab.waziup.io \
  -d innotec21.de -d www.innotec21.de \
  -d kijanibox.eu -d www.kijanibox.eu \
  -d kijanispace.eu -d www.kijanispace.eu

```
Use `--expand` to keep the same certificates and add some domains.
Warning: removing domains will make certbot to create another certificate in a new folder.
Run with `--dry-run` before, in order to make sure that the command is OK.

This will generate the certifications in `/etc/letsencrypt/archive` and create links in `/etc/letsencrypt/live`.
A renew file will also be created in `/etc/letsencrypt/renew`.

The Nginx proxy will then use the certificates in order to add the HTTPS capacity: https://github.com/Waziup/Platform-deploy/blob/master/proxy-frontend/waziup.conf#L10.


In order to let `certbot` renew the certificates automatically, we should also serve a particular letsencrypt folder on our proxy: https://github.com/Waziup/Platform-deploy/blob/master/proxy-frontend/letsencrypt.conf. This will allow `certbot` to verify that the domain is ours before renewing the certificates. 
Place this script in `/etc/cron.weekly`:
```
#!/bin/sh
{
date
certbot renew --post-hook "docker stop $(docker ps -q --filter ancestor=waziup/proxy-frontend:2.6)"
} &>> /home/ec2-user/cert-renew.log
```
This will attempt to renew the certificates weekly. In case of renewal, it reboots the proxy container so that the new certificates are taken into account.

VPN
---

OpenVPN runs on the front-end VM. It allows to connect the staging server and possibly WaziGates.

To install it, follow the instructions at:
https://github.com/angristan/openvpn-install

Use the default answer to all questions.
This will produce a "ovpn" file for the first client. This file can be used to configure a client.
On an Ubuntu machine, Go in the Networks Setting, VPN section and enter the file.
The Client machine should connect automatically.
You can reissue the command `openvpn-install` to get more client ovpn files.
