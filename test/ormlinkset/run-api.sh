#!/bin/bash

for id in `seq 1 10`;do echo $id;done |parallel -j 3 ./ormlinkset.sh admin http://192.168.10.101 &
for id in `seq 1 10`;do echo $id;done |parallel -j 3 ./ormlinkset.sh admin http://192.168.10.102 &
for id in `seq 1 10`;do echo $id;done |parallel -j 3 ./ormlinkset.sh admin http://192.168.10.103 &