#!/bin/bash

function runAll() {
	for id in `seq 1 3`;do
		HOST=192.168.10.10${id}
		echo "RUN on $HOST"
		mysql -h${HOST} -uroot -proot -e "$1"
	done
}

case $1 in
"status") runAll "select * from performance_schema.replication_group_members;";;
"gtid") runAll "SELECT @@GTID_EXECUTED;";;
"primary") runAll "SHOW STATUS LIKE 'group_replication_primary_member';";;
"meta") runAll "select instance_name, mysql_server_uuid, addresses from  mysql_innodb_cluster_metadata.instances;";;
*) runAll "$1";;
esac