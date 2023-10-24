#!/bin/bash

echo "[docker-start-up.sh] Starting"

cat /etc/locale.conf

export PGPASSWORD=$BUCARDO_DB_PASSWORD

bucardo install --batch --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME

# Call check bucardo.json in infinity loop in background
while true; do sleep 10; /bin/bash apply-bucardo-config.sh;   done &

# Call entrypoint and cmd of the postgres docker image
# It is blocking command, so it makes container to run permanently
docker-entrypoint.sh python3 -m http.server 8080