#!/bin/bash

NODE1="192.168.10.201"
NODE2="192.168.10.202"
NODE3="192.168.10.203"
MYIP=`ifconfig eth1 |grep "inet " |awk '{print $2}'`
ID=`echo $MYIP |awk -F'.' '{printf "%s%s", $3,$4}'`
CLUSTER_NAME="mgr"
MYSQL_ROOT="root"
LOCK="/etc/mysql_init.lock"

systemctl enable mysqld
systemctl restart mysqld

# 修改root用户密码
cat > /tmp/init.sql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT' PASSWORD EXPIRE NEVER;
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT';
create user root@'%' identified WITH mysql_native_password BY '$MYSQL_ROOT';
grant all privileges on *.* to root@'%' with grant option;
flush privileges;
EOF

cat << EOF > /tmp/config_local_instance.js
dba.configureLocalInstance('root@$MYIP:3306', {'password': 'root', 'interactive': false})
EOF

cat << EOF > /tmp/check_local_instance.js
shell.connect('root@192.168.10.201:3306', 'root')
dba.checkInstanceConfiguration()
EOF

 cat << EOF > /tmp/init_cluster.js
shell.connect('root@192.168.10.201:3306', 'root')
dba.createCluster('$CLUSTER_NAME', {'localAddress': '192.168.10.201','multiPrimary': true, 'force': true})
var cluster=dba.getCluster('$CLUSTER_NAME')
cluster.addInstance('root@192.168.10.202:3306', {'localAddress': '192.168.10.202', 'password': 'root', 'recoveryMethod':'clone'})
cluster.addInstance('root@192.168.10.203:3306', {'localAddress': '192.168.10.203', 'password': 'root','recoveryMethod':'clone'})
EOF

# 只在第一次执行时初始化
if [ ! -f $LOCK ];then
	rm -fr /var/lib/mysql
	mysqld --initialize-insecure --user=mysql
	systemctl start mysqld
	# (HY000): Can't connect to local MySQL server through socket '/var/lib/mysql/mysql.sock' (2)，重启生成 sock 文件
	grep "report_host" /etc/my.cnf || echo "report_host=$MYIP" >> /etc/my.cnf
	systemctl restart mysqld
	systemctl status mysqld
	mysql -uroot -e "show databases;"

	mysql -uroot < /tmp/init.sql

	# 配置本地实例
	mysqlsh --js --file=/tmp/config_local_instance.js
	systemctl restart mysqld
	# 检查本地实例
	mysqlsh --js --file=/tmp/check_local_instance.js

	# 等全部节点启动后执行，只执行一次，js脚本中只在 201 节点上执行
	if [ "$ID"x == "10203"x ];then
		mysqlsh --js --file=/tmp/init_cluster.js
	fi

	touch $LOCK
fi


cat > /tmp/status.js <<EOF
shell.connect('root@192.168.10.201', 'root');
var cluster = dba.getCluster('$CLUSTER_NAME');
cluster.status();
EOF

cat > /tmp/reboot.js <<EOF
shell.connect('root@192.168.10.201', 'root');
dba.rebootClusterFromCompleteOutage('$CLUSTER_NAME',{rejoinInstances:["192.168.10.202:3306","192.168.10.203:3306"]})
var cluster = dba.getCluster('$CLUSTER_NAME');
cluster.status();
EOF


# 重启集群在最后一个节点上操作，即等所有节点启动后在操作
MYSQLSHLOG=/tmp/mysql.log

if [ "$ID"x == "10203"x ];then
	echo "Run Get Status"
	# 加 -i 选项控制台输出 status 结果
	mysqlsh -i --js --file=/tmp/status.js > $MYSQLSHLOG 2>&1
	grep "RuntimeError" $MYSQLSHLOG && r=0 || r=1
	if [ $r -eq 0 ];then
		grep "but GR is not active" $MYSQLSHLOG && r=0 || r=1
		if [ $r -eq 0 ];then
			echo "Cluster Need Reboot"
			mysqlsh --js --file=$JSDIR/reboot.js
		fi
	else
		cat $MYSQLSHLOG
	fi
fi