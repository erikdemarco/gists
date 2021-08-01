#!/bin/bash

user=$1
domain=$2
ip=$3
home=$4
docroot=$5

# https://wordpress.org/support/article/nginx/
# https://forum.nginx.org/read.php?2,2450,273132
# change levels to "1:2". its more common
str="proxy_cache_path /var/cache/nginx/$domain levels=1:2" 
str="$str keys_zone=$domain:10m inactive=60m max_size=512m;" 
conf='/etc/nginx/conf.d/01_caching_pool.conf'
if [ -e "$conf" ]; then
    if [ -z "$(grep "=${domain}:" $conf)" ]; then
        echo "$str" >> $conf
    fi
else
    echo "$str" >> $conf
fi

