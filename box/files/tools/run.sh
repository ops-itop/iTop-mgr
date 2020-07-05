#!/bin/bash

function runAll() {
	for id in `seq 1 3`;do
		HOST=192.168.10.10${id}
		echo "RUN on $HOST"
		mysql -h${HOST} -uroot -proot -e "$1"
	done
}

runAll "$1"