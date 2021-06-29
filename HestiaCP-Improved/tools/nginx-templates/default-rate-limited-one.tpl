#=======================================================================#
# Default Web Domain Template                                           #
# DO NOT MODIFY THIS FILE! CHANGES WILL BE LOST WHEN REBUILDING DOMAINS #
#=======================================================================#

# Modified from: https://github.com/hestiacp/hestiacp/blob/main/install/deb/templates/web/nginx/default.tpl

server {
    listen      %ip%:%proxy_port%;
    server_name %domain_idn% %alias_idn%;
        
    include %home%/%user%/conf/web/%domain%/nginx.forcessl.conf*;

    location / {
        proxy_pass      http://%ip%:%web_port%;
        
        #add ratelimit only for php files (burst is 2x zone rate, if zone rate is 4/r/s then burst should be 8)
        location ~ .php$ {
            limit_req zone=req_limit_per_ip_one burst=8 nodelay;
            #proxy_pass      http://%ip%:%web_port%;
            try_files      $uri @fallback;
        }
        
        location ~* ^.+\.(%proxy_extensions%)$ {
            root           %docroot%;
            access_log     /var/log/%web_system%/domains/%domain%.log combined;
            access_log     /var/log/%web_system%/domains/%domain%.bytes bytes;
            expires        max;
            try_files      $uri @fallback;
        }
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
