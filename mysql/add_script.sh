#!/bin/bash -e

if [ -z "$1" ]
then
      echo "run: ./add_script.sh container_name_id"
      exit 1
fi

container=$1
echo "Set tls enription for $container" 
cp ./mysql/run_rsa.sh ~/.prod-db
# 7de0c455a7e1
docker exec $container chmod 766 /var/lib/mysql/run_rsa.sh
docker exec $container ./var/lib/mysql/run_rsa.sh
