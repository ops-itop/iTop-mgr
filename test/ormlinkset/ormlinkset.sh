#!/bin/bash

[ $# -lt 2 ] && echo "$0 password url" && exit 1
user=admin
password=$1
url=$2
json_data='{"operation":"core/update","comment":"test mgr","class":"Person","key":"SELECT Person WHERE name=\"Xing\" AND first_name=\"Ming\"","output_fields":"id,team_list,friendlyname","fields":{"team_list":[{"team_id":{"name":"Helpdesk"}}]}}'

curl -s "$url/webservices/rest.php?version=1.3" -d "auth_user=$user&auth_pwd=$password&json_data=$json_data" |jq .