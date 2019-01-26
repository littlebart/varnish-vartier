vcl 4.0;

sub vcl_init {
	var.global_set("X-Apis", var.global_get("X-Apis") + "; mock:realtime=remote");
}

sub vcl_recv {
	if (req.url ~ "^/mock:realtime/") {
		set req.http.X-Vartier-Current-Api = "mock:realtime";

		if (req.http.X-Vartier-Flags !~ "(^|[, ]+)cache:expired:backend=force-fetch([, ]+|$)") {
			set req.http.X-Vartier-Flags = req.http.X-Vartier-Top-Flags + ",cache:expired:backend=force-fetch";
		}

		if (req.http.X-Vartier-Level != "client") {
			set req.backend_hint = cluster_backend_mock_realtime.backend();
		}
	}
}

sub vcl_deliver {
	/* Hide Vartier info for clients on this API */
	if (req.url ~ "^/mock:realtime/" && req.http.X-Vartier-Level == "client") {
		unset resp.http.X-Vartier-Apis;
	}
}
