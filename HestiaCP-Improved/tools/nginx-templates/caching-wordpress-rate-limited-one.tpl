#=======================================================================#
# Default Web Domain Template                                           #
# DO NOT MODIFY THIS FILE! CHANGES WILL BE LOST WHEN REBUILDING DOMAINS #
#=======================================================================#

server {
    listen      %ip%:%proxy_port%;
    server_name %domain_idn% %alias_idn%;
    

    # Tuning SSL (server block)
    # https://www.nginx.com/blog/10-tips-for-10x-application-performance/#Tip-5&nbsp;%E2%80%93-Optimize-SSL/TLS
    # https://www.nginx.com/blog/10-tips-for-10x-application-performance/#Tip-5&nbsp;%E2%80%93-Optimize-SSL/TLS
    # ssl_session_cache & ssl_session_timeout. for the timeout defualtis ok because the more it gets the more memory it needs. 1m can store 4000reqs
    # ssl_stapling. we dont need this if using CF, Full (no strict)? https://blog.cloudflare.com/ocsp-stapling-how-cloudflare-just-made-ssl-30/
    # ssl_session_cache shared:SSL:10m;     #hestiacp alreaady set this, we cant set it anymore
    ssl_session_timeout 5m;
    ssl_session_tickets on;
    
    # TUning TTFB (server block)
    # https://www.nginx.com/blog/7-tips-for-faster-http2-performance/
    # output_buffers default https://github.com/nginx/nginx/commit/a0d7df93a0188f79733351a7e7e8168b6fdf698e
    # proxy_buffers default. this will make rps more more higher, because it save a lot of memory, not spent too much memory for each page. ubuntu memory pagesize is 4k, so use 4k. average htmlsize according to https://httparchive.org/reports/page-weight#bytesHtml is 30k, so the optimum is 8*4k (nginx default). https://www.getpagespeed.com/server-setup/nginx/tuning-proxy_buffer_size-in-nginx, http://disq.us/p/1o6fcqc
    # ssl_buffer_size default. http://nginx.org/en/docs/http/ngx_http_ssl_module.html#ssl_buffer_size
    proxy_buffers 8 4k;
    output_buffers 2 32k;
    ssl_buffer_size 4k;
    
    include %home%/%user%/conf/web/%domain%/nginx.forcessl.conf*;

    location / {
    
        limit_req zone=req_limit_per_ip_one burst=10 nodelay;
        proxy_pass      http://%ip%:%web_port%;

        # Tuning RPS (server block)
        # https://www.nginx.com/blog/benefits-of-microcaching-nginx/amp/
        # https://nginx.org/en/docs/http/ngx_http_log_module.html#access_log
        # https://medium.com/staqu-dev-logs/optimizations-tuning-nginx-for-better-rps-of-an-http-api-de2a0919744a
        # https://loadforge.com/guides/high-performance-nginx
        # worker_processes (main block) must be set to auto. so it will increase maxclient we can handle by the cpu core count. so 4core can handle approx 4096client/sec (worker_processes * worker_connections = max clients)
        access_log off;
        proxy_cache_lock on;

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
        add_header "X-Caching-Status" $upstream_cache_status;
        add_header "X-Caching-Skip" $skip_reason;

        proxy_cache %domain%;
        proxy_cache_valid 15m;
        proxy_cache_valid 404 1m;
        proxy_no_cache $no_cache;
        proxy_cache_bypass $no_cache;
        proxy_cache_bypass $cookie_session $http_x_update;

    }
    

    location ~* ^.+\.(%proxy_extentions%)$ {
        proxy_cache    off;
        root           %docroot%;
        access_log     off;
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
