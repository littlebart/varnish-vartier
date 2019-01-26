vcl 4.0;
/**
 * Flags options
 * - flags are used to control request flow or in some API force behavior
 */

sub vcl_init {
	var.global_set("X-Apis", var.global_get("X-Apis") + "; flags=internal");
}

sub vcl_recv {
	/* X-Vartier-Top-Flags are set only once with initial request */
	if (!req.http.X-Vartier-Top-Flags) {
		if (req.http.X-Vartier-Flags) {
			set req.http.X-Vartier-Top-Flags = req.http.X-Vartier-Flags;
		} else {
			set req.http.X-Vartier-Top-Flags = "none";
		}
	}
	/* X-Vartier-Flags default value, can be changed by API localy */
	if (!req.http.X-Vartier-Flags) {
		set req.http.X-Vartier-Flags = req.http.X-Vartier-Top-Flags;
	}
}

sub vcl_backend_fetch {
	if (bereq.http.X-Vartier-Flags ~ "(^|[, ]+)subrequest:headers:x-varnish=disable([, ]+|$)") {
		unset bereq.http.X-Varnish;
	}
}

