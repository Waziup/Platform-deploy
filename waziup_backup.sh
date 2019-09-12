# this script performs a backup of both mongo and MySQL databases.
# it should be copied on the production server and registered in the crontab:
# crontab -e
# 30 1 * * * /home/ec2-user/waziup_backup.sh

DATE=`date +"%d-%m-%y"`
MONGO_DIR=/mnt/S3/backups/mongobackups/$DATE
MYSQL_FILE=/mnt/S3/backups/mysqlbackups/$DATE.sql
sudo mkdir -p $MONGO_DIR
sudo mongodump --quiet -u admin -p<password> --authenticationDatabase "admin" --out $MONGO_DIR
sudo mysqldump -h 127.0.0.1 -u root -p<password> --all-databases > $MYSQL_FILE

