vcl 4.0;

sub vcl_recv {
	/* @TODO: Experimental - preserve locking, but can cache object more than once and more queries to backend */
	if (req.http.X-Vartier-Flags ~ "(^|[, ]+)request:hash_ignore_busy_lock=enable([, ]+|$)") {
		set req.hash_ignore_busy = true;
	}
}

sub vcl_deliver {
	if (req.http.X-Vartier-Level == "client") {
		/* We can't show xkey tagging to the clients, possible shorter responses */
		if (req.http.X-Vartier-Flags ~ "(^|[, ]+)response:client:headers:xkey=disable([, ]+|$)") {
			unset resp.http.xkey;
		}
	}
}
