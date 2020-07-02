#!/bin/bash

NODE1="192.168.10.101"
NODE2="192.168.10.102"
NODE3="192.168.10.103"
MYIP=`ifconfig eth1 |grep "inet " |awk '{print $2}'`
ID=`echo $MYIP |awk -F'.' '{printf "%s%s", $3,$4}'`
CLUSTER_NAME="itop-mgr"
MYSQL_ROOT="root"
LOCK="/etc/mysql_init.lock"
WEBROOT="/home/wwwroot/default"

systemctl enable mysqld

# 只在第一次执行时初始化
if [ ! -f $LOCK ];then
	rm -fr /var/lib/mysql
	mysqld --initialize-insecure --user=mysql
	systemctl start mysqld
	# (HY000): Can't connect to local MySQL server through socket '/var/lib/mysql/mysql.sock' (2)，重启生成 sock 文件
	systemctl restart mysqld
	systemctl status mysqld
	mysql -uroot -e "show databases;"

	cat > /tmp/init.sql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT' PASSWORD EXPIRE NEVER;
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT';
create user root@'127.0.0.1' identified WITH mysql_native_password BY '$MYSQL_ROOT';
grant all privileges on *.* to root@'127.0.0.1' with grant option;
flush privileges;
EOF
	mysql -uroot < /tmp/init.sql
	touch $LOCK
fi

echo "my.cnf"

cat > /etc/my.cnf <<EOF
[mysqldump]
max_allowed_packet = 64M

[mysqld]
server-id=$ID
innodb_buffer_pool_size = 768M

# Remove leading # to set options mainly useful for reporting servers.
# The server defaults are faster for transactions and fast SELECTs.
# Adjust sizes as needed, experiment to find the optimal values.
# join_buffer_size = 128M
# sort_buffer_size = 2M
# read_rnd_buffer_size = 2M
datadir=/var/lib/mysql
socket=/var/lib/mysql/mysql.sock

# Disabling symbolic-links is recommended to prevent assorted security risks
symbolic-links=0

log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid

# Binary logging and Replication
log_bin = mysql-bin
binlog_format = ROW
binlog_checksum = NONE # or CRC32
master_verify_checksum = OFF # ON if binlog_checksum = CRC32
slave_sql_verify_checksum = OFF # ON if binlog_checksum = CRC32
binlog_cache_size = 1M
binlog_stmt_cache_size = 3M
max_binlog_size = 512M
sync_binlog = 1
expire_logs_days = 7
log_slave_updates = 1
relay_log = mysql-relay-bin
relay_log_purge = 1

# Group Replication parameter
gtid_mode = ON
enforce_gtid_consistency = ON
master_info_repository = TABLE
relay_log_info_repository = TABLE
 
slave_parallel_workers = 10
slave_preserve_commit_order = ON
slave_parallel_type = LOGICAL_CLOCK

#以便在server收集写集合的同时将其记录到二进制日志。写集合基于每行的主键，并且是行更改后的唯一标识此标识将用于检测冲突。
transaction_write_set_extraction = XXHASH64
#组的名字可以随便起,但不能用主机的GTID! 所有节点的这个组名必须保持一致！
loose-group_replication_group_name = "abcdaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" 
##为了避免每次启动自动引导具有相同名称的第二个组,所以设置为OFF。
loose-group_replication_start_on_boot = OFF
loose-group_replication_local_address = "$MYIP:33061"
loose-group_replication_group_seeds = "$NODE1:33061,$NODE2:33061,$NODE3:33061"
#为了避免每次启动自动引导具有相同名称的第二个组,所以设置为OFF。  
loose-group_replication_bootstrap_group = OFF
##关闭单主模式的参数（本例测试时多主模式，所以关闭该项,开启多主模式的参数
loose-group_replication_single_primary_mode = FALSE # = multi-primary
loose-group_replication_enforce_update_everywhere_checks=ON # = multi-primary
report_host=$MYIP
report_port=3306
# 允许加入组复制的客户机来源的ip白名单
#loose-group_replication_ip_whitelist="192.110.0.0/16,127.0.0.1/8"
EOF

systemctl restart mysqld

cat > /tmp/rep.sql <<EOF
SET SQL_LOG_BIN=0;
CREATE USER IF NOT EXISTS repl@'%' IDENTIFIED WITH 'mysql_native_password' BY 'repl';
GRANT SUPER,REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO repl@'%';
FLUSH PRIVILEGES;
SET SQL_LOG_BIN=1;
CHANGE MASTER TO MASTER_USER='repl', MASTER_PASSWORD='repl' FOR CHANNEL 'group_replication_recovery';
EOF

mysql -uroot -p$MYSQL_ROOT < /tmp/rep.sql

# install mgr
cat > /tmp/mgr.sql <<EOF
INSTALL PLUGIN group_replication SONAME 'group_replication.so';
SHOW PLUGINS;
EOF

mysql -uroot -p$MYSQL_ROOT -e "SHOW PLUGINS" |grep -q "group_replication" || mysql -uroot -p$MYSQL_ROOT < /tmp/mgr.sql

# start mgr
cat > /tmp/start.sql <<EOF
SET GLOBAL group_replication_bootstrap_group=ON;
START GROUP_REPLICATION;
SET GLOBAL group_replication_bootstrap_group=OFF;
SELECT * FROM performance_schema.replication_group_members;
EOF

# only run on first node.
[ "$ID"x == "10101"x ] && mysql -uroot -p$MYSQL_ROOT < /tmp/start.sql

# join
cat > /tmp/join.sql <<EOF
SELECT * FROM performance_schema.replication_group_members;
show global variables like '%seed%';
START GROUP_REPLICATION;
SELECT * FROM performance_schema.replication_group_members;
SHOW STATUS LIKE 'group_replication_primary_member';
show global variables like 'group_replication_single%';
EOF

# run on other two node
[ "$ID"x == "10101"x ] || mysql -uroot -p$MYSQL_ROOT < /tmp/join.sql

# fix nginx server_name
sed -i "s/__SERVER_NAME__/$MYIP/g" /etc/nginx/nginx.conf
# fix app_root_url
PHP_CONF="/etc/php-fpm.d/www.conf"
grep -q "ITOP_URL" $PHP_CONF || echo "env[ITOP_URL]=http://$MYIP/" >> $PHP_CONF

# ensure web dir permission
chown -R nginx:nginx $WEBROOT

# rsync itop dir. base 192.168.10.101
if [ "$ID"x == "10101"x ];then
	cat > /etc/rsyncd.conf <<EOF
uid = nginx
gid = nginx
hosts allow = 192.168.10.102 192.168.10.103
address = 192.168.10.101
[itop]
	readonly = true
	path = $WEBROOT
	comment = itop sync
	exclude = data/cache-production/* data/transactions/*
EOF
	systemctl enable rsyncd
	systemctl restart rsyncd
else
	grep -q "rsync.*itop" /etc/crontab || echo "* * * * * root rsync -avzP 192.168.10.101::itop $WEBROOT &>/tmp/itop-sync.log" >> /etc/crontab
fi

# php.ini
PHP_INI=/etc/php.ini
sed -i -r 's/^display_errors =.*/display_errors = On/g' $PHP_INI
sed -i -r 's/^;error_log =.*/error_log = \/tmp\/php_errors.log/g' $PHP_INI

systemctl restart nginx
systemctl restart php-fpm


# usefull script
cat > /root/run.sh <<"EOF"
#!/bin/bash

function runAll() {
	for id in `seq 1 3`;do
		mysql -uroot -proot -e "$1"
	done
}

runAll "$1"
EOF

# auto install(only install one instance: 192.168.10.101)
ITOP_CONF_FILE="$WEBROOT/conf/production/config-itop.php"
if [ ! -f $ITOP_CONF_FILE && "$ID"x == "10101"x ];then
	cd $WEBROOT/toolkit
	php auto_install.php
	sed -i 's/__ITOP_URL__/getenv("ITOP_URL")/g' $ITOP_CONF_FILE
fi