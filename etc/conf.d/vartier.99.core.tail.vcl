vcl 4.0;

sub vcl_recv {
	/* all unhandled requests return some info */
	if (!req.http.X-Vartier-Current-Api) {
		return(synth(800, "404 Api not found"));
	}
	/**
	 * By default Vartier don't use Cookie header logic
	 */
	unset req.http.Cookie;
}

sub vcl_hash {
	return (lookup);
}

sub vcl_backend_response {
	/* use stale-if-error header for longer grace */
	var.set_duration("stale-if-error", 300s);
	if (beresp.http.Cache-Control ~ "stale-if-error=\d+") {
		var.set_duration("stale-if-error",
			std.duration(
				regsub(beresp.http.Cache-Control, "(^|.*[,\s])stale-if-error=(\d+).*", "\2") + "s",
				var.get_duration("stale-if-error")
			)
		);
	}
	if (beresp.grace < var.get_duration("stale-if-error")) {
		set beresp.grace = var.get_duration("stale-if-error");
	}

	if (beresp.status >= 500 && !bereq.http.sie-enabled && bereq.http.X-Vartier-Refresh != "true") {
		return(retry);
	}
}

sub vcl_backend_error {
	/**
	 * Default JSON error handler
	 * returns status 200 if not in refresh hash_always_miss state
	 */
	synthetic( {"
	{
		"app": "Vartier",
		"version": ""} + var.global_get("X-Apis") + {"",
		"url": ""} + bereq.url + {"",
		"retry-after": 5,
		"status": "} + beresp.status + {",
		"reason": ""} + regsuball(beresp.reason, {"""}, {"\""}) + {""
	}"} );
	set beresp.http.Content-Type = "application/json; charset=utf-8";
	set beresp.http.Cache-Control = "max-age=5, stale-while-revalidate=5";
	if (bereq.http.X-Vartier-Refresh != "true") {
		set beresp.reason = "OK";
		set beresp.status = 200;
	}
	return(deliver);
}

sub vcl_synth {
	if (resp.status == 800) {
		synthetic( {"{
	"app": "Vartier",
	"version": ""} + var.global_get("X-Apis") + {"",
	"message": ""} + regsuball(resp.reason, {"""}, {"\""}) + {""
}"} );
		call deliver_json_200_ok;
	}
}

sub vcl_deliver {
	/* Remove age header between esi and microcaching layer */
	if (req.http.X-Vartier-Level == "esi" && req.http.X-Vartier-Top-Level == "client" && resp.http.X-Vartier-Use-Esi == "true") {
		unset resp.http.Age;
	}
	unset resp.http.via;
	unset resp.http.server;
}
