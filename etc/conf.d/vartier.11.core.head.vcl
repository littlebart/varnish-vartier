vcl 4.0;
/**
 * default backend settings and importing std module is not necessary in eea-varnish (used configuration with ENVIRONMENT)
 * some other functionality is moved into generated backend.vcl
 */

/*
import var;
import std;
*/
backend default {
	.host = "127.0.0.1";
	.port = "6081";
}

sub vcl_recv {
	set req.backend_hint = default;

	/* Remove duplicate X-Forwarded-For on default loop */
	if (req.http.X-Forwarded-For ~ "(?:, 127.0.0.1){2,}") {
		set req.http.X-Forwarded-For = regsuball(req.http.X-Forwarded-For, "(, 127.0.0.1)+", ", 127.0.0.1");
	}

	/**
	 * Merge all request X-Varnish header, avoid leak of max header count
	 */
	if (req.http.X-Varnish) {
		std.collect(req.http.X-Varnish, ", ");
	}

	/**
	 * Unset api header, will be checked in tail if was set in vcl_recv else return syntetic response
	 */
	unset req.http.X-Vartier-Current-Api;

	if (req.http.X-Vartier-Level !~ "^(client|esi)$") {
		/* internal backend raw response eg. "backend", disable esi parsing */
		if (req.http.X-Vartier-Level) {
			set req.esi = false;
			set req.http.X-Vartier-Level = "esi";
		} else {
			set req.http.X-Vartier-Level = "client";
		}
	}

	/**
	 * For recursive esi this helps prevents strange behavior
	 * - split esi only current level and subesi are parsed in another delegated requests (cause varnish 5.2.1 strange segfaults)
	 */
	if (req.esi_level > 0) {
		set req.http.X-Vartier-Level = "client";
	}
	set req.http.X-Vartier-Esi-Level = req.esi_level;

	if (req.method == "REFRESH" || req.http.X-Vartier-Refresh == "true") {
		set req.method = "GET";
		set req.http.X-Vartier-Refresh = "true";
		set req.hash_always_miss = true;
	} else {
		unset req.http.X-Vartier-Refresh;
	}

	if (!req.http.X-Vartier-Top-Level) {
		set req.http.X-Vartier-Top-Level = req.http.X-Vartier-Level;
	}

	/**
	 * Use surrogate headers to inform backend (and Surrogate-Control back to vartier)
	 * @source: https://www.w3.org/TR/edge-arch/
	 *
	 * @TODO: Surrogate-Control can be used to set ttl/grace instead of proprietary X-Vartier-Cache-Control
	 */
	set req.http.Surrogate-Capabilities = {"vartier="ESI/1.0""};

	/* Logging info for debug */
	var.set("info", "Top=" + req.http.X-Vartier-Top-Level + "/Lev=" + req.http.X-Vartier-Level + "/Esi=" + req.http.X-Vartier-Esi-Level);
	if(req.http.X-Vartier-Refresh == "true") {
		var.set("info", var.get("info") + "/refresh");
	}
	set req.http.User-Agent = "<" + var.get("info") + ">";
	if(req_top.url != req.url || !req.http.Referer) {
		set req.http.Referer = req_top.url;
	}

}

sub vcl_hash {
	hash_data(req.url);
	hash_data(req.http.X-Vartier-Level);
}

sub vcl_backend_fetch {
	if (bereq.http.X-Vartier-Top-Level != bereq.http.X-Vartier-Level) {
		set bereq.http.X-Vartier-Top-Level = bereq.http.X-Vartier-Level;
	}
	if (bereq.http.X-Vartier-Level != "esi") {
		set bereq.http.X-Vartier-Level = "esi";
	}
}

sub vcl_backend_response {
	if (beresp.ttl <= 0s && beresp.http.Cache-Control !~ "no-store" && beresp.status <= 400) {
		set beresp.ttl = 1s;
		set beresp.grace = 5s;
	}
	/* Example: case insensitive regular match can be "Esi/1.0" or something similar */
	if (beresp.http.Surrogate-Control ~ {"(?i)content="(esi/1.0|[^"]+ esi/1.0)[^"]*"(;vartier|[^;]|$)"}) {
		if (beresp.http.X-Vartier-Use-Esi != "true") {
			set beresp.http.X-Vartier-Use-Esi = "true";
		}
		set beresp.do_esi = true;
		if (!beresp.http.X-Vartier-Cache-Control) {
			set beresp.http.X-Vartier-Cache-Control = "max-age=1, stale-while-revalidate=5";
		}
	} else {
		unset beresp.http.X-Vartier-Use-Esi;
	}
	/* Handle Cache-Control for esi requests */
	if (beresp.http.X-Vartier-Use-Esi == "true") {
		/**
		 * X-Vartier-Cache-Control header to allow microcaching granularity
		 * This header is propagate automaticaly
		 * default is max-age=1, stale-while-revalidate=5 for microcaching layer
		 */
		if (bereq.http.X-Vartier-Top-Level == "client" && beresp.http.X-Vartier-Cache-Control) {
			/* use new caching policy */
			if (beresp.http.Cache-Control != beresp.http.X-Vartier-Cache-Control) {
				set beresp.http.Cache-Control = beresp.http.X-Vartier-Cache-Control;
			}
			unset beresp.http.X-Vartier-Cache-Control;
			set beresp.ttl = std.duration(regsub(beresp.http.Cache-Control, ".*max-age=(\d+).*", "\1") + "s", 1s);
			set beresp.grace = std.duration(regsub(beresp.http.Cache-Control, ".*stale-while-revalidate=(\d+).*", "\1") + "s", 5s);
		}
	}
}

sub vcl_deliver {
	if (req.http.X-Vartier-Refresh == "true") {
		set resp.http.X-Vartier-Refresh = "refreshed";
	}
	set resp.http.X-TTL = obj.ttl + "+" + obj.grace + "+" + obj.hits + "+" + req.restarts;
}
