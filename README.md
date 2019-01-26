# Vartier project

Your Web API may be faster.

Prepared configuration library of [vcl](https://varnish-cache.org/docs/6.0/reference/vcl.html) files for [varnish-cache](https://varnish-cache.org/), primary designed for HTTP REST like APIs or key value database caching as passthrough http cache, allows [Edge Side Includes (ESI)](https://varnish-cache.org/docs/6.0/users-guide/esi.html) composition or loopback tranformations when one resource needs transforms to another representation but needs propagate TTL to minimalize cache inconsistency (backend application can requests back to vartier for example full data json of resource to return only some json keys or mixed more independent data resource to one).

Vartier is more architectural cache pattern implemented with varnish for specific problem, but IMHO principles used in vartier can be used in application itself, with nginx and lua, in workers behind Cloudflare or in AWS lambda with Elasticache.

Vartier tries to solve one of the biggest developer problem, it is called "simple cache invalidation".

## Basic ideas

 * try to have an object entity in cache at exact representation only once (lower memory footprint)
 * recycle - use what you already have in vartier
 * use logicaly set time to live (TTL) whenever possible and tune it by backend (Cache-Control header with max-age) - caching to minutes is always better than seconds, but if you needs super fresh data also 1s is good if you have hotspot resource.
 * try to tag your resources with xkey header for better invalidation and use it
 * if you can precisely invalidate you can use very long TTLs
 * if you have problem invalidate use shortest TTL
 * lists of objects can be solved with ESI composing, but its not dogma, also note that microcaching layer use special header to have another cache policy than resource itself
 * staled (not fresh) data are not mostly problem
 * try every fetch from backend to be as simple and fast as possible
 * don't use too long ESI lists (use some kind of force client paginate)
 * shallow recursion in ESI is not a problem (lists or html with ESI are 1 level recursion)
 * if use recursion ESI, avoiding cycles references is possible
 * you can use vartier as source for another backend response (xml to json tranformatione) or combine more resources into newone, but you need transparently add xkey tags and resend Age header or compute new TTL to minimalize cache inconsistencies.
 * if fast generating response from backend is problem and resource is very few times requested (one days exports etc.), use cron like pregenerating

 * if you have every object in cache for at least some TTL you can for that TTL time shutdown the backends and there is very little probability that somebody will notice any problem 

If you accept the vartier basic ideas than you get smaller cache footprint (every backend fetch is cached once and fetched once per TTL of this independend object/fragment, and some copies in every ESI composed microcache layer for very small time, but also this TTL can be tuned with X-Vartier-Cache-Control backend response header)

## Cache invalidation mechanics
Vartier allows two complementary cache invalidation mechanism.

 ### Purge xkey mechanism
 
Purge by xkey tag or more tags at once (soft or hard) on dedicated route behind ACL - If backend "tags" their responses with *xkey http header*, cache can be purged on special route without knowledge where resource in cache is present (use vmod-xkey module). Can be used one or more xkey tags if needed for both tagging and ivalidation.

### Direct passthrough route cache refreshing

If you don't know what is in this route but wants refetch fresh data to cache recursively for one or all ESI fragments.

This *may be slow* but returns most freshed data without purging cache if something fails and minimal impact to paralel normal requests which may still return staled data. It is good for slowly generating backends routes - which is better on cron refresh or refresh cache on database/storage trigered change. Can be also used when accident on backend occurs and needs refresh incosistent data somewhere fastly without purge whole cache elsewhere or when you temporary needs faster propagation of some data. Currently without ACL but it is possible to add it to code.

## Compatibility and requirements

 * require varnish-cache http accelerator (>= 5.2.1, < 6.0.x - because varnish-modules are not compatible with new 6.1.x yet)
 * require varnish-modules (>= 0.12.0) with modules vmod-xkey, vmod-saintmode and vmod-var 
 * designed for linux, especialy Debian like systems (Debian, Ubuntu) using /etc/varnish configs directory
 
 You must have some little devops knowledge (know how to install/build and configure varnish-cache server and varnish-modules and don't be lazy read some docs) also is better to be familiar with http requesting and sending http headers to fully use vartier potential. Basic knowledge of VCL configuration language for Varnish is needed.
 
## Project - how to use, what u can do with it

 Starting with - needs some backend application which u wants to cache, configure backends to vcl, set route vcl snippet and use it
 
 * designed for API, so only use URL routes instead of virtualhosts (virtualhost are possible with adding custom virtualhost to route API mapping  VCL snippet with localhost vartier loopback, but it is out of scope vartier)
 * can handle more than one API by routes independently eg. /Api1/ and /secondApi/
 * transparently use server side Vary header for handling more than once representation on the same route - get json or xml controlled  with request Accept header or use some AB testing by client info headers, mobile device detection or simple authorization etc. - may require some vcl snippet to normalize this variation data to finite and small set of variations.
 * allows using ESI tags composition, if needed, without any line of change in configuration
 * multiple layered microcaching inspired by matroska like cache mechanism for ESI composition. First client requests some route which use ESI, next subsequent request is faster static and use their stale-while revalidate option. Can prevents hotspots route to require more CPU but this technique requires more memory. Because varnish has LRU mechanism, it may not be a problem.
 * TTL and stale-while-revalidate use
 * Client can choose from faster response (but maybe staled data) or more consistent data fetched from backend with adding special X-Vartier-* header.
 * Backend is primarily source of how long both caching (micro or base) layers are used, and how long allow grace (mechanism for preventing dogpile, less backend requests)
 * needs simple backend + route configuration from example vcl template
 * varnish cache contains excellent command line tools for analyzing request / responses - use varnishtop for analyzing hotsposts or some problems on the fly, varnishstat for cachehit ratio, bandwith or error rate, varnishhist to find some problems in latency, too long request/response or slowest backend etc.

## Development of backends or clients with or without vartier

With passthrough design, backends can be developed more straightforward - vartier is only proxy cache containing exactly what backend responds with capability to compose ESI, so when require ESI composition you will need some patching in backends if you remove vartier from stack, to emulate the same functionality. But if you use ESI you know why, so it seems ok.

Clients needs only endpoint reconfiguration.

## Scalability concept

Vartier can be used in clusters but scenario can vary for your application architecture.

  * horizontal scaling with more servers to gain more bandwith, more CPU or more RAM, it may require some another balancing mechanism.   Need to know that every vartier instance has its independent cache (nothing strange).
  * Cascade mirror vartier which use as backends another vartier with same route configuration (API routes are transparently propagated, everything is HTTP request) - Practical if you have not problem with tradeoff between slightly cache aging, but has problem with latency or unstable network between datacenters.
  * Vartier is designed to allow clientside bypass of ESI expansion for fetching raw objects fragments to another instance of Vartier server with transparent propagation TTL and AGE. With some backend log stream parser (not included in this project) and direct passthrough route cache refetch mechanism can be used to synchronize caches between cluster from backends (consistent) or from another vartier cache (faster but needs changes in VCL). So how much complex architecture you use is on you.
  * @TODO notice about development mirror
  
  ## Performance
  
  For now i don't have exactly measures, but from simple test is not problem to deliver one digit thousands and more responses per seconds (2-20 - vary on response body size and complexity of ESI) on normal developer laptop with Core i5 2.6Ghz/2 Core with HT (4 core) with 8GB RAM. Benchmark is done from localhost to localhost with concurency 100 with [siege](https://github.com/JoeDog/siege). 
