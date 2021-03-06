#!/bin/bash

# Source:
# https://gist.github.com/AidasK/27aa5d6f918eca12d95427178b5aaa59
# https://marekbosman.com/site/automatic-update-of-cloudflare-ip-addresses-in-nginx/

# Location of the nginx config file that contains the CloudFlare IP addresses.
CF_NGINX_CONFIG="/etc/nginx/cloudflare-ips.conf"

# The URLs with the actual IP addresses used by CloudFlare.
CF_URL_IP4="https://www.cloudflare.com/ips-v4"
CF_URL_IP6="https://www.cloudflare.com/ips-v6"

# Temporary files.
CF_TEMP_IP4="/tmp/cloudflare-ips-v4.txt"
CF_TEMP_IP6="/tmp/cloudflare-ips-v6.txt"

# Download the files.
if [ -f /usr/bin/curl ];
then
    curl --silent --output $CF_TEMP_IP4 $CF_URL_IP4
    curl --silent --output $CF_TEMP_IP6 $CF_URL_IP6
elif [ -f /usr/bin/wget ];
then
    wget --quiet --output-document=$CF_TEMP_IP4 --no-check-certificate $CF_URL_IP4
    wget --quiet --output-document=$CF_TEMP_IP6 --no-check-certificate $CF_URL_IP6
else
    echo "Unable to download CloudFlare files."
    exit 1
fi

# Generate the new config file.
echo "# CloudFlare IP Ranges" > $CF_NGINX_CONFIG
echo "# Generated at $(date) by $0" >> $CF_NGINX_CONFIG
echo "" >> $CF_NGINX_CONFIG

echo "# - IPv4 ($CF_URL_IP4)" >> $CF_NGINX_CONFIG
awk '{ print "set_real_ip_from " $0 ";" }' $CF_TEMP_IP4 >> $CF_NGINX_CONFIG
echo "" >> $CF_NGINX_CONFIG

echo "# - IPv6 ($CF_URL_IP6)" >> $CF_NGINX_CONFIG
awk '{ print "set_real_ip_from " $0 ";" }' $CF_TEMP_IP6 >> $CF_NGINX_CONFIG
echo "" >> $CF_NGINX_CONFIG

echo "real_ip_header CF-Connecting-IP;" >> $CF_NGINX_CONFIG
echo "" >> $CF_NGINX_CONFIG

# Remove the temporary files.
rm $CF_TEMP_IP4 $CF_TEMP_IP6

# Reload the nginx config.
service nginx reload
