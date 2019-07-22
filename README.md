# Platform-deploy

This repo contains manifests to deploy the Waziup platform on Amazon ECS and Kubernetes.
It also contains proxies for routing trafic to the Platform.


Database security
-----------------

mongoDB must be started with auth in order to avoid any hacking.
https://docs.mongodb.com/manual/tutorial/enable-authentication/

Start the mongo container without auth (remove all env variables):

Add admin users (replace xxx with the real password):
```
use admin;
db.createUser(
  {
    user: "admin",
    pwd: "xxxx",
    roles: [ { role: "userAdminAnyDatabase", db: "admin" }, "readWriteAnyDatabase" ]
  }
)

use waziup;
db.createUser({user: "admin", pwd: "xxxx", roles: [{role: "dbOwner", db: "waziup"}]});
```

restart the mongo container with auth.

Connection to DB:
```
mongo <IP>/waziup --quiet -u admin -p xxx --authenticationDatabase "admin"
```


Database debugging:
-------------------

Find devices without a Keycloak ID:
```
curl "http://35.157.161.231:1026/v2/entities?limit=1000&type=Device" -s -S --header 'Fiware-Service:waziup' | jq '.[]  | select(has("keycloak_id") | not) | .id' -r
```

Backups
-------

Copy [this script](./waziup_backup.sh) on the production server.
Add it to crontab:
```
crontab -e
30 1 * * * /home/ec2-user/waziup_backup.sh
```

Since backups can be big, you should [mount a S3 bucket on Amazon](https://cloudkul.com/blog/mounting-s3-bucket-linux-ec2-instance/).
Add this command to /etc/rc.local:
```
sudo s3fs waziup -o use_cache=/tmp -o allow_other -o uid=1001 -o mp_umask=002 -o multireq_max=5 /mnt/S3
```

