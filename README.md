# Platform-deploy

This repo contains manifests to deploy the Waziup platform on Amazon ECS and Kubernetes.
It also contains proxies for routing trafic to the Platform.


Database security
-----------------

mongoDB must be started with auth in order to avoid any hacking.
https://docs.mongodb.com/manual/tutorial/enable-authentication/

As explained in the link above, first start the DB without auth. Then add admin users:
```
use admin;
db.createUser(
  {
    user: "admin",
    pwd: "xxxxx",
    roles: [ { role: "userAdminAnyDatabase", db: "admin" }, "readWriteAnyDatabase", "restore" ]
  }
)

use waziup;
db.createUser({user: "admin", pwd: "xxxx", roles: [{role: "dbOwner", db: "waziup"}]});
```

After this is done, restart the DB with auth. You can now connect to the DB with auth:
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

A backup can be restored this way:
```
mongorestore -u admin -p <password> --authenticationDatabase "admin" /mnt/S3/backups/mongobackups/13-07-19/
mysql -u root -p<password> -h 127.0.0.1 < /mnt/S3/backups/mysqlbackups/13-07-19.sql
```

