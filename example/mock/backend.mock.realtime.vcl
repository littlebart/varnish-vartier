vcl 4.0;

sub vcl_recv {
	if (req.url ~ "^/mock:realtime/ttl=\d+") {
		return(synth(701, req.url));
	}

	if (req.url ~ "^/mock:realtime/\d+") {
		return(synth(702, req.url));
	}
	return(synth(200, "ok"));
}

# syntethic responses mocks - will be served from real backend server
# but for illustration of power of synthetic responses
sub vcl_synth {
	# /mock:realtime/ttl=\d+
	if (resp.status == 701) {
		# parse TTL from path
		set req.http.X-TTL = regsuball(resp.reason, "^.*/ttl=([0-9]+).*$", "\1");
		# some defaults
		if (req.http.X-TTL !~ "^[0-9]+$") {
			set req.http.X-TTL = "2";
		}
		# use cache control extension https://tools.ietf.org/html/rfc5861
		set resp.http.Cache-Control = "max-age=" + req.http.X-TTL + ", stale-while-revalidate=5, stale-if-error=3600";
		set resp.http.xkey = req.http.X-TTL;
		synthetic( {"{
		"item_id": ""}
			+ req.http.X-TTL + {"",
		"vxid": ""}
			+ resp.http.X-Varnish + {"",
		"data": ""}
			+ resp.http.Date + {""
}"} );
		# cleanup local header
		unset req.http.X-TTL;
		call deliver_json_200_ok;
	}
}

sub vcl_synth {
	# /mock:realtime(/\d+)+
	if (resp.status == 702) {
		# cache policy for query response change (same req => same resp ?) so long
		set resp.http.Cache-Control = "max-age=20, stale-while-revalidate=5, stale-if-error=3600";
		# cache policy for responses after esi parts processing if necessary
		set resp.http.X-Vartier-Cache-Control = "max-age=1, stale-while-revalidate=5";

		# create multiple esi tags from input path number delimited by "/" eg.: /mock:realtime/1/2/3/4
		# cleanup from not /\d+ parts
		set resp.http.X-Esi = regsub(regsuball(resp.reason, "/[^0-9][^/]*", ""), "/$", "");
		# default value
		if (resp.http.X-Esi == "") {
			set resp.http.X-Esi = "/4";
		}
		# xkey header has delimiter space
		set resp.http.xkey = regsuball(resp.http.X-Esi, "/", " ");
		# replace all /\d+ by esi with his ttl (and uniq url)
		# Example of use multiline and quotes in regsuball
		set resp.http.X-Esi = regsuball(resp.http.X-Esi, "/([0-9]+)", {"
	{ ""} + "/mock:realtime/ttl=\1" + {"": [ <esi:include src="/mock:realtime/ttl="} + "\1" + {"" /> ] }
	,"});
		synthetic( {"{
	"list": ""} + resp.reason + {"",
	"list_val": ""} + resp.http.Date + {"",
	"items": ["} + regsub(resp.http.X-Esi, ",$", "") + {"
	]
}"} );
		# reset header to enable esi parsing
		unset resp.http.X-Esi;
		set resp.http.Surrogate-Control = {"content="ESI/1.0";vartier"};
		call deliver_json_200_ok;
	}
}
