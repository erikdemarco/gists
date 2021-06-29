#!/bin/sh



#----------------------------------------------------------#
#                  upgrade system                               #
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


#get info
memory=$(grep 'MemTotal' /proc/meminfo |tr ' ' '\n' |grep [0-9])  #get current server ram size (in K)
vIPAddress=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')

read -r -p "What e-mail address would you like to receive VestaCP alerts to? " vEmail
read -r -p "Please type your server hostname, or press enter to use default: " vHostname
read -r -p "Which port do you want the panel can be accessed from? or press enter to use default: " vPort
read -r -p "Please type a password to use with VestaCP: " vPassword
read -r -p "Please type timezone of your server (example: Asia/Jakarta) or press enter to use default: " vTimezone
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

if [ $vAddSsh == "y" ] || [ $vAddSsh == "Y" ]; then
  read -r -p "Please input your public SSH Key: " vSshKey
fi

read -r -p "Do you want to make admin panel, mysql, and phpmyadmin accesible to localhost only (you can still access admin panel using SSH tunnel)? [y/N] " vProtectAdminPanel

read -r -p "Do you want to automated backup to dropbox weekly? (needs dropbox access token) [y/N] " vDropboxUploader
if [ $vDropboxUploader == "y" ] || [ $vDropboxUploader == "Y" ]; then
  read -r -p "Please input your dropbox Generated access token: " vDropboxUploaderKey
fi


vAddString="-r $vPort -s $vHostname -e $vEmail -p $vPassword"




#----------------------------------------------------------#
#                   install vestacp                        #
#----------------------------------------------------------#


curl -O https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh

#apache+nginx+phpfpm
echo "Y" | bash hst-install.sh -a yes -n yes -w yes -o no -v no -j no -k no  -m yes -g no -x no -z no -c no -t no -i yes -b yes -q no -d no -l en -y yes $vAddString -force



#----------------------------------------------------------#
#                   needed variable                        #
#----------------------------------------------------------#

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
echo -n > /home/admin/web/$servername/public_shtml/index.html

#change default page template for future use
echo -n > ${XPANEL}data/templates/web/skel/public_html/index.html
echo -n > ${XPANEL}data/templates/web/skel/public_shtml/index.html



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


#deactivate 'open_basedir' line from the 'default' template
sed -i -e '/open_basedir/s/.*/#deleted#/' ${XPANEL}data/templates/web/apache2/default.stpl
sed -i -e '/open_basedir/s/.*/#deleted#/' ${XPANEL}data/templates/web/apache2/default.tpl


#----------------------------------------------------------#
#                   optimize httpd                         #
#----------------------------------------------------------#

greentext "optimizing httpd..."

httpd_optimized_setting="\n
\n#OPTIMIZED APACHE Setting#
\n
\n#hide apache version
\nServerSignature Off
\nServerTokens Prod
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
echo 'check program check-iptables-status with path /usr/local/bin/check-iptables-status.sh
      if status != 1 then exec "${XPANEL}bin/v-update-firewall"' >> /etc/monit/conf.d/custom.conf  #add monit rule
      
      
   
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
#               	optimizing php                     #
#----------------------------------------------------------#

greentext "optimizing php..."

for pconf in $(find /etc/php* -name php.ini); do

    #inspired from https://www.hostgator.com/help/article/php-settings-that-cannot-be-changed

    #Disable php dangerous functions
    sed -i -e 's/disable_functions =/disable_functions = exec,passthru,shell_exec,system/g' $pconf

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


#php soap
sudo apt-get install php${phpversion_short}-soap
#addextension line to php.ini if its not yet activated automatically
#sed -i -e '/extension=bz2/a extension=soap' /etc/php/${phpversion_short}/cli/php.ini		

#restart apache 
sudo systemctl restart apache2 



#----------------------------------------------------------#
#                  optimize mysql                    	   #
#----------------------------------------------------------#

# http://mysql.rjweb.org/doc.php/ricksrots
# https://haydenjames.io/mysql-server-has-gone-away-error-solutions/
# https://mariadb.com/kb/en/mariadb-memory-allocation/
# set innodb_log_file_size to 20% of innodb_buffer_pool_size (becasue the default innodb_log_files_in_group=2 we need to divide by 2, so for the recomended 25%, we use 12%)
# innodb_log_file_size max 256M Especially on a system with a lot of writes to InnoDB tables you should set innodb_log_file_size to 25% of innodb_buffer_pool_size. However the bigger this value, the longer the recovery time will be when database crashes, so this value should not be set much higher than 256 MiB. Please note however that you cannot simply change the value of this variable. You need to shutdown the server, remove the InnoDB log files, set the new value in my.cnf, start the server, then check the error logs if everything went fine. See also this blog entry 
# If only using InnoDB, set innodb_buffer_pool_size to 70% of available RAM. (Plus key_buffer_size = 10M, small, but not zero.)
# If only using MyISAM, set key_buffer_size to 20% of available RAM. (Plus innodb_buffer_pool_size=0)
# 
# TODO: Set tmp_table_size and max_heap_table_size to about 1% of RAM. 


mysql_config_file='/etc/mysql/my.cnf'

innodb_buffer_pool_size_value=$( calc 70/100*$memory )
innodb_buffer_pool_size_value=$( round $innodb_buffer_pool_size_value )
innodb_buffer_pool_size_value_text="${innodb_buffer_pool_size_value}K"

#key_buffer_size_value=$( calc 20/100*$memory )
#key_buffer_size_value=$( round $key_buffer_size_value )
#key_buffer_size_value_text="${key_buffer_size_value}K"

innodb_log_files_in_group_value=2
innodb_log_file_size_value=$( calc 25/100*$innodb_buffer_pool_size_value )
innodb_log_file_size_value=$( calc $innodb_log_file_size_value/$innodb_log_files_in_group_value )
innodb_log_file_size_value=$( round $innodb_log_file_size_value )
innodb_log_file_size_value_text="${innodb_log_file_size_value}K"
    if [ $innodb_log_file_size_value -gt 256000 ]; then
        innodb_log_file_size_value_text="256M"
    fi

#remove line containing matched config
sed -i -e '/query_cache_type/s/.*//' $mysql_config_file
sed -i -e '/query_cache_size/s/.*//' $mysql_config_file
sed -i -e '/innodb_buffer_pool_size/s/.*//' $mysql_config_file
sed -i -e '/key_buffer_size/s/.*//' $mysql_config_file
sed -i -e '/innodb_log_file_size/s/.*//' $mysql_config_file
sed -i -e '/innodb_log_files_in_group/s/.*//' $mysql_config_file

#add config after [mysqld]
sed -i -e '/\[mysqld\]/a query_cache_type = 0' $mysql_config_file
sed -i -e '/\[mysqld\]/a query_cache_size = 0' $mysql_config_file
sed -i -e "/\[mysqld\]/a innodb_buffer_pool_size = $innodb_buffer_pool_size_value_text" $mysql_config_file
#sed -i -e "/\[mysqld\]/a key_buffer_size = $key_buffer_size_value_text" $mysql_config_file
sed -i -e '/\[mysqld\]/a key_buffer_size = 10M' $mysql_config_file
sed -i -e "/\[mysqld\]/a innodb_log_file_size = $innodb_log_file_size_value_text" $mysql_config_file
sed -i -e "/\[mysqld\]/a innodb_log_files_in_group = $innodb_log_files_in_group_value" $mysql_config_file

#restart mariadb 
sudo systemctl restart mariadb


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

    #add limit_req zone 'one'
    sed -i 's|server_names_hash_bucket_size   512;|server_names_hash_bucket_size   512;\n    limit_req_zone $binary_remote_addr zone=req_limit_per_ip_one:10m rate=5r/s;|g' /etc/nginx/nginx.conf

    #add limit_req zone 'global' (we shouldnt do this, because all static files will gets limited as well)
    #sed -i 's|server_names_hash_bucket_size   512;|server_names_hash_bucket_size   512;\n    limit_req_zone $binary_remote_addr zone=req_limit_per_ip_global:10m rate=10r/s;\n    limit_req zone=req_limit_per_ip_global burst=20;|g' /etc/nginx/nginx.conf

    rate_limit_zone_added=1
    echo "=== Added limit_req_zone to nginx.conf"

fi

#download 'default-rate-limited-one' template
if [ "$rate_limit_zone_added" -eq 1 ]; then
    curl -o ${XPANEL}data/templates/web/nginx/default-rate-limited-one.stpl https://raw.githubusercontent.com/erikdemarco/gists/main/HestiaCP-Improved/tools/nginx-templates/default-rate-limited-one.stpl
    curl -o ${XPANEL}data/templates/web/nginx/default-rate-limited-one.tpl https://raw.githubusercontent.com/erikdemarco/gists/main/HestiaCP-Improved/tools/nginx-templates/default-rate-limited-one.tpl
    echo "=== Added 'limit_req' to location block in 'default-rate-limited-one' template"
fi

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

#restart nginx
sudo systemctl restart nginx


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
    echo "RULE='11' ACTION='ACCEPT' PROTOCOL='TCP' PORT='3306,5432' IP='127.0.0.1' COMMENT='DB' SUSPENDED='no' TIME='07:40:16' DATE='2014-05-25'" >> /usr/local/hestia/data/firewall/rules.conf


    #update firewall then restart hestia
    ${XPANEL}bin/v-update-firewall
    service $xpanelname restart

    #fail2ban remove watching admin panel its useless because it can only be accessible from localhost
    sed -i -e '/\['"$xpanelname"'-iptables\]/!b;n;cenabled = false' /etc/fail2ban/jail.local  # ';n' change next 1line after match 
    service fail2ban restart 

    #phpmyadmin
    sed -i -e '/<Directory \/usr\/share\/phpmyadmin>/a AllowOverride All' /etc/phpmyadmin/apache.conf
    echo '<RequireAll>
    Require local
    </RequireAll>' > /usr/share/phpmyadmin/.htaccess
    service apache2 restart



fi



#----------------------------------------------------------#
#                      dropbox backup                      #
#----------------------------------------------------------#



if [ $vDropboxUploader == "y" ] || [ $vDropboxUploader == "Y" ]; then
  ##Automate backup to dropbox (START)
  
  greentext "installing dropbox backup..."

  #get the dropbox uploader api
  cd /  #cd to main dir
  mkdir dropbox
  cd dropbox
  curl "https://raw.githubusercontent.com/andreafabrizi/Dropbox-Uploader/master/dropbox_uploader.sh" -o dropbox_uploader.sh
  chmod 755 dropbox_uploader.sh
  echo "$vDropboxUploaderKey
  y" | ./dropbox_uploader.sh

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
