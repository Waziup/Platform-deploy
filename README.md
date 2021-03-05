# Platform-deploy

This repo contains manifests to deploy the Waziup platform on Amazon ECS and Kubernetes.
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

sudo yum install vim mysql mongodb-org-shell mongodb-org-tools
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
sudo /usr/local/bin/certbot-auto certonly -a webroot -w /etc/letsencrypt/www/_letsencrypt/  --agree-tos --expand --dry-run \
  -d waziup.io \
  -d www.waziup.io \
  -d api.waziup.io \
  -d dashboard.waziup.io \
  -d keycloak.waziup.io \
  -d api.staging.waziup.io \
  -d dashboard.staging.waziup.io \
  -d keycloak.staging.waziup.io \
  -d iot-catalogue.waziup.io \
  -d login.waziup.io \
  -d remote.waziup.io \
  -d diy.waziup.io \
  -d install.waziup.io \
  -d waziup.org \
  -d www.waziup.org \
  -d forum.waziup.io \
  -d downloads.waziup.io
```
Use `--expand` to keep the same certificates and add some domains.
Warning: removing domains will make certbot to create another certificate in a new folder.
Run with `--dry-run` before, in order to make sure that the command is OK.

This will generate the certifications in `/etc/letsencrypt/archive` and link them in `/etc/letsencrypt/live`.
The nginx configuration will then reference the files in `/etc/letsencrypt/live/waziup.io`.


Nginx configuration should also serve the folder `/etc/letsencrypt/www/_letsencrypt` on `http://*.waziup.io/.well-known/acme-challenge/`
```
location /.well-known/acme-challenge/ {
   root /certs/www/_letsencrypt;
}
```
This will allow certbot to renew our certificates regularly.
