Notes:<br>
-) burst is 2x zone rate, if zone rate is 4/r/s then burst should be 8<br>
-) Its important to add burst, if it doesnt exist, many request will be blocked, because browser usually open many request to open a page. read it here why: https://www.nginx.com/blog/rate-limiting-nginx/<br>
-) For most deployments, we recommend including the burst and nodelay parameters to the limit_req directive. https://www.nginx.com/blog/rate-limiting-nginx/<br>
-) 'proxy_extensions' location block should be outside '/' location block, if not it will also gets rate limited and break reguler browsing activity<br>
