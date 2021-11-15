# kong-dnsbug-2
Test case to reproduce a bug in Kong 2.5.x related targets whose DNS lookup sometimes returns a TTL value of 0.  A TTL value of 0 confuses Kong and causes Kong to briefly mark the upstream as unhealthy, which results in intermittment 503 errors.

Follow these steps to reproduce the issue:

1. Clone this repo
2. `docker build -t kong-dns-bug . && docker run -p 8000:8000 -p 8001:8001 kong-dns-bug`
3. Watch the log output from Kong: `docker logs -f <container_id>`
4. Observe messages indicating the upstream is unhealthy and then healthy again any time TTL toggles between zero and non-zero on consecutive DNS queries.  Example:

```
2021/11/15 21:05:32 [debug] 1097#0: *21 [lua] base.lua:647: queryDns(): [upstream:example-upstream 1] querying dns for example.com
2021/11/15 21:05:32 [debug] 1097#0: *21 [lua] base.lua:562: f(): [upstream:example-upstream 1] dns record type changed for example.com, 33 -> 1
2021/11/15 21:05:32 [debug] 1097#0: *21 [lua] base.lua:242: disable(): [upstream:example-upstream 1] disabling address: example.com:443 (host example.com)
2021/11/15 21:05:32 [debug] 1097#0: *21 [lua] base.lua:266: change(): [upstream:example-upstream 1] changing address weight: example.com:443(host example.com) 100 -> 0
2021/11/15 21:05:32 [debug] 1097#0: *21 [lua] base.lua:368: newAddress(): [upstream:example-upstream 1] new address for host 'example.com' created: 93.184.216.34:443 (weight 100)
2021/11/15 21:05:32 [debug] 1097#0: *21 [lua] base.lua:626: f(): [upstream:example-upstream 1] updating balancer based on dns changes for example.com
2021/11/15 21:05:32 [debug] 1097#0: *21 [lua] base.lua:255: delete(): [upstream:example-upstream 1] deleting address: example.com:443 (host example.com)
2021/11/15 21:05:32 [debug] 1097#0: *21 [lua] base.lua:636: f(): [upstream:example-upstream 1] querying dns and updating for example.com completed
2021/11/15 21:05:32 [warn] 1097#0: *847 [lua] balancer.lua:258: callback(): [healthchecks] balancer 0dc6f45b-8f8d-40d2-a504-473544ee190b:example-upstream reported health status changed to UNHEALTHY, context: ngx.timer
2021/11/15 21:05:32 [warn] 1097#0: *848 [lua] balancer.lua:258: callback(): [healthchecks] balancer 0dc6f45b-8f8d-40d2-a504-473544ee190b:example-upstream reported health status changed to HEALTHY, context: ngx.timer
2021/11/15 21:05:32 [debug] 1097#0: *849 [lua] healthcheck.lua:1126: log(): [healthcheck] (0dc6f45b-8f8d-40d2-a504-473544ee190b:example-upstream) adding an existing target: example.com 93.184.216.34
```

## Analysis

The instance of Kong is configured with a single route (`/example`) whose target points to `https://www.example.com`.  The configuration also runs an instance of CoreDNS to provide custom DNS resolution.  The custom DNS resolution forwards to Google DNS, but configures caching such that the maximum TTL value is 11, and the resolver will sometimes return TTL = 0 in order simulate Route53 and Azure DNS resolution in a more controlled environment.  With DNS caching of 11 seconds, Kong will initially requery every 11 seconds.  It will eventually get TTL = 0, which causes Kong to put the target into a special mode where it will requery every 60 seconds.  Eventually, it will receive a non-zero TTL value again which briefly causes Kong to mark the target unhealthy and then healthy.  During the brief time when the target is unhealthy, any requests that attempt to use that endpoint will result in a 503 error.  Note that the DNS cache time of 11 seconds was intentionally selected so that it's NOT periodic with Kong's 60-second timer, so that Kong will receive both zero and non-zero TTL values from the DNS resolver over time.

If you open a shell inside the Kong container, you can check the current TTL returned by the DNS resolver as follows:

```
# dig example.com

; <<>> DiG 9.16.20 <<>> example.com
.....cut.....

;; ANSWER SECTION:
example.com.            6       IN      A       93.184.216.34

;; Query time: 2 msec
;; SERVER: 127.0.0.11#53(127.0.0.11)
;; WHEN: Mon Nov 15 21:22:37 UTC 2021
;; MSG SIZE  rcvd: 68
```

## Bug Report
Issue is tracked here:
https://github.com/Kong/kong/issues/7551
