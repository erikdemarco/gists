Notes:<br>
-) burst is 2x zone rate, if zone rate is 4/r/s then burst should be 8<br>
-) Its important to add burst, if it doesnt exist, many request will be blocked, because browser usually open many request to open a page. read it here why: https://www.nginx.com/blog/rate-limiting-nginx/<br>
-) For most deployments, we recommend including the burst and nodelay parameters to the limit_req directive. https://www.nginx.com/blog/rate-limiting-nginx/<br>
-) 'proxy_extensions' location block should be outside '/' location block, if not it will also gets rate limited and break reguler browsing activity<br>
-) For static files: DON'T pass to Apache if it's not found by nginx (try_files). Update: But from our testing with random jpg files. The responsetime is no difference even with fallback to apache little bit faster. weird

NGINX limit setting inspirations:
-) https://www.nginx.com/blog/enterprise-grade-cloud-storage-nginx-plus-minio/
-) https://www.nginx.com/wp-content/uploads/2014/10/AWS_NGINX_Plus-whitepaper-final_v4.pdf
-) If its not enough next we can try set to rate=15r/s & burst=30

Benchmark rank for static files:
1. Fastest: #try_files      $uri @fallback;
2. Medium: try_files      $uri =404;
3. Slowest: try_files      $uri @fallback;

Notes caching template:
-) We want to add browser cache if cache status is HIT, but fail because of "if is evil". So its better to add this header via wordpress. Example code:
if ($upstream_cache_status = "HIT") {
    expires 1m;
} 

Note nginx tuning:
-) open_file_cache not effective (tested). Because its just a caching system for metadata operations (file mtime, file existence etc), not for file content.<br>
-) 'aio threads' not effective to increase performance (tested)
-) reuseport increase performance but cant be used in hestia because it can only be declared once to the same socket https://serverfault.com/questions/1000365/correct-way-to-use-reuseport-in-nginx-virtual-host
-) todo: keepalive 
https://stackoverflow.com/questions/46771389/why-does-nginx-proxy-pass-close-my-connection
https://ma.ttias.be/enable-keepalive-connections-in-nginx-upstream-proxy-configurations/
