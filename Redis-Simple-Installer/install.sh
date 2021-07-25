#!/bin/bash

#----------------------------------------------------------#
#                  update system                               #
#----------------------------------------------------------#


sudo apt-get update

#----------------------------------------------------------#
#                   functions                              #
#----------------------------------------------------------#


#text colors
redtext() { echo "$(tput setaf 1)$*$(tput setaf 7)"; }
greentext() { echo "$(tput setaf 2)$*$(tput setaf 7)"; }
yellowtext() { echo "$(tput setaf 3)$*$(tput setaf 7)"; }

#to round float
round() { echo $1 | awk '{print int($1+0.5)}'; }

#to run calculation of a string
calc() { awk "BEGIN { print "$*" }"; }

#----------------------------------------------------------#
#                   settings                               #
#----------------------------------------------------------#

physical_memory_mb=$(awk '/^MemTotal/ { printf("%.0f", $2/1024 ) }' < /proc/meminfo)

read -r -p "Enter IP address which will access this redis server:" vAccessIP

#----------------------------------------------------------#
#                   Install redis-server                   #
#----------------------------------------------------------#

#install redis
sudo apt install redis-server

#redis config: bind to 0.0.0.0 so redis can listen outside connection
#sed "s@^# bind 127.0.0.1@bind 0.0.0.0@" /etc/redis/redis.conf #https://wiki.linuxchina.net/index.php/Redis_install_-How_To_Install_and_Use_Redis
sed -i -e 's/^# bind 127.0.0.1.*/bind 0.0.0.0/' /etc/redis/redis.conf

#redis config: maxmemory-policy using lfu: https://redis.io/topics/lru-cache
sed -i -e "/bind 0.0.0.0/a maxmemory-policy allkeys-lfu" /etc/redis/redis.conf

#redis config: maxmemory 50% of node memory 
# https://github.com/W3EDGE/w3-total-cache/wiki/FAQ:-Installation:-Redis-Server
redis_max_memory_value=$( calc 50/100*$physical_memory_mb )
redis_max_memory_value=$( round $redis_max_memory_value )
redis_max_memory_value_text="${redis_max_memory_value}mb"
echo $redis_max_memory_value_text
sed -i -e "/bind 0.0.0.0/a maxmemory $redis_max_memory_value_text" /etc/redis/redis.conf

#restart redis
sudo systemctl restart redis-server

#----------------------------------------------------------#
#                   Enable UFW                  	   #
#----------------------------------------------------------#

# https://www.digitalocean.com/community/tutorials/ufw-essentials-common-firewall-rules-and-commands

#allow redis access from single ip
#sudo ufw allow proto tcp from $vAccessIP/32 to any port 6379 
sudo ufw allow from $vAccessIP to any port 6379

#allow ssh access from anywhere (so we can manage it from everywhere)
#sudo ufw allow “OpenSSH”
sudo ufw allow 22

#enable ufw
sudo ufw enable

#fix bug 'ufw does not start automatically at boot' see comment #23 here: https://bugs.launchpad.net/ubuntu/+source/ufw/+bug/1726856?comments=all
echo '@reboot root ufw enable' >> /etc/crontab
    
#----------------------------------------------------------#
#                   install Monit                          #
#----------------------------------------------------------#

greentext "installing monit"

sudo apt install monit

#allow only localhost to access monit
echo 'set httpd port 2812
	allow localhost' >> /etc/monit/conf.d/custom.conf

#redis
echo 'check process redis with pidfile  /var/run/redis/redis-server.pid
    start program = "/bin/systemctl start redis-server"
    stop program = "/bin/systemctl stop redis-server"
    if failed port 6379 protocol redis then restart
    if 5 restarts within 5 cycles then timeout' >> /etc/monit/conf.d/custom.conf

#ufw/iptables isn't a service so we cant use monit to monitor this

#restart monit
sudo service monit restart
sudo monit start all
