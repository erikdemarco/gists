#=======================================================================#
# Default Web Domain Template                                           #
# DO NOT MODIFY THIS FILE! CHANGES WILL BE LOST WHEN REBUILDING DOMAINS #
#=======================================================================#

server {
    listen      %ip%:%proxy_port%;
    server_name %domain_idn% %alias_idn%;
        
    include %home%/%user%/conf/web/%domain%/nginx.forcessl.conf*;

    location / {
    
        limit_req zone=req_limit_per_ip_one burst=10 nodelay;
        proxy_pass      http://%ip%:%web_port%;

        # Cache bypass
        # https://wordpress.org/support/article/nginx/#nginx-fastcgi_cache
        # https://gridpane.com/kb/gridpane-default-cache-exclusions/
        set $skip_reason "";
        # POST requests and urls with a query string should always go to PHP
        if ($request_method = POST) {
            set $no_cache 1;
            set $skip_reason "${skip_reason}-POST";
        }
        # Don't cache any url that includes a query string
        if ($query_string != "") {
            set $no_cache 1;
            set $skip_reason "${skip_reason}-query_string";
        }   
        # Don't cache uris containing the following segments
        if ($request_uri ~* "(/wp-admin/|/xmlrpc.php|/wp-(app|cron|login|register|mail).php|wp-.*.php|/feed/|index.php|wp-comments-popup.php|wp-links-opml.php|wp-locations.php|sitemap(_index)?.xml|[a-z0-9_-]+-sitemap([0-9]+)?.xml)") {
            set $no_cache 1;
            set $skip_reason "${skip_reason}-request_uri";
        }   
        # Don't use the cache for logged in users or recent commenters
        if ($http_cookie ~* "comment_author|wordpress_[a-f0-9]+|wp-postpass|wordpress_no_cache|wordpress_logged_in") {
            set $no_cache 1;
            set $skip_reason "${skip_reason}-http_cookie";
        } 
        # Add cache status and skip cache reason to header
        add_header "X-WP-Cache" $upstream_cache_status;
        add_header "X-WP-Cache-Skip" $skip_reason;

        proxy_cache %domain%;
        proxy_cache_valid 15m;
        proxy_cache_valid 404 1m;
        proxy_no_cache $no_cache;
        proxy_cache_bypass $no_cache;
        proxy_cache_bypass $cookie_session $http_x_update;

    }
    

    location ~* ^.+\.(%proxy_extensions%)$ {
        proxy_cache    off;
        root           %docroot%;
        access_log     /var/log/%web_system%/domains/%domain%.log combined;
        access_log     /var/log/%web_system%/domains/%domain%.bytes bytes;
        expires        max;
        try_files      $uri @fallback;
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
