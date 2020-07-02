#!/bin/bash
SHARE_DIR=/vagrant
WEBROOT="/home/wwwroot/default"

mv /etc/yum.repos.d/* /tmp
curl -s http://mirrors.aliyun.com/repo/Centos-7.repo -o /etc/yum.repos.d/CentOS-Base.repo
curl -s http://mirrors.aliyun.com/repo/epel-7.repo -o /etc/yum.repos.d/epel.repo

sed -i '/aliyuncs.com/d' /etc/yum.repos.d/*.repo

# 安装 常用/必要 软件
yum install -y wget vim yum-plugin-priorities ntp unzip

# 时区
rm -rf /etc/localtime
ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# 换用国内ntp，解决 ceph mon clock skew detected 问题，国外ntp延时超过0.05s
sed -i -r '/^server /d' /etc/ntp.conf
cat >> /etc/ntp.conf <<EOF
server ntp.ntsc.ac.cn iburst prefer
server ntp.aliyun.com iburst
server ntp2.aliyun.com iburst
server ntp3.aliyun.com iburst
server ntp4.aliyun.com iburst
EOF

systemctl enable ntpd

# 允许密码登录
sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
systemctl restart sshd

# 在 CentOS 和 RHEL 上， SELinux 默认为 Enforcing 开启状态。为简化安装，我们建议把 SELinux 设置为 Permissive 或者完全禁用，也就是在加固系统配置前先确保集群的安装、配置没问题。用下列命令把 SELinux 设置为 Permissive 
sed -i 's/^SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

# 安装 MySQL 5.7
yum install -y https://dev.mysql.com/get/mysql57-community-release-el7-11.noarch.rpm
yum install -y mysql-community-server mysql-shell mysql-router

# 安装 Nginx 和 PHP
yum install -y http://rpms.remirepo.net/enterprise/remi-release-7.rpm
yum-config-manager --enable remi-php73
yum install -y nginx php php-fpm php-xml php-mysqlnd php-soap php-ldap php-zip php-json php-mbstring php-gd graphviz rsync

systemctl enable nginx
systemctl enable php-fpm

if [ ! -d $WEBROOT ];then
    wget https://sourceforge.net/projects/itop/files/latest/download -O /tmp/itop.zip
    mkdir -p /home/wwwroot/
    cd /home/wwwroot/ && unzip /tmp/itop.zip && rm -f /tmp/itop.zip && mv web default
fi

sed -i 's/ = apache/ = nginx/g' /etc/php-fpm.d/www.conf
chgrp nginx /var/lib/php/session

cp -u /vagrant/conf/php-pathinfo.conf /etc/nginx
cp -u /vagrant/conf/nginx.conf /etc/nginx
cp -ru /vagrant/toolkit-2.7 $WEBROOT/toolkit
cp -u /vagrant/auto_install/* $WEBROOT/toolkit
cp -u /vagrant/tools/* /root

chmod +x /root/run.sh
chown -R nginx:nginx $WEBROOT
rm -fr /var/cache/yum/*