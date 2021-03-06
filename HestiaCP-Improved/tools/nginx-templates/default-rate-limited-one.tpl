#=======================================================================#
# Default Web Domain Template                                           #
# DO NOT MODIFY THIS FILE! CHANGES WILL BE LOST WHEN REBUILDING DOMAINS #
#=======================================================================#

# Modified from: https://github.com/hestiacp/hestiacp/blob/main/install/deb/templates/web/nginx/default.tpl

server {
    listen      %ip%:%proxy_port%;
    server_name %domain_idn% %alias_idn%;

    #fix 'upstream sent too big header' sometimes happens during wp_logout
    proxy_buffer_size 8k;
    proxy_buffers 8 4k;
    proxy_busy_buffers_size 16k;

    include %home%/%user%/conf/web/%domain%/nginx.forcessl.conf*;

    location / {
        limit_req zone=req_limit_per_ip_one burst=20 nodelay;
        proxy_pass      http://%ip%:%web_port%;
    }

    location ~* ^.+\.(%proxy_extensions%)$ {
        root           %docroot%;
        access_log     /var/log/%web_system%/domains/%domain%.log combined;
        access_log     /var/log/%web_system%/domains/%domain%.bytes bytes;
        expires        30d;
        #try_files      $uri @fallback;
    }

    location /error/ {
        alias   %home%/%user%/web/%domain%/document_errors/;
    }

    location @fallback {
        proxy_pass      http://%ip%:%web_port%;
    }

    location ~ /\.ht    {return 404;}
    location ~ /\.svn/  {return 404;}
    location ~ /\.git/  {return 404;}
    location ~ /\.hg/   {return 404;}
    location ~ /\.bzr/  {return 404;}

    include %home%/%user%/conf/web/%domain%/nginx.conf_*;
}

