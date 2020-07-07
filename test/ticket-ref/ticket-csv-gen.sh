#!/bin/bash

echo "'标题','组织->名称','发起人->全称','状态','描述'" > request.csv

for id in `seq 1 100`;do
	echo "'csv-import-test-$id','Demo','Agatha Christie','新建','Test'" >> request.csv
done
