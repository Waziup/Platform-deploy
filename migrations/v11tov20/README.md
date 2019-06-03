WAZIUP Platform migration guide
===============================

This migration guide explains how to transfer data from Waziup Platform V1.1 to V2.0.
All the operations should be performed on the target server.

Import databases
----------------

Import mongo data from old server:
First open the port 27017 on the old server. Close it AS SOON AS FINISHED.

```
mongodump --host 35.157.161.231 --port 27017 --out /var/backups/mongobackups/`date +"%m-%d-%y"`
mongorestore /var/backups/mongobackups/`date +"%m-%d-%y"`
```

Import MySQL data from old server:
First open the port 3306 on the old server. Close it AS SOON AS FINISHED.
```
mysqldump -h 18.197.65.175 -P 3306 -u root -proot_password --all-databases > /var/backups/mysqlbackups/`date +"%m-%d-%y"`
mysql -u root -proot_password -h 127.0.0.1 <  /var/backups/mysqlbackups/`date +"%m-%d-%y"`
```


Migrate datapoints
------------------

Merge all documents in the same collection. First extract the list of collections in db "waziup_history", in a file called collections.txt.
Merge them in the new database:
```
./merge.sh
```

Perform renamings in mongo shell:
- rename entityID -> device_id
- rename attributeID -> sensor_id
- remove SensingDevice

```
use waziup;
db.waziup_history.update({}, {$rename:{"entityID":"device_id", "attributeID":"sensor_id"}, $unset: {"entityType":""}}, false, true);
```

Migrate sensors
---------------

Regarding sensors, the work to do is:
- add the keycloak Id for existing sensors
- rename type SensingDevice -> Device
- rename type Measurement -> Sensor
** TODO: this technique will not preserve date_created and date_modified.

Extract resources:
```
CLIENTTOKEN=`curl -X POST -H "Content-Type: application/x-www-form-urlencoded" -d 'grant_type=client_credentials&client_id=api-server&client_secret=4e9dcb80-efcd-484c-b3d7-1e95a0096ac0' "http://35.157.161.231:8080/auth/realms/waziup/protocol/openid-connect/token" | jq .access_token -r`
curl "http://localhost:8080/auth/realms/waziup/authz/protection/resource_set?deep=true&max=1000" -H "Authorization: Bearer $CLIENTTOKEN" -H "Content-Type: application/json" -v > resources.json
```

Extract sensors:
```
curl http://localhost:1026/v2/entities?limit=1000 -s -S --header 'Fiware-Service:waziup' | jq "" > devices.json
```

Find/replace the types in devices.json using a text editor.
Now insert the keycloak IDs in the JSON:
```
node insert_key.js | jq "" -r > devices2.json
```
You should check that the resulting file has keycloak IDs for all devices.
If everything if OK, inject those devices into Orion:

```
./insert.sh
```



