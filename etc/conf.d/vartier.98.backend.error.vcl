vcl 4.0;
# @source from https://github.com/fgsch/vcl-snippets/blob/master/v5/stale-if-error.vcl
# Only adds little tune for vartier use and adds registration to global var info
sub vcl_init {
	var.global_set("X-Apis", var.global_get("X-Apis") + "; stale-if-error=internal");
}

sub vcl_hit {
	if (obj.ttl < 0s && obj.ttl + obj.grace > 0s && req.http.X-Vartier-Flags ~ "(^|[, ]+)cache:expired:backend=force-fetch([, ]+|$)") {
		if (req.restarts == 0) {
			set req.http.sie-enabled = true;
			set req.hash_always_miss = true;
			return (restart);
		} else {
			set req.http.sie-abandon = true;
			return (deliver);
		}
	}
}

sub vcl_backend_fetch {
	if (bereq.http.sie-abandon) {
		return (abandon);
	}
}

sub vcl_backend_response {
	if (beresp.status > 400 && bereq.http.sie-enabled) {
		return (abandon);
	}
}

sub vcl_backend_error {
	/* All modules can handle backend_errors, this is default behavior */
	if (bereq.http.sie-enabled) {
		return (abandon);
	}
}

sub vcl_synth {
	if (resp.status == 503 && req.http.sie-enabled) {
		unset req.http.sie-enabled;
		set req.hash_always_miss = false;
		return (restart);
	}
}
