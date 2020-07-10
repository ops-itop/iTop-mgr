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
loose-group_replication_single_primary_mode = OFF # = multi-primary
loose-group_replication_enforce_update_everywhere_checks=ON # = multi-primary
report_host=$MYIP
report_port=3306
# 允许加入组复制的客户机来源的ip白名单
loose-group_replication_ip_whitelist="192.168.10.0/24,127.0.0.1/8"
EOF

systemctl restart mysqld

# 修改root用户密码
cat > /tmp/init.sql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT' PASSWORD EXPIRE NEVER;
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT';
create user root@'%' identified WITH mysql_native_password BY '$MYSQL_ROOT';
grant all privileges on *.* to root@'%' with grant option;
flush privileges;
EOF

# 设置复制用户
cat > /tmp/rep.sql <<EOF
SET SQL_LOG_BIN=0;
CREATE USER IF NOT EXISTS repl@'%' IDENTIFIED WITH 'mysql_native_password' BY 'repl';
GRANT SUPER,REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO repl@'%';
FLUSH PRIVILEGES;
SET SQL_LOG_BIN=1;
CHANGE MASTER TO MASTER_USER='repl', MASTER_PASSWORD='repl' FOR CHANNEL 'group_replication_recovery';
EOF

# install mgr
cat > /tmp/mgr.sql <<EOF
INSTALL PLUGIN group_replication SONAME 'group_replication.so';
SHOW PLUGINS;
EOF

# start mgr
cat > /tmp/start.sql <<EOF
SET GLOBAL group_replication_bootstrap_group=ON;
START GROUP_REPLICATION;
SET GLOBAL group_replication_bootstrap_group=OFF;
SELECT * FROM performance_schema.replication_group_members;
EOF

# join
cat > /tmp/join.sql <<EOF
SELECT * FROM performance_schema.replication_group_members;
show global variables like '%seed%';
START GROUP_REPLICATION;
SELECT * FROM performance_schema.replication_group_members;
SHOW STATUS LIKE 'group_replication_primary_member';
show global variables like 'group_replication_single%';
EOF

# 只在第一次执行时初始化
if [ ! -f $LOCK ];then
	rm -fr /var/lib/mysql
	mysqld --initialize-insecure --user=mysql
	systemctl start mysqld
	# (HY000): Can't connect to local MySQL server through socket '/var/lib/mysql/mysql.sock' (2)，重启生成 sock 文件
	systemctl restart mysqld
	systemctl status mysqld
	mysql -uroot -e "show databases;"

	mysql -uroot < /tmp/init.sql
	mysql -uroot -p$MYSQL_ROOT < /tmp/rep.sql
	mysql -uroot -p$MYSQL_ROOT -e "SHOW PLUGINS" |grep -q "group_replication" || mysql -uroot -p$MYSQL_ROOT < /tmp/mgr.sql

	# reset master. 解决 The member contains transactions not present in the group. The member will now exit the group. 报错
	# 见 https://blog.csdn.net/snowhite91/article/details/83791997
	# MySQL是新装的没问题，但是每次新装MySQL都要修改密码，如果在修改密码的时候就已经把binlog_format=on配在了/etc/my.cnf中，那么修改密码的记录是存在在binlog日志中的。所以就会提示前文中的日志错误。
	mysql -uroot -proot -e "RESET MASTER;"
	# only run on first node. 
	# 当使用 vagrant reload 虚拟机的时候，1 号虚机最先关机，这时候 2，3 号如果还在写入，会比 1 号数据新，当 reload 完成之后，如果还默认以1 号为准，用 SQL 语句启动集群，会出现 contains errant transactions that did not originate from the cluster. (RuntimeError) 报错。因此不能默认 1 号 启动，除第一次启动外，应使用 mysql-shell 来重启
	[ "$ID"x == "10101"x ] && mysql -uroot -p$MYSQL_ROOT < /tmp/start.sql
	# run on other two node
	# 同上，仅第一次启动虚机时执行。之后使用 mysql-shell 来管理
	[ "$ID"x == "10101"x ] || mysql -uroot -p$MYSQL_ROOT < /tmp/join.sql

	touch $LOCK
fi



# fix nginx server_name
sed -i "s/__SERVER_NAME__/$MYIP/g" /etc/nginx/nginx.conf
# fix app_root_url
PHP_CONF="/etc/php-fpm.d/www.conf"
grep -q "ITOP_URL" $PHP_CONF || echo "env[ITOP_URL]=http://$MYIP/" >> $PHP_CONF

# ensure web dir permission
chown -R nginx:nginx $WEBROOT

# rsync itop dir. base 192.168.10.101
# data/.maintenance 不应该被同步，否则可能将导致 itop-mgr-2,itop-mgr-3停留在维护状态无法使用。
# node1 上执行维护任务，进入维护状态，node2, node3 恰好开始同步，node1 维护完成之后删除 data/.maintenance，但是 node2, node3 没有删除（不能使用 rsync --delete 选项，因为每个节点有不同的cache等文件，此选项会删除这些不同的文件）。应将此文件排除在 rsync 同步列表之外。
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
	exclude = data/cache-production/* data/transactions/* log/* data/.maintenance
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
systemctl restart ntpd

# auto install(only install one instance: 192.168.10.101)
ITOP_CONF_FILE="$WEBROOT/conf/production/config-itop.php"
if [ ! -f $ITOP_CONF_FILE ] && [ "$ID"x == "10101"x ];then
	cd $WEBROOT/toolkit
	php auto_install.php
	sed -i "s/'__ITOP_URL__'/getenv('ITOP_URL')/g" $ITOP_CONF_FILE
	cd ../
	chown -R nginx:nginx conf
	chown -R nginx:nginx env-production
	chown -R nginx:nginx data
	chown -R nginx:nginx log
fi

# 由于 auto install 中使用的app root url 是 __ITOP_URL__，auto install 完成之后才替换为 getenv，因此生成的 apc cache 是错误，需要删除 cache
echo "remove apc cache"
rm -fr $WEBROOT/data/cache-production/


# iTop 调整一些配置，异步邮件，时区等
if [ "$ID"x == "10101"x ];then
	sed -i "s/'email_asynchronous' =>.*/'email_asynchronous' => true,/g" $ITOP_CONF_FILE
	sed -i "s/'timezone' =>.*/'timezone' => 'Asia\/Shanghai',/g" $ITOP_CONF_FILE
	sed -i "s/'csv_file_default_charset' =>.*/'csv_file_default_charset' => 'UTF-8',/g" $ITOP_CONF_FILE
fi
# cron(only one instance)
CRONLOG=/var/log/itop
if [ "$ID"x == "10101"x ];then
	[ ! -d $CRONLOG ] && mkdir $CRONLOG
	chown nginx:nginx $CRONLOG
	grep -q "cron.php" /etc/crontab || echo "*/5 * * * * nginx /usr/bin/php $WEBROOT/webservices/cron.php --param_file=/etc/itop-cron.params --verbose=1 >>$CRONLOG/cron.log 2>&1" >> /etc/crontab
fi
cat > /etc/itop-cron.params <<EOF
auth_user=admin
auth_pwd=admin
EOF

# 使用 mysqlsh 管理集群
# MGR集群接管：如果在已经配置好的组复制上创建InnoDB Cluster，并且希望使用它来创建集群，可将adoptFromGR选项传递给dba.createCluster()函数。创建的InnoDB Cluster会匹配复制组是以单主数据库还是多主数据库运行。要采用现有的组复制组，使用MySQL Shell连接到组成员。
# 在最后一个节点上操作，即等所有节点启动后在操作
JSDIR="/vagrant/js"
MYSQLSHLOG=/tmp/mysql.log

if [ "$ID"x == "10103"x ];then
	echo "Run Get Status"
	mysqlsh -i --js --file=$JSDIR/status.js > $MYSQLSHLOG 2>&1
	grep "RuntimeError" $MYSQLSHLOG && r=0 || r=1
	if [ $r -eq 0 ];then
		grep "but GR is not active" $MYSQLSHLOG && r=0 || r=1
		if [ $r -eq 0 ];then
			echo "Cluster Need Reboot"
			mysqlsh --log-level=debug -i --js --file=$JSDIR/reboot.js
		else
			echo "Init Cluster"
			# 3号节点处于 RECOVERING 状态时是 R/O 模式，会报错：WARNING: Error updating recovery credentials for 192.168.10.103:3306: Cannot set Group Replication recovery user to 'mysql_innodb_cluster_10103'. Error executing CHANGE MASTER statement: 192.168.10.103:3306: This operation cannot be performed with a running slave io thread; run STOP SLAVE IO_THREAD FOR CHANNEL 'group_replication_recovery' first.
			# 因此需要等待 3号 ONLINE 之后在 init
			for id in  `seq 1 30`;do
				online=`mysql -uroot -proot -e "SELECT * FROM performance_schema.replication_group_members;" |grep "ONLINE" |wc -l`
				if [ $online -lt 3 ];then
					echo "Wait all nodes ONLINE. Try $id times"
					sleep 1;
					continue
				else
					mysqlsh --js --file=$JSDIR/init.js
					break;
				fi
			done
		fi
	else
		cat $MYSQLSHLOG
	fi
fi