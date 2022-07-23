#!/bin/bash

user=$1
domain=$2
ip=$3
home=$4
docroot=$5

# https://wordpress.org/support/article/nginx/
# https://forum.nginx.org/read.php?2,2450,273132
# https://www.nginx.com/resources/wiki/start/topics/examples/reverseproxycachingexample/
# change levels to "1:2". its more common
# Note: #cache levels still "2", if its differs than hestiacp it will show "cache had previously different levels"
str="proxy_cache_path /var/cache/nginx/$domain levels=2" 
str="$str keys_zone=$domain:10m inactive=24h max_size=1g;" 
conf='/etc/nginx/conf.d/01_caching_pool.conf'
if [ -e "$conf" ]; then

    #if 'previous setting' for this domain exist, delete it first before continuing (this is to make sure if we change something it gets applied, for example if we change the levels of cache dir)
    if [ -n "$(grep "=${domain}:" $conf)" ]; then
        sed -i "/=${domain}:/d" $conf
    fi

    #then, if seeting for this really not exist, add it
    if [ -z "$(grep "=${domain}:" $conf)" ]; then
        echo "$str" >> $conf
    fi

else
    echo "$str" >> $conf
fi

