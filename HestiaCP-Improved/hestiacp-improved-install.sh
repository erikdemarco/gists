#!/bin/bash


#----------------------------------------------------------#
#                  upgrade system                          #
#----------------------------------------------------------#


sudo apt-get update

#upgrade system?
#echo "Y" | sudo apt-get dist-upgrade



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

#round down
#https://stackoverflow.com/a/67727181/15185328
#roundDownNearestHundred() { echo $1 | awk '{printf "%d00\n", $0 / 100}'; }
#roundDownNearestTen() { echo $1 | awk '{printf "%d0\n", $0 / 10}'; }

# Defining password-gen function (hestiacp)
gen_pass() {
    head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16
}

#----------------------------------------------------------#
#                   settings                               #
#----------------------------------------------------------#


# Defining return code check function
check_result() {
    if [ $1 -ne 0 ]
    then
	redtext "Error: $2"
        exit $1
    else
    	greentext "Finished: $2"
    fi
}


read -r -p "What e-mail address would you like to receive alerts to? " vEmail
read -r -p "Please type your server hostname, or press enter to use default: " vHostname
read -r -p "Which port do you want the panel can be accessed from? or press enter to use default: " vPort
read -r -p "Please type a password to use or press enter to generate it automatically: " vPassword
read -r -p "Please type timezone of your server (example: Asia/Jakarta) or press enter to use default: " vTimezone

#additional app
read -r -p "Do you want to add local redis-server? [y/N] " vAddRedisServer

read -r -p "Do you want to add SSH Key? [y/N] 
(if you don't have ssh key, you can generate it yourself using using tool like PuTTYgen) " vAddSsh

if [ -z "$vHostname" ]; then
	vHostname=$(hostname -f)
fi


#(use port that supported by cloudflare, so if you use cloudflare, you dont need to issue letsencrypt cert: https://support.cloudflare.com/hc/en-us/articles/200169156-Which-ports-will-CloudFlare-work-with-)
if [ -z "$vPort" ]
then
   vPort=2083
else
   vPort=$vPort
fi

if [ -z "$vPassword" ]
then
   generatedpass=$(gen_pass)
   vPassword="$generatedpass"
else
   vPassword="$vPassword"
fi

if [ $vAddSsh == "y" ] || [ $vAddSsh == "Y" ]; then
  read -r -p "Please input your public SSH Key: " vSshKey
fi

read -r -p "Do you want to make admin panel, mysql, and phpmyadmin accesible to localhost only (you can still access admin panel using SSH tunnel)? [y/N] " vProtectAdminPanel


#dropbox backup
read -r -p "Do you want to automated backup to dropbox daily? ( make sure you already install dropbox-uploader. if not, install it using command 'curl -O https://raw.githubusercontent.com/erikdemarco/gists/main/HestiaCP-Improved/dropbox-uploader-install.sh && bash dropbox-uploader-install.sh' ) [y/N] " vDropboxUploader

#additional open_basedir rule
read -r -p "Do you want to add additional directory to apache's open_basedir? [y/N] " vApacheOpenBasedir
if [ $vApacheOpenBasedir == "y" ] || [ $vApacheOpenBasedir == "Y" ]; then
  read -r -p "Please input your additional directory, separated by semicolon, do not add any quote, slash must be escaped (EXAMPLE: '\/home\/%user%\/dir1:\/home\/%user%\/dir2'): " vApacheOpenBasedirRule
fi

vAddString="-r $vPort -s $vHostname -e $vEmail -p $vPassword"




#----------------------------------------------------------#
#                   install vestacp                        #
#----------------------------------------------------------#


curl -O https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh

#apache+nginx+phpfpm+named
#echo "Y" | bash hst-install.sh -a yes -w yes -o no -v no -j no -k yes -m yes -g no -x no -z no -c no -t no -i yes -b yes -q no -d no -l en -y no $vAddString -force

#apache+nginx+phpfpm
echo "Y" | bash hst-install.sh -a yes -w yes -o no -v no -j no -k no -m yes -g no -x no -z no -c no -t no -i yes -b yes -q no -d no -l en -y no $vAddString -force



#----------------------------------------------------------#
#                   needed variable                        #
#----------------------------------------------------------#

#get info
memory=$(grep 'MemTotal' /proc/meminfo |tr ' ' '\n' |grep [0-9])  #get current server ram size (in K)
real_available_memory_kb=$memory	# available memory minus memory allocated for other apps, will be used later (in K)
vIPAddress=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')

export xpanelname="hestia"
export VERSION='ubuntu'
export release="$(lsb_release -s -r)"
export XPANEL="/usr/local/$xpanelname/"
export xpanelcp="$XPANEL/install/$VERSION/$release"
export servername=$(hostname -f)
export BIN="${XPANEL}bin"


#needed
export VESTA=/usr/local/vesta/
export HESTIA=/usr/local/hestia/


#----------------------------------------------------------#
#          calculate real_available_memory                 #
#----------------------------------------------------------#

# redis-server
# allocatied memory for redis: 10% from server memory
# maxmemory 50%-70% from allocated memory
# while saving an RDB file on disk or rewriting the AOF log Redis may use up to 2 times the memory normally used
# https://blog.opstree.com/2019/04/16/redis-best-practices-and-performance-tuning/
# https://docs.digitalocean.com/products/databases/redis/resources/memory-usage/
# https://pantheon.io/docs/object-cache
# https://docs.digitalocean.com/products/databases/redis/resources/memory-usage/
# https://gridpane.com/kb/configure-redis/
if [ $vAddRedisServer == "y" ] || [ $vAddRedisServer == "Y" ]; then
  memory_allocated_for_redis_server_kb=$( calc 10/100*$memory )
  memory_allocated_for_redis_server_kb=$( calc 50/100*$memory_allocated_for_redis_server_kb )
  memory_allocated_for_redis_server_kb=$( round $memory_allocated_for_redis_server_kb )
  real_available_memory_kb=$( calc $real_available_memory_kb-$memory_allocated_for_redis_server_kb )
fi




#----------------------------------------------------------#
#                  change timezone                         #
#----------------------------------------------------------#


if [ ! -z "$vTimezone" ]; then
	${XPANEL}bin/v-change-sys-timezone $vTimezone
fi


#----------------------------------------------------------#
#            optimize and hardening hestiacp                #
#----------------------------------------------------------#

#change default page template for hostname
echo -n > /home/admin/web/$servername/public_html/index.html
#echo -n > /home/admin/web/$servername/public_shtml/index.html		#doenst exist anymore in new hestiacp

#change default page template for future use
echo -n > ${XPANEL}data/templates/web/skel/public_html/index.html
#echo -n > ${XPANEL}data/templates/web/skel/public_shtml/index.html	#doenst exist anymore in new hestiacp



#----------------------------------------------------------#
#              	auto update letsencrypt ssl                #
#----------------------------------------------------------#

# Random password generator
generate_password() {
    matrix=$1
    lenght=$2
    if [ -z "$matrix" ]; then
        matrix=0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz
    fi
    if [ -z "$lenght" ]; then
        lenght=10
    fi
    i=1
    while [ $i -le $lenght ]; do
        pass="$pass${matrix:$(($RANDOM%${#matrix})):1}"
       ((i++))
    done
    echo "$pass"
}

# Adding LE autorenew cronjob
if [ -z "$(grep v-update-lets ${XPANEL}data/users/admin/cron.conf)" ]; then
    min=$(generate_password '012345' '2')
    hour=$(generate_password '1234567' '1')
    cmd="sudo ${XPANEL}bin/v-update-letsencrypt-ssl"
    ${XPANEL}bin/v-add-cron-job admin "$min" "$hour" '*' '*' '*' "$cmd" > /dev/null
fi



#----------------------------------------------------------#
#              fix hestiacp default template bug            #
#----------------------------------------------------------#

greentext "fixing template bug..."


#deactivate 'open_basedir' line from the 'default' template (more secure using additional openbasedir rule)
#sed -i -e '/open_basedir/s/.*/#deleted#/' ${XPANEL}data/templates/web/apache2/default.stpl
#sed -i -e '/open_basedir/s/.*/#deleted#/' ${XPANEL}data/templates/web/apache2/default.tpl

#additional open_basedir rule
if [ $vApacheOpenBasedir == "y" ] || [ $vApacheOpenBasedir == "Y" ]; then
  sed -i -e '/open_basedir/ s/$/:'"$vApacheOpenBasedirRule"'/' ${XPANEL}data/templates/web/apache2/default.stpl
  sed -i -e '/open_basedir/ s/$/:'"$vApacheOpenBasedirRule"'/' ${XPANEL}data/templates/web/apache2/default.tpl
  sed -i -e '/open_basedir/ s/$/:'"$vApacheOpenBasedirRule"'/' ${XPANEL}data/templates/web/php-fpm/default.tpl
fi


#----------------------------------------------------------#
#                   optimize httpd                         #
#----------------------------------------------------------#

#fix for 'Could not reliably determine the server's fully qualified domain name' (#2215)
#https://askubuntu.com/a/256018
#https://help.ubuntu.com/community/ApacheMySQLPHP#Troubleshooting_Apache

greentext "optimizing httpd..."

httpd_optimized_setting="\n
\n#OPTIMIZED APACHE Setting#
\n
\n#hide apache version
\nServerSignature Off
\nServerTokens Prod
\n
\n#fix Could not reliably determine the server's fully qualified domain name
\n#ServerName localhost
\n
\n#OPTIMIZED APACHE Setting#
\n"

#append to current httpd settings
echo -e $httpd_optimized_setting >> /etc/apache2/apache2.conf

#restart apache 
sudo systemctl restart apache2 



#----------------------------------------------------------#
#                   install Monit                          #
#----------------------------------------------------------#

# https://mmonit.com/monit/documentation/monit.html#CONFIGURATION-EXAMPLES
# https://mmonit.com/wiki/Monit/ConfigurationExamples

greentext "installing monit"

sudo apt install monit

#allow only localhost to access
echo 'set httpd port 2812
	allow localhost' >> /etc/monit/conf.d/custom.conf

#apache
echo 'check process apache2 with pidfile /run/apache2/apache2.pid
    start program = "/etc/init.d/apache2 start"
    stop program  = "/etc/init.d/apache2 stop"' >> /etc/monit/conf.d/custom.conf

#nginx
echo 'check process nginx with pidfile /run/nginx.pid
    start program = "/etc/init.d/nginx start"
    stop program  = "/etc/init.d/nginx stop"' >> /etc/monit/conf.d/custom.conf

#mariadb (hestiacp)
echo 'check process mariadb with pidfile /run/mysqld/mysqld.pid
    start program = "/bin/systemctl start mariadb"
    stop program  = "/bin/systemctl stop mariadb"' >> /etc/monit/conf.d/custom.conf

#mysql (vestacp)
#echo 'check process mysql with pidfile /run/mysqld/mysqld.pid
#    start program = "/bin/systemctl start mysql"
#    stop program  = "/bin/systemctl stop mysql"' >> /etc/monit/conf.d/custom.conf

#openssh
echo 'check process sshd with pidfile /var/run/sshd.pid
    start program "/etc/init.d/ssh start"
    stop program "/etc/init.d/ssh stop"
    if failed port 22 protocol ssh then restart' >> /etc/monit/conf.d/custom.conf

#hestia-php
echo 'check process '"$xpanelname"'-php with pidfile /var/run/'"$xpanelname"'-php.pid
    start program = "/bin/systemctl start '"$xpanelname"'"
    stop program  = "/bin/systemctl stop '"$xpanelname"'"' >> /etc/monit/conf.d/custom.conf

#hestia-nginx
echo 'check process '"$xpanelname"'-nginx with pidfile /var/run/'"$xpanelname"'-nginx.pid
    start program = "/bin/systemctl start '"$xpanelname"'"
    stop program  = "/bin/systemctl stop '"$xpanelname"'"' >> /etc/monit/conf.d/custom.conf

#fail2ban
echo 'check process fail2ban with pidfile /var/run/fail2ban/fail2ban.pid
   start program = "/etc/init.d/fail2ban start"
   stop program = "/etc/init.d/fail2ban stop"' >> /etc/monit/conf.d/custom.conf

#cron
echo 'check process cron with pidfile /var/run/crond.pid
   start program = "/etc/init.d/cron start"
   stop  program = "/etc/init.d/cron stop"' >> /etc/monit/conf.d/custom.conf
   
#iptables (https://mmonit.com/monit/documentation/monit.html#PROGRAM-STATUS-TEST) xpanelname must be alluppercase
echo '#!/bin/sh
/sbin/iptables -n -L fail2ban-'"${xpanelname^^}"' >/dev/null 2>&1
if [ "$?" -eq 0 ]
then
   exit 1 #running
else
   exit 2 #not running
fi
' > /usr/local/bin/check-iptables-status.sh  #create 'check-iptables-status.sh' program
chmod +x /usr/local/bin/check-iptables-status.sh    #make 'check-iptables-status.sh' executeable
echo "check program check-iptables-status with path /usr/local/bin/check-iptables-status.sh
      if status != 1 then exec '${XPANEL}bin/v-update-firewall'" >> /etc/monit/conf.d/custom.conf  #add monit rule
      
      
   
sudo service monit restart
sudo monit start all

#check_result $? 'starting monit'





#----------------------------------------------------------#
#                  add SSH KEY                             #
#----------------------------------------------------------#



if [ $vAddSsh == "y" ] || [ $vAddSsh == "Y" ]; then

    greentext "adding ssh key"

    #create the ~/.ssh directory if it does not already exist (it safe beacuse of -p)
    mkdir -p ~/.ssh

    #add your public key (vps_4096 file)
    echo $vSshKey >> ~/.ssh/authorized_keys

    #make sure permission and ownership correct
    chmod -R go= ~/.ssh
    chown -R $USER:$USER ~/.ssh

    #hardening ssh https://www.techrepublic.com/article/5-quick-ssh-hardening-tips/
    #TODO 2FA using google authenticator: https://medium.com/@jasonrigden/hardening-ssh-1bcb99cd4cef
    sed -i -e '/PermitRootLogin/s/.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    sed -i -e '/PermitEmptyPasswords/s/.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config
    sed -i -e '/MaxAuthTries/s/.*/MaxAuthTries 3/' /etc/ssh/sshd_config
    sed -i -e '/X11Forwarding/s/.*/X11Forwarding no/' /etc/ssh/sshd_config
    sed -i -e '/ClientAliveInterval/s/.*/ClientAliveInterval 300/' /etc/ssh/sshd_config

    #reload ssh
    systemctl reload sshd.service
    check_result $? 'reloading sshd'

fi

#----------------------------------------------------------#
#              		 OS tuning                     	   #
#----------------------------------------------------------#


# increase max open file descriptor, So we can increase maxclients for webserver like nginx
# https://www.programmersought.com/article/34684954797/
# https://www.fatalerrors.org/a/summary-of-nginx-s-too-many-open-files.html
# https://superuser.com/a/1027505
os_max_file_open=$(grep -r MemTotal /proc/meminfo | awk '{printf("%d\n",$2/1000)}')
ulimit -n $os_max_file_open	# instant result, so we dont need to reboot (only for root)
echo "*   soft   nofile  $os_max_file_open" >> /etc/security/limits.conf
echo "root   soft   nofile  $os_max_file_open" >> /etc/security/limits.conf


#----------------------------------------------------------#
#               	optimizing php                     #
#----------------------------------------------------------#

greentext "optimizing php..."

for pconf in $(find /etc/php* -name php.ini); do

    #inspired from https://www.hostgator.com/help/article/php-settings-that-cannot-be-changed

    #Disable php dangerous functions
    #https://www.acunetix.com/blog/articles/detection-prevention-introduction-web-shells-part-5/
    sed -i -e 's/disable_functions =/disable_functions = exec,passthru,shell_exec,system,eval,show_source,pcntl_exec,proc_open/g' $pconf

    #increase post_max_size
    sed -i -e '/post_max_size/s/.*/post_max_size = 64M/' $pconf

    #increase upload_max_filesize
    sed -i -e '/upload_max_filesize/s/.*/upload_max_filesize = 64M/' $pconf
    
    #increase memory_limit
    sed -i -e '/memory_limit/s/.*/memory_limit = 256M/' $pconf
    
    #optimum max_input_time
    sed -i -e '/max_input_time/s/.*/max_input_time = 60/' $pconf
    
done

#restart apache 
sudo systemctl restart apache2 


#----------------------------------------------------------#
#            install additional php extension            #
#----------------------------------------------------------#

#PHPINI_LOC="$(php -i | grep /.+/php.ini -oE)"

phpversion_short="$(php -r 'echo PHP_MAJOR_VERSION;').$(php -r 'echo PHP_MINOR_VERSION;')" #example:7.3

#add bcmath
sudo apt install php${phpversion_short}-bcmath
#addextension line to php.ini if its not yet activated automatically
#sed -i -e '/extension=bz2/a extension=bcmath' /etc/php/${phpversion_short}/cli/php.ini		

# install ioncube loader 
wget http://downloads3.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz
tar xzf ioncube_loaders_lin_x86-64.tar.gz -C /usr/local
for pconf in $(find /etc/php* -name php.ini); do
    echo "zend_extension=/usr/local/ioncube/ioncube_loader_lin_${phpversion_short}.so" >> $pconf
done

# php-redis
# https://www.prowebtips.com/install-redis-and-php-redis-extension-on-ubuntu/
sudo apt install -y php-redis	#is this needed?
sudo apt install -y "php${phpversion_short}-redis"


#php soap
sudo apt-get install php${phpversion_short}-soap
#addextension line to php.ini if its not yet activated automatically
#sed -i -e '/extension=bz2/a extension=soap' /etc/php/${phpversion_short}/cli/php.ini		

#restart apache 
sudo systemctl restart apache2 


#----------------------------------------------------------#
#     optimize mysql (reset some settings to default)      #
#----------------------------------------------------------#

# reset some setting to default value, because its not too important to tune
# watch 'max_allowed_packet' becasue mariadb default is 16M, but mysql default is 64M. if error happens, increase it to mysql default

mysql_config_file='/etc/mysql/my.cnf'

sed -i -e '/key_buffer_size/s/^/#/' $mysql_config_file
sed -i -e '/max_allowed_packet/s/^/#/' $mysql_config_file
sed -i -e '/table_open_cache/s/^/#/' $mysql_config_file
sed -i -e '/sort_buffer_size/s/^/#/' $mysql_config_file
sed -i -e '/net_buffer_length/s/^/#/' $mysql_config_file
sed -i -e '/read_buffer_size/s/^/#/' $mysql_config_file
sed -i -e '/read_rnd_buffer_size/s/^/#/' $mysql_config_file
sed -i -e '/myisam_sort_buffer_size/s/^/#/' $mysql_config_file

#restart mariadb 
sudo systemctl restart mariadb

greentext "Reset some settings to default value"

#----------------------------------------------------------#
#        optimize mysql (automatic configuration)      	   #
#----------------------------------------------------------#

# This automatic configuration modified from https://dev.mysql.com/doc/refman/8.0/en/innodb-dedicated-server.html
# innodb_log_files_in_group=1, Its defaulted to 1 and removed in MariaDB 10.6.0. We had some ideas to move to an append-only file and to partition the log into multiple files, but it turned out that a single fixed-size circular log file would perform best in typical scenarios.
# for innodb_flush_method better to use default value, so we not set any configuration for it https://mariadb.com/docs/reference/mdb/system-variables/innodb_flush_method/
# For innodb_buffer_pool_size, start with 50% 70% of total RAM
# innodb_log_file_size max 256M Especially on a system with a lot of writes to InnoDB tables you should set innodb_log_file_size to 25% of innodb_buffer_pool_size. However the bigger this value, the longer the recovery time will be when database crashes, so this value should not be set much higher than 256 MiB. Please note however that you cannot simply change the value of this variable. You need to shutdown the server, remove the InnoDB log files, set the new value in my.cnf, start the server, then check the error logs if everything went fine. See also this blog entry 
# If only using InnoDB, set innodb_buffer_pool_size to 70% of available RAM. (Plus key_buffer_size = 10M, small, but not zero.) Note: 70% is too much, we need to consider other app
# If only using MyISAM, set key_buffer_size to 20% of available RAM. (Plus innodb_buffer_pool_size=0)

# http://mysql.rjweb.org/doc.php/ricksrots
# https://haydenjames.io/mysql-server-has-gone-away-error-solutions/
# https://mariadb.com/kb/en/mariadb-memory-allocation/
# https://www.percona.com/blog/2016/10/12/mysql-5-7-performance-tuning-immediately-after-installation/
# https://github.com/fillup/phpmyadmin-minimal/blob/master/libraries/advisory_rules.txt
# https://github.com/major/MySQLTuner-perl/blob/656a7e51ed0c758131bca6ce6d73cb4201dce143/mysqltuner.pl
# https://github.com/phpmyadmin/phpmyadmin/blob/a96044476aae45fafd645fca8a042d2a42c7a897/libraries/advisory_rules_generic.php
# set innodb_log_file_size to 20% of innodb_buffer_pool_size (becasue the default innodb_log_files_in_group=2 we need to divide by 2, so for the recomended 25%, we use 12%)


mysql_config_file='/etc/mysql/my.cnf'

#innodb_buffer_pool_size_value percentage (in K)
if [ $real_available_memory_kb -lt 3900000 ]; then
    innodb_buffer_pool_size_percentage=35
else
    innodb_buffer_pool_size_percentage=50
fi

innodb_buffer_pool_size_value=$( calc $innodb_buffer_pool_size_percentage/100*$real_available_memory_kb )
innodb_buffer_pool_size_value=$( round $innodb_buffer_pool_size_value )
if [ $real_available_memory_kb -lt 900000 ]; then
	innodb_buffer_pool_size_value=128000
fi
innodb_buffer_pool_size_value_text="${innodb_buffer_pool_size_value}K"

#key_buffer_size_value=$( calc 20/100*$real_available_memory_kb )
#key_buffer_size_value=$( round $key_buffer_size_value )
#key_buffer_size_value_text="${key_buffer_size_value}K"

innodb_log_files_in_group_value=1
all_innodb_log_file_size_value=$( calc 25/100*$innodb_buffer_pool_size_value )
innodb_log_file_size_value=$( calc $all_innodb_log_file_size_value/$innodb_log_files_in_group_value )
innodb_log_file_size_value=$( round $innodb_log_file_size_value )
innodb_log_file_size_value_text="${innodb_log_file_size_value}K"
    #innodb_log_file_size_value recommended max value from phpmyadmin advisory (not relevan anymore)
    #if [ $innodb_log_file_size_value -gt 256000 ]; then
        #innodb_log_file_size_value_text="256M"
    #fi
    #innodb_log_file_size_value recommened max value is 128GB (remember its total value of innodb_log_file_size_value x innodb_log_files_in_group) https://mariadb.com/docs/reference/mdb/system-variables/innodb_log_file_size/
    if [ $all_innodb_log_file_size_value -gt 128000000 ]; then
        all_innodb_log_file_size_value=128000000
        innodb_log_file_size_value=$( calc $all_innodb_log_file_size_value/$innodb_log_files_in_group_value )
        innodb_log_file_size_value=$( round $innodb_log_file_size_value )
        innodb_log_file_size_value_text="${innodb_log_file_size_value}K"
    fi
    

#remove line containing matched config
sed -i -e '/innodb_buffer_pool_size/s/.*//' $mysql_config_file
#sed -i -e '/key_buffer_size/s/.*//' $mysql_config_file
sed -i -e '/innodb_log_file_size/s/.*//' $mysql_config_file
sed -i -e '/innodb_log_files_in_group/s/.*//' $mysql_config_file

#add config after [mysqld]
sed -i -e "/\[mysqld\]/a innodb_buffer_pool_size = $innodb_buffer_pool_size_value_text" $mysql_config_file
#sed -i -e "/\[mysqld\]/a key_buffer_size = $key_buffer_size_value_text" $mysql_config_file
sed -i -e "/\[mysqld\]/a innodb_log_file_size = $innodb_log_file_size_value_text" $mysql_config_file
sed -i -e "/\[mysqld\]/a innodb_log_files_in_group = $innodb_log_files_in_group_value" $mysql_config_file

#reverting connections settings to default value (because all of the above optimization is based on default connection value, to prove use mysqlcalculator.com)
# https://dev.mysql.com/doc/refman/5.7/en/server-system-variables.html
sed -i -e '/max_user_connections/s/.*//' $mysql_config_file
sed -i -e '/\[mysqld\]/a max_user_connections = 0' $mysql_config_file
#sed -i -e '/max_connections/s/.*//' $mysql_config_file
#sed -i -e '/\[mysqld\]/a max_connections = 151' $mysql_config_file

#restart mariadb 
sudo systemctl restart mariadb

greentext "Calculate and apply the most optimied mysql settings"






#----------------------------------------------------------#
#             optimize mysql (modify some settings)        #
#----------------------------------------------------------#

# CF will give 504 error if origin server not responding for 100seconds, so we follow it, we should wait for 100seconds
# slow query is all query which processed more than 1 second
# https://mariadb.com/docs/reference/mdb/system-variables/long_query_time/ 

mysql_config_file='/etc/mysql/my.cnf'

#turn off cache, better to use object cache like redis
sed -i -e '/query_cache_type/s/.*/query_cache_type = 0/' $mysql_config_file
sed -i -e '/query_cache_size/s/.*/query_cache_size = 0/' $mysql_config_file

#timeout, should we set wait_timeout to 30? because php timelimit is 30
sed -i -e '/wait_timeout/s/.*/wait_timeout = 100/' $mysql_config_file
sed -i -e '/interactive_timeout/s/.*/interactive_timeout = 100/' $mysql_config_file
sed -i -e '/long_query_time/s/.*/long_query_time = 1/' $mysql_config_file

#restart mariadb 
sudo systemctl restart mariadb

greentext "Modified some mysql settings"


#----------------------------------------------------------#
#             optimize mysql (max_connections)             #
#----------------------------------------------------------#

# we can only calculate max_connections after we modify all other settings
# highly inspired from: https://github.com/BMDan/tuning-primer.sh/blob/master/tuning-primer.sh
# https://lintechops.com/how-to-calculate-mysql-max_connections/
# Systems with 16G RAM or higher max_connections=1000 is a good idea. https://www.percona.com/blog/2013/11/28/mysql-error-too-many-connections/

mysql_config_file='/etc/mysql/my.cnf'

mysql_variable () {
  MYSQL_COMMAND="mysql"
  local variable=$($MYSQL_COMMAND -Bse "show variables like $1" | awk '{ print $2 }')
  export "$2"=$variable
}

#calculate global_buffers
mysql_variable \'innodb_buffer_pool_size\' innodb_buffer_pool_size
if [ -z $innodb_buffer_pool_size ] ; then
innodb_buffer_pool_size=0
fi
mysql_variable \'innodb_additional_mem_pool_size\' innodb_additional_mem_pool_size
if [ -z $innodb_additional_mem_pool_size ] ; then
innodb_additional_mem_pool_size=0
fi
mysql_variable \'innodb_log_buffer_size\' innodb_log_buffer_size
if [ -z $innodb_log_buffer_size ] ; then
innodb_log_buffer_size=0
fi
mysql_variable \'key_buffer_size\' key_buffer_size
mysql_variable \'query_cache_size\' query_cache_size
if [ -z $query_cache_size ] ; then
query_cache_size=0
fi
global_buffers=$(echo "$innodb_buffer_pool_size+$innodb_additional_mem_pool_size+$innodb_log_buffer_size+$key_buffer_size+$query_cache_size" | bc -l)

#calculate thread_buffers (without max_connections)
export major_version=$($MYSQL_COMMAND -Bse "SELECT SUBSTRING_INDEX(VERSION(), '.', +2)")
mysql_variable \'read_buffer_size\' read_buffer_size
mysql_variable \'read_rnd_buffer_size\' read_rnd_buffer_size
mysql_variable \'sort_buffer_size\' sort_buffer_size
mysql_variable \'thread_stack\' thread_stack
#mysql_variable \'max_connections\' max_connections
mysql_variable \'join_buffer_size\' join_buffer_size
mysql_variable \'tmp_table_size\' tmp_table_size
mysql_variable \'max_heap_table_size\' max_heap_table_size
mysql_variable \'log_bin\' log_bin
#mysql_status \'Max_used_connections\' max_used_connections
if [ "$major_version" = "3.23" ] ; then
        mysql_variable \'record_buffer\' read_buffer_size
        mysql_variable \'record_rnd_buffer\' read_rnd_buffer_size
        mysql_variable \'sort_buffer\' sort_buffer_size
fi
if [ "$log_bin" = "ON" ] ; then
        mysql_variable \'binlog_cache_size\' binlog_cache_size
else
        binlog_cache_size=0
fi
if [ $max_heap_table_size -le $tmp_table_size ] ; then
        effective_tmp_table_size=$max_heap_table_size
else
        effective_tmp_table_size=$tmp_table_size
fi
per_thread_buffers=$(echo "($read_buffer_size+$read_rnd_buffer_size+$sort_buffer_size+$thread_stack+$join_buffer_size+$binlog_cache_size)" | bc -l)

#available_memory_for_mysql_max_connections
export available_memory_for_mysql_max_connections=$( calc $real_available_memory_kb*1024 )  #get available server ram (in bytes)

#rough calculation should be (2GB = max_connections 100) (4GB = max_connections 200)
# For calculation, its better not to set this to lower than 90% $available_memory_for_mysql_max_connections. Because if its lower than 90%, sometimes the max_connection calculation is wrong, because not enough available memory for even 1 per_thread_buffers. If we use 100%, maybe its too high, much higher than rough calculation
# we have tested it with 100% $available_memory_for_mysql_max_connections, and load test it until max. Works without an issue. But still we recommend to keep it at 90% for the sweet spot
#calculate max_connections (50-70% of real max_connections is recommended so we not use too much memory. especially server with shared system)
max_connections=$(echo "($available_memory_for_mysql_max_connections-$global_buffers)/$per_thread_buffers" | bc -l)
max_connections=$(echo "50 / 100 * $max_connections" | bc -l)
max_connections=$( round $max_connections )

#updating max_connections setting
sed -i -e '/max_connections/s/.*//' $mysql_config_file
sed -i -e "/\[mysqld\]/a max_connections = $max_connections" $mysql_config_file

#restart mariadb 
sudo systemctl restart mariadb

#if its even lower than 'my-small.cnf', maybe the calculation is wrong 
if [ $max_connections > 29 ]; then
  greentext "Optimized mysql max_connections"
else
  redtext "Maybe we failed to optimize mysql max_connections, please check max_connections value by comparing the value with rough calculation value"
fi

#----------------------------------------------------------#
#      optimizing nginx (add rate-limited template)        #
#----------------------------------------------------------#

# Add rate_limit zone (rate limit based on request/second for now we dont need to do ratelimit based on connection 'limit_conn'),inspired from: https://github.com/myvesta/vesta/blob/master/src/deb/for-download/tools/rate-limit-tpl/install_rate_limit_tpl.sh
# 4reqs/sec is enough. source: https://www.wordfence.com/help/firewall/rate-limiting/
# its perfectly fine to have multiple 'limit_req_zone', maybe we should remove 'limit_req_zone' check?
rate_limit_zone_added=0
grepc=$(grep -c 'limit_req_zone' /etc/nginx/nginx.conf)
if [ "$grepc" -eq 0 ]; then

    #add limit_req settings
    sed -i 's|server_names_hash_bucket_size   512;|server_names_hash_bucket_size   512;\n    limit_req_log_level error;\n    limit_req_status 429;|g' /etc/nginx/nginx.conf

    #add limit_req zone 'login'
    sed -i 's|server_names_hash_bucket_size   512;|server_names_hash_bucket_size   512;\n    limit_req_zone $binary_remote_addr zone=req_limit_per_ip_login:10m rate=1r/s;|g' /etc/nginx/nginx.conf

    #add limit_req zone 'one'
    sed -i 's|server_names_hash_bucket_size   512;|server_names_hash_bucket_size   512;\n    limit_req_zone $binary_remote_addr zone=req_limit_per_ip_one:10m rate=5r/s;|g' /etc/nginx/nginx.conf

    #add limit_req zone 'global' (we shouldnt do this, because all static files will gets limited as well)
    #sed -i 's|server_names_hash_bucket_size   512;|server_names_hash_bucket_size   512;\n    limit_req_zone $binary_remote_addr zone=req_limit_per_ip_global:10m rate=10r/s;\n    limit_req zone=req_limit_per_ip_global burst=20;|g' /etc/nginx/nginx.conf

    rate_limit_zone_added=1
    greentext "Added limit_req_zone to nginx.conf"
else
    redtext "Fail adding limit_req_zone to nginx.conf"
fi

#download 'default-rate-limited-one' template
if [ "$rate_limit_zone_added" -eq 1 ]; then
    curl -o ${XPANEL}data/templates/web/nginx/default-rate-limited-one.stpl https://raw.githubusercontent.com/erikdemarco/gists/main/HestiaCP-Improved/tools/nginx-templates/default-rate-limited-one.stpl
    curl -o ${XPANEL}data/templates/web/nginx/default-rate-limited-one.tpl https://raw.githubusercontent.com/erikdemarco/gists/main/HestiaCP-Improved/tools/nginx-templates/default-rate-limited-one.tpl
    greentext "Added 'limit_req' to location block in 'default-rate-limited-one' template"
fi

#restart nginx
sudo systemctl restart nginx


#----------------------------------------------------------------#
# optimizing nginx (add wordpress caching rate-limited template) #
#----------------------------------------------------------------#

#download 'caching-wordpress-rate-limited-one' template
if [ "$rate_limit_zone_added" -eq 1 ]; then
    cp ${XPANEL}data/templates/web/nginx/caching.sh ${XPANEL}data/templates/web/nginx/caching-wordpress-rate-limited-one.sh && chmod 755 ${XPANEL}data/templates/web/nginx/caching-wordpress-rate-limited-one.sh	#make sure its executable
    #curl -o ${XPANEL}data/templates/web/nginx/caching-wordpress-rate-limited-one.sh https://raw.githubusercontent.com/erikdemarco/gists/main/HestiaCP-Improved/tools/nginx-templates/caching-wordpress-rate-limited-one.sh && chmod 755 ${XPANEL}data/templates/web/nginx/caching-wordpress-rate-limited-one.sh	#make sure its executable and cache levels still "2", if its differs than hestiacp it will show "cache had previously different levels"
    curl -o ${XPANEL}data/templates/web/nginx/caching-wordpress-rate-limited-one.stpl https://raw.githubusercontent.com/erikdemarco/gists/main/HestiaCP-Improved/tools/nginx-templates/caching-wordpress-rate-limited-one.stpl
    curl -o ${XPANEL}data/templates/web/nginx/caching-wordpress-rate-limited-one.tpl https://raw.githubusercontent.com/erikdemarco/gists/main/HestiaCP-Improved/tools/nginx-templates/caching-wordpress-rate-limited-one.tpl
    greentext "Added 'caching-wordpress-rate-limited-one' nginx template"
else
    redtext "Fail adding 'caching-wordpress-rate-limited-one' nginx template"
fi

# fix "purge cache" button to show if template name contains 'caching', instead of just show only if template named 'caching'
word_to_find="\$v_proxy_template == 'caching'"
word_to_replace="strpos(\$v_proxy_template, 'caching') !== false"
sed -i -e "s/$word_to_find/$word_to_replace/g" ${XPANEL}web/templates/pages/edit_web.html
word_to_find="select.val() != 'caching'"
word_to_replace="select.val().includes('caching') == false"
sed -i -e "s/$word_to_find/$word_to_replace/g" ${XPANEL}web/js/pages/edit_web.js

#restart nginx
sudo systemctl restart nginx


#----------------------------------------------------------#
#      optimizing nginx (autoupdate cloudflare ips)        #
#----------------------------------------------------------#

# Install cloudflare ips updater script
curl -o ${XPANEL}bin/cloudflare-update-ip-ranges.sh https://raw.githubusercontent.com/erikdemarco/gists/main/HestiaCP-Improved/cloudflare-update-ip-ranges.sh
chmod 755 ${XPANEL}bin/cloudflare-update-ip-ranges.sh
${XPANEL}bin/cloudflare-update-ip-ranges.sh

# Remove hestiacp cloudflare list, so we can use our list
sed -i -e '/set_real_ip_from/d' /etc/nginx/nginx.conf
sed -i -e '/real_ip_header/d' /etc/nginx/nginx.conf
sed -i -e '/https:\/\/www.cloudflare.com\/ips/s/.*/    #Hestiacp cloudflare ips deleted#/' /etc/nginx/nginx.conf

# Include the generated 'cloudflare-ips.conf' in nginx.conf
sed -i -e '/\/etc\/nginx\/conf.d\/\*.conf/i\    include /etc/nginx/cloudflare-ips.conf;' /etc/nginx/nginx.conf

# Add weekly cron to update 'cloudflare-ips.conf'
${XPANEL}bin/v-add-cron-job admin '0' '4' '*' '*' '0'  "sudo ${XPANEL}bin/cloudflare-update-ip-ranges.sh"

greentext "Added script to autoupdate cloudflare ips"

#restart nginx
sudo systemctl restart nginx

#----------------------------------------------------------#
#      		optimizing nginx (etc)        		   #
#----------------------------------------------------------#

# Respect existing headers & others
# https://www.nginx.com/blog/nginx-caching-guide/
# 'proxy_cache_use_stale' use this instead: https://www.nginx.com/resources/wiki/start/topics/examples/reverseproxycachingexample/
# 'proxy_ignore_headers' do not ignore 'control-cache' make it respect existing headers: http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_ignore_headers
# https://forum.nginx.org/read.php?2,2450,273132
# if you want to change the proxy_cache_path, its better to also change proxy_cache_path in 'hestiacp/install/deb/templates/web/nginx/caching.sh'
# proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=cache:10m inactive=60m max_size=1024m;
sed -i -e '/proxy_cache_use_stale /s/.*/    proxy_cache_use_stale  error timeout invalid_header updating http_500 http_502 http_503 http_504;/' /etc/nginx/nginx.conf
sed -i -e 's/proxy_ignore_headers /#&/' /etc/nginx/nginx.conf
sed -i -e '/proxy_cache_valid /s/.*/    proxy_cache_valid 200 1d;/' /etc/nginx/nginx.conf

# bugfix wordpress www to non-www redirect loop (proxy_cache_key / fastcgi_cache_key)
# use '$host' instead of '$proxy_host', because if we use '$proxy_host' it will not differentiate the http_host, thus causing infinite loop
# https://www.nginx.com/blog/9-tips-for-improving-wordpress-performance-with-nginx/
# https://wordpress.org/support/article/nginx/
sed -i -e '/proxy_cache_key /s/.*/    proxy_cache_key "$scheme$request_method$host$request_uri";/' /etc/nginx/nginx.conf

#restart nginx
sudo systemctl restart nginx

#----------------------------------------------------------#
#      		optimizing named   			   #
#----------------------------------------------------------#

# Notes:
# -) This will make any domain which enabled dns, will resolve internally. Resulting much better performance when dealing with internal domain
# -) Named require ~250mb of memory
# -) Based on our recent internat testing, ts not differ much in term of speed between using named or not

# Alternative:
# -) editing '/etc/hosts' will fail. Because php/curl ignore this file
# -) editing '/etc/dhcp/dhclient.conf' or '/etc/network/interfaces' will fail because hestiacp doenst use 'dhclient' nor 'ifup'
# -) editing '/etc/systemd/resolved.conf' with ReadEtcHosts=yes also fail

# Source:
# -) https://stackoverflow.com/a/22592801/15185328
# -) https://stackoverflow.com/a/26759734/15185328
# -) ubuntu uses systemd-resolved as default dns resolver since v17 needs to watch if this changed in the future release https://askubuntu.com/a/1001295
# -) https://askubuntu.com/a/973025
# -) https://www.linuxbabe.com/ubuntu/set-up-local-dns-resolver-ubuntu-18-04-16-04-bind9
# -) https://notes.enovision.net/linux/changing-dns-with-resolve
# -) https://www.shells.com/l/en-US/tutorial/Install-a-local-DNS-resolver-on-Ubuntu-20-04
# -) https://unix.stackexchange.com/a/527581
 

# Check if named is installed
if ! [ -x "$(command -v named)" ]; then
    is_named_installed='no'
else
    is_named_installed='yes'
fi


if [ "$is_named_installed" == "yes" ]; then


    # add localhost as first priority of dns resolver, bail if its already set
    grepc=$(grep -c '^DNS=' /etc/systemd/resolved.conf)
    if [ "$grepc" -eq 0 ]; then
        sed -i -e 's/^DNS=.*/#DNS=/' /etc/systemd/resolved.conf
        echo 'DNS=127.0.0.1' >> /etc/systemd/resolved.conf
        sudo systemctl restart systemd-resolved
    fi


    # make dns can only be accessed from localhost
    #add rule
    sed  -i -e "/'53'/ s|0.0.0.0/0|127.0.0.1|" ${XPANEL}data/firewall/rules.conf
    #update firewall then restart hestia
    ${XPANEL}bin/v-update-firewall
    service $xpanelname restart
    

    # Check if systemd-resolved (check resolvectl) is installed
    if ! [ -x "$(command -v resolvectl)" ]; then
        is_resolvectl_installed='no'
    else
        is_resolvectl_installed='yes'
    fi


    #check if we use localhost for dns
    if [ "$is_resolvectl_installed" == "yes" ]; then

        grepc=$(resolvectl status | grep -c '127.0.0.1')
        if [ "$grepc" -eq 0 ]; then
            echo 'Not using localhost as DNS'
        redtext "Not using localhost as DNS, All local domain will be resolved using external DNS resulting poor performance!"
        fi

    fi


    # add monit 'named' config, note: the correct is '/var/run/named/named.pid' not '/var/run/named.pid' if not correct it will cause failed start
    echo 'check process named with pidfile /var/run/named/named.pid
        start program = "/etc/init.d/named start"
        stop program  = "/etc/init.d/named stop"
        if failed port 53 type tcp protocol dns then restart
        if failed port 53 type udp protocol dns then restart
        if 5 restarts within 5 cycles then timeout' >> /etc/monit/conf.d/custom.conf
    sudo service monit restart
    sudo monit start all


fi




#----------------------------------------------------------#
#         Install additional app: redis-server             #
#----------------------------------------------------------#

if [ $vAddRedisServer == "y" ] || [ $vAddRedisServer == "Y" ]; then

    #install redis (automatically make it accessable only from localhost)
    sudo apt install -y redis-server

    #redis config: maxmemory-policy using lfu: https://redis.io/topics/lru-cache
    sed -i -e "s/^# maxmemory-policy .*/maxmemory-policy allkeys-lfu/" /etc/redis/redis.conf

    #redis config: its important to set timemut, because redis defualt is set to  0, meaning it will wait forever: https://blog.opstree.com/2019/04/16/redis-best-practices-and-performance-tuning/
    #we dont need this because we are protected by 'tcp-keepalive' setting. https://rtfm.co.ua/en/draft-eng-redis-main-configuration-parameters-and-performance-tuning-overview/
    #sed -i -e "s/^timeout 0.*/timeout 300/" /etc/redis/redis.conf

    #redis config: maxmemory  
    export redis_max_memory_value=$( calc $memory_allocated_for_redis_server_kb/1024 ) #(in mb)
    redis_max_memory_value=$( round $redis_max_memory_value )
    redis_max_memory_value_text="${redis_max_memory_value}mb"
    sed -i -e "s/^# maxmemory .*/maxmemory $redis_max_memory_value_text/" /etc/redis/redis.conf
    
    # redis config: unixsocket
    # https://mummila.net/nuudelisoppa/2018/04/20/switching-redis-from-tcp-port-to-unix-socket-in-ubuntu-16-04-with-nextcloud-running-under-apache/
    # https://gulchuk.com/blog/how-to-connect-to-redis-by-unix-socket-only
    # https://guides.wp-bullet.com/how-to-configure-redis-to-use-unix-socket-speed-boost/
    # https://wordpress.org/support/topic/redis-socket-support-3/
    # based on our in house very intensive load test, there is no performance advantage between socket and ip. not even a slight. So we turn it off for now
    #sudo mkdir -p /run/redis/	#create redis dir in 'run' if not exist
    #sed -i -e "s/^# unixsocket .*/unixsocket \/run\/redis\/redis.sock/" /etc/redis/redis.conf
    #sed -i -e "s/^# unixsocketperm .*/unixsocketperm 777/" /etc/redis/redis.conf	#will not run if we set lower than '777', because we dont set redis as the owner of redis.sock
    ##sed -i -e "s/^port 6379.*/port 0/" /etc/redis/redis.conf	#if you dont need to connect redis via TCP anymore, you can disable listening the TCP here

    # remove warning from /var/log/redis/redis-server.log
    # note: 'madvise' more saver than 'never' https://github.com/redis/redis/issues/3895 | https://www.nginx.com/blog/optimizing-web-servers-for-high-throughput-and-low-latency/
    sysctl vm.overcommit_memory=1   #instant effect 
    echo 'vm.overcommit_memory = 1' >> /etc/sysctl.conf #persist after reboot
    echo madvise > /sys/kernel/mm/transparent_hugepage/enabled    #instant effect 
    sudo apt install -y sysfsutils && echo 'kernel/mm/transparent_hugepage/enabled = madvise' >> /etc/sysfs.conf  #persist after reboot. we tried to use rc.local and crontab with no succes, maybe because redis start earlier than those. we use sysfs instead. https://askubuntu.com/questions/597372/how-do-i-modify-sys-kernel-mm-transparent-hugepage-enabled

    #restart redis
    sudo systemctl restart redis-server
    
    #check redis installation
    check_result $? 'install redis-server'

    # add monit 'redis' config
    echo 'check process redis with pidfile  /var/run/redis/redis-server.pid
        start program = "/bin/systemctl start redis-server"
        stop program = "/bin/systemctl stop redis-server"
        if failed port 6379 protocol redis then restart
        if 5 restarts within 5 cycles then timeout' >> /etc/monit/conf.d/custom.conf
    sudo service monit restart
    sudo monit start all

fi



#----------------------------------------------------------#
#               Disable shell login for admin              #
#----------------------------------------------------------#

greentext "disabling shell login for admin..."
${XPANEL}bin/v-change-user-shell admin nologin



#----------------------------------------------------------#
#                 Protect Admin panel                      #
#----------------------------------------------------------#

#make hestia admin panel accessible only for localhost (use ssh tunnel to access it from anywhere something like "ssh user@server -L8083:localhost:8083")


if [ $vProtectAdminPanel == "y" ] || [ $vProtectAdminPanel == "Y" ]; then

    greentext "making admin panel, mysql, phpmyadmin only accessible from localhost..."

    #admin panel
    sed -i -e "/$vPort/ s|0.0.0.0/0|127.0.0.1|" ${XPANEL}data/firewall/rules.conf
    ## OR USE THIS, but if the id is changing it wont work ## ${XPANEL}bin/v-change-firewall-rule 2 ACCEPT 127.0.0.1 8083 TCP HestiaAdmin && service hestia restart

    #mysql (vesta)
    #sed -i -e '/3306/ s|0.0.0.0/0|127.0.0.1|' ${XPANEL}data/firewall/rules.conf

    #mysql (hestia)
    #echo "RULE='11' ACTION='ACCEPT' PROTOCOL='TCP' PORT='3306,5432' IP='127.0.0.1' COMMENT='DB' SUSPENDED='no' TIME='07:40:16' DATE='2014-05-25'" >> /usr/local/hestia/data/firewall/rules.conf
    echo "RULE='11' ACTION='ACCEPT' PROTOCOL='TCP' PORT='3306,5432' IP='127.0.0.1' COMMENT='DB' SUSPENDED='no' TIME='07:40:16' DATE='2014-05-25'" >> ${XPANEL}data/firewall/rules.conf

    #update firewall then restart hestia
    ${XPANEL}bin/v-update-firewall
    service $xpanelname restart

    #fail2ban remove watching admin panel its useless because it can only be accessible from localhost
    sed -i -e '/\['"$xpanelname"'-iptables\]/!b;n;cenabled = false' /etc/fail2ban/jail.local  # ';n' change next 1line after match 
    service fail2ban restart 

    #phpmyadmin
    #note: must start with newline if not it will complain"<Directory> directive missing closing '>'"
    echo '
<Directory /usr/share/phpmyadmin>
    Require local
</Directory>' >> /etc/apache2/conf.d/phpmyadmin.conf
    service apache2 restart



fi



#----------------------------------------------------------#
#                      dropbox backup                      #
#----------------------------------------------------------#



if [ $vDropboxUploader == "y" ] || [ $vDropboxUploader == "Y" ]; then
  ##Automate backup to dropbox (START)
  
  #only continue if dropbox-uploader already installed
  if [ -e "/dropbox/dropbox_uploader.sh" ]
  then
  
    greentext "installing dropbox backup..."
    
    #download the cron file (vestacp)
    #curl -o dropbox-auto-backup-cron-hestia.sh https://gist.githubusercontent.com/erikdemarco/959e3afc29122634631e59d3e3640333/raw/f58557e0ab474eedd480e145e499de584eed6293/dropbox_auto_backup_cron.sh

    #download the cron file (hestiacp)
    curl -o dropbox-auto-backup-cron-hestia.sh https://raw.githubusercontent.com/erikdemarco/gists/main/HestiaCP-Improved/dropbox-auto-backup-cron-hestia.sh

    #move the cron file for accessiblity & chmod it
    mv dropbox-auto-backup-cron-hestia.sh ${XPANEL}bin/
    chmod 755 ${XPANEL}bin/dropbox-auto-backup-cron-hestia.sh 
    
    #daily cron (make backup) at 05.10 (add cron job if there is not yet added)
    if [ -z "$(grep v-backup-users ${HESTIA}data/users/admin/cron.conf)" ]; then
        ${XPANEL}bin/v-add-cron-job admin '10' '05' '*' '*' '*'  "sudo ${XPANEL}bin/v-backup-users"
    fi

    #daily cron (upload to dropbox) at 06.10
    ${XPANEL}bin/v-add-cron-job admin '10' '06' '*' '*' '*'  "sudo ${XPANEL}bin/dropbox-auto-backup-cron-hestia.sh"
    
  else
    redtext "Error: dropbox-uploader is not installed yet!"
  fi

  ##Automate backup to dropbox (END)
fi


#----------------------------------------------------------#
#              additional steps for hestiacp               #
#----------------------------------------------------------#

#make 'backup' folder, sometimes its not added by default
mkdir -p "/backup"

#disable auto-update, sometimes autoupdate crashing our site (dont try this if your panel is not protected), we need to do full update of cp every couple years to keep system crisp
${XPANEL}bin/v-delete-cron-hestia-autoupdate

#remove file-manager, to minimize bug/security issue. you can still use sftp.
if [ -e "${XPANEL}web/fm" ]; then
    ${XPANEL}bin/v-delete-sys-filemanager
fi



#----------------------------------------------------------#
#                          Done                            #
#----------------------------------------------------------#

#done
echo "Done!";
echo " ";
echo "You can access $xpanelname here: https://$vIPAddress:$vPort/";
echo "Username: admin";
echo "Password: $vPassword";
echo " ";
echo " ";
echo "PLEASE REBOOT THE SERVER ONCE YOU HAVE COPIED THE DETAILS ABOVE.";

#reboot
read -r -p "Do you want to reboot now? [y/N] " vReboot
if [ $vReboot == "y" ] || [ $vReboot == "Y" ]; then
  reboot
fi
