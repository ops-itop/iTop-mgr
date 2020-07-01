#!/bin/bash
mv /etc/yum.repos.d/* /tmp
curl -s http://mirrors.aliyun.com/repo/Centos-7.repo -o /etc/yum.repos.d/CentOS-Base.repo
curl -s http://mirrors.aliyun.com/repo/epel-7.repo -o /etc/yum.repos.d/epel.repo

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

if [ ! -d /home/wwwroot/default ];then
    wget https://sourceforge.net/projects/itop/files/latest/download -O /tmp/itop.zip
    mkdir -p /home/wwwroot/
    cd /home/wwwroot/ && unzip /tmp/itop.zip && rm -f /tmp/itop.zip && mv web default

    # toolkit
    wget http://dev.tecbbs.com/iTopDataModelToolkit-2.7.zip -O /tmp/toolkit.zip
    cd default && unzip /tmp/toolkit.zip && rm -f /tmp/toolkit.zip

    chown -R nginx:nginx default
fi

sed -i 's/ = apache/ = nginx/g' /etc/php-fpm.d/www.conf
chgrp nginx /var/lib/php/session

cat > /etc/nginx/php-pathinfo.conf << "EOF"
        location ~ [^/]\.php(/|$)
        {
            fastcgi_pass  127.0.0.1:9000;
            fastcgi_index index.php;
            include fastcgi.conf;
            fastcgi_split_path_info ^(.+?\.php)(/.*)$;
            set $path_info $fastcgi_path_info;
            fastcgi_param PATH_INFO       $path_info;
            try_files $fastcgi_script_name =404;            
        }
EOF

cat > /etc/nginx/nginx.conf << "EOF"
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

# Load dynamic modules. See /usr/share/doc/nginx/README.dynamic.
include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    # Load modular configuration files from the /etc/nginx/conf.d directory.
    # See http://nginx.org/en/docs/ngx_core_module.html#include
    # for more information.
    include /etc/nginx/conf.d/*.conf;

    server {
        listen       80 default_server;
        listen       [::]:80 default_server;
        server_name  __SERVER_NAME__;
        root         /home/wwwroot/default;
        # Add index.php to the list if you are using PHP
        index index.html index.htm index.nginx-debian.html index.php;
        
        # Load configuration files for the default server block.
        include /etc/nginx/default.d/*.conf;

        access_log /var/log/nginx/default_access.log;
        error_log /var/log/nginx/default_error.log;

        fastcgi_connect_timeout 300s;
        fastcgi_send_timeout 300s;
        fastcgi_read_timeout 300s;

        include php-pathinfo.conf;

        location / {
            try_files $uri $uri/ =404;
        }

        error_page 404 /404.html;
            location = /40x.html {
        }

        error_page 500 502 503 504 /50x.html;
            location = /50x.html {
        }
    }
}
EOF

IP=`ifconfig eth1 |grep "inet "|awk '{print $2}'`
sed -i "s/__SERVER_NAME__/$IP/g" /etc/nginx/nginx.conf

systemctl restart nginx

rm -fr /var/cache/yum/*