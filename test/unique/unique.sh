#!/bin/bash

[ $# -lt 3 ] && echo "$0 password url" && exit 1
user=admin
password=$1
url=$2
json_data='{"operation":"core/create","comment":"test mgr","class":"Person","output_fields":"id,employee_number,friendlyname","fields":{"org_id":"SELECT Organization WHERE name = \"Demo\"","name":"Xing","first_name":"Ming","employee_number":"2020"}}'

curl -s "$url/webservices/rest.php?version=1.3" -d "auth_user=$user&auth_pwd=$password&json_data=$json_data" |jq .