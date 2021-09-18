# Vartier project

Your Web or API may be faster. Looking for project contributor/consultant with knowledge of Varnish/VCL.

Project contains prepared configuration library of [vcl](https://varnish-cache.org/docs/6.0/reference/vcl.html) files for [varnish-cache](https://varnish-cache.org/), primary designed for HTTP REST like APIs or key value database caching as passthrough http cache, allows [Edge Side Includes (ESI)](https://varnish-cache.org/docs/6.0/users-guide/esi.html) composition or loopback tranformations when one resource needs transforms to another representation but needs propagate TTL to minimalize cache inconsistency (backend application can requests back to vartier for example full data json of resource to return only some json keys or mixed more independent data resource to one).

Vartier is more an architectural cache pattern implemented with varnish for specific problem, inspired by other existing solutions and because i use varnish for years with good experiences. IMHO principles used in vartier can be used in application itself, implemented with nginx and lua, with workers behind Cloudflare or in AWS with lambda and Elasticache.

Vartier tries to solve one of the biggest developer problem, it is called "simple cache invalidation" for what varnish provides builtin solutions.

Vartier adds defaultly info about resource ttl, grace (how long cache can be returned after expire), hits count (higher than 1 is optimal) and restarts (detect problems) of requested cache layer in X-TTL response header.

## Request flow schemes


### Non cached + full cached + partial cached
![Request flow scheme](/docs/schemes/basic.png)

## Basic ideas

 * try to have an object entity in cache at exact representation only once (lower memory footprint)
 * recycle - use what you already have in vartier
 * use logicaly set time to live (TTL) whenever possible and tune it by backend (Cache-Control header with max-age) - caching to minutes is always better than seconds, but if you needs super fresh data also 1s is good if you have hotspot resource.
 * try to tag your resources with xkey header for better invalidation and use it
 * if you can precisely invalidate you can use very long TTLs
 * if you have problem invalidate use shortest TTL
 * lists of objects can be solved with ESI composing, but its not dogma, also note that microcaching layer use special header (X-Vartier-Cache-Control with max-age) to have another cache policy than resource itself to cache recomposed resource
 * stalled (not fresh) data are not mostly problem
 * try every fetch from backend to be as simple and fast as possible with predictable delivery time
 * don't use too long ESI lists (use some kind of force client paginate)
 * shallow recursion in ESI is not a problem (lists or html with ESI are 1 level recursion)
 * if use recursion ESI, avoiding cycles references is possible (@TODO: use some Vary header technique)
 * you can use vartier as source for another backend response (xml to json tranformatione) or combine more resources into newone, but you need transparently add xkey tags and resend Age header or compute new TTL to minimalize cache inconsistencies.
 * if fast generating response from backend is problem or resource is very few times requested (one days exports etc.), use cron like pregenerating (active refresh cache)
 * vartier config stays minimal as possible, mostly fall to default varnish builtin.vcl and trying don't force you to bypass it if you wants allow POST or PUT methods to routes for save resource or use routes with Cache-Control: no-cache (varnish listen to your backend responses and their headers)
 * if you have every object in cache for at least some TTL you can for that TTL time shutdown the backends and there is very little probability that somebody will notice any problem on readonly request

If you accept the vartier basic ideas than you get smaller cache footprint (every backend fetch is cached once and fetched once per TTL of this independend object/fragment, and some copies in every ESI composed microcache layer for very small time, but also this TTL can be tuned with X-Vartier-Cache-Control backend response header)

## Cache invalidation mechanics
Vartier allows two complementary cache invalidation/freshening mechanism.

 ### Purge xkey mechanism
 
Purge by xkey tag or more tags at once (soft or hard) on dedicated route behind ACL - If backend "tags" their responses with *xkey http header*, cache can be purged on special route without knowledge where resource in cache is present (use vmod-xkey module). Can be used one or more xkey tags if needed for both tagging and invalidation.

### Direct passthrough URL cache refreshing

If you don't know what is in this route but wants refetch fresh data to cache recursively for all ESI fragments inside

With client sending to URL *"X-Vartier-Refresh: true"* header (or localy http method REFRESH) triggers [hash_always_miss mechanism](https://varnish-cache.org/docs/6.0/reference/vcl.html) which *may be slow* but returns most freshed data without purging cache if something fails and minimal impact to paralel normal requests which may still return stalled data. It is good for slowly generating backends URLs - which are better independently cron-like fills or refresh cache, eg. on database/storage trigered change. Can be also used when accident on backend occurs and needs refresh incosistent data somewhere fast without purge whole cache elsewhere or when you temporary needs faster propagation of some data. Currently without ACL but it is possible to add it to code. Vartier can hold structure of your data only by reference them with small ESI Envelopes without any data.

## Compatibility and requirements

 * require [varnish-cache](https://varnish-cache.org/) http accelerator (>= 5.2.1, < 6.0.x - because varnish-modules are not compatible with new 6.1.x yet)
 * require [varnish-modules](https://github.com/varnish/varnish-modules) (>= 0.12.0) with modules vmod-xkey, vmod-saintmode and vmod-var 
 * designed for linux, especialy Debian like systems (Debian, Ubuntu) using /etc/varnish configs directory
 * @TODO - 2021-09-18 trying to use Varnish 6.0 LTS, current version is 7.0 but it is too young to use, wait for stability but features are promising - new PCRE2, structured fields in headers, glob for include etc.
 
 You must have some little devops knowledge (know how to install/build and configure varnish-cache server and varnish-modules and don't be lazy read some docs) also is better to be familiar with http requesting and sending http headers to fully use vartier potential. Basic knowledge of VCL configuration language for Varnish is needed.
 
## Project - how to use, what u can do with it

 Starting with - needs some backend application which u wants to cache, configure backends to vcl, set route vcl snippet and use it (complete /etc/varnish/conf.d/vartier.20.your_api_name.0.vcl from template and include it /etc/varnish/default.vcl)
 
 * designed for API, so only use URL routes instead of virtualhosts (virtualhost are possible with adding custom virtualhost to route API mapping VCL snippet with localhost vartier loopback, but it is out of scope vartier)
 * can handle more than one API by routes independently eg. /api:one/ or /second_api/
 * transparently use server side Vary header for handling more than one representation on the same route - get json or xml controlled with request Accept header or use some AB testing by client info headers, mobile device detection or simple authorization etc. - may require some vcl snippet to normalize this variation data to finite and small set of variations.
 * allows using ESI tags composition, if needed, without any line of change in configuration
 * multiple layered microcaching inspired by matroska like cache mechanism for ESI composition. First client requests some route which use ESI, next subsequent request is faster static and use their stale-while revalidate option. Can prevents hotspots route to require more CPU but this technique requires some additional memory. Because varnish has LRU mechanism, it may not be a problem.
 * TTL and stale-while-revalidate using - use Cache-Control header (@TODO use max-age or s-maxage use)
 * Try refresh on stalled - clients can choose from faster response (but maybe stalled data) or more consistent data fetched from backend with adding special X-Vartier-Flags header (on routes can be forced this behavior in vcl)
 * Backend is primary source of how long cache both, micro and esi/resource layer, and how long allow grace (mechanism for preventing dogpile, less backend requests)
 * needs only simple backend + route configuration from example vcl template

## Use command line tools bundled with varnish

Varnish cache contains excellent command line tools for analyzing request / responses
 * use **varnishtop** for analyzing hotsposts or some problems on the fly
 * use **varnishstat** for get cachehit ratio, bandwith or error rate
 * use **varnishhist** to find some problems in latency, identify slow request/response or found the slowest backend etc.

## Development of backends or clients with or without vartier

With passthrough design, backends can be developed more straightforward - vartier is only proxy cache containing exactly what backend responds with capability to compose ESI, so when require ESI composition you will need some patching in backends if you remove vartier from stack, to emulate the same functionality. But if you use ESI you know why, so it seems ok.

Clients needs only endpoint reconfiguration.

## Scalability concept

Vartier can be used in clusters but scenario can vary for your application architecture.

  * horizontal scaling with more servers to gain more bandwith, more CPU or more RAM, it may require some another balancing mechanism.   Need to know that every vartier instance has its independent cache (nothing strange).
  * Cascade mirror vartier which use as backends another vartier with same route configuration (API routes are transparently propagated, everything is HTTP request) - Practical if you have not problem with tradeoff between slightly cache aging, but has problem with latency or unstable network between datacenters.
  * Vartier is designed to allow clientside bypass of ESI expansion for fetching raw objects fragments to another instance of Vartier server with transparent propagation TTL and AGE. With some backend log stream parser (not included in this project) and direct passthrough URL cache refetch mechanism can be used to synchronize caches between cluster from backends (consistent) or from another vartier cache (faster but needs changes in VCL). So how much complex architecture you use is on you. Send **X-Vartier-Level: backend** request header and see what change on ESI compatible route (get only envelope without expansion ESI and valid TTL/Age header)
  * @TODO notice about development mirror
  
  ## Performance
  
  For now i don't have exactly measures, but from simple test is not problem to deliver one digit thousands and more responses per seconds (2-20 - vary on response body size and complexity of ESI) on normal developer laptop with Core i5 2.6Ghz/2 Core with HT (4 core) with 8GB RAM. Benchmark is done from localhost to localhost with concurency 100 with [siege](https://github.com/JoeDog/siege). 

## Author

Vaclav Barta (https://github.com/littlebart/)
