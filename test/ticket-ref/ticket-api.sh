#!/bin/bash

[ $# -lt 2 ] && echo "$0 password url" && exit 1
user=admin
password=$1
url=$2
json_data='{"operation":"core/create","comment":"test mgr","class":"UserRequest","output_fields":"id,friendlyname","fields":{"org_id":"SELECT Organization WHERE name = \"Demo\"","caller_id":{"name":"Christie", "first_name":"Agatha"},"title":"Test MGR From API", "description":"Test"}}'

curl -s "$url/webservices/rest.php?version=1.3" -d "auth_user=$user&auth_pwd=$password&json_data=$json_data" |jq .