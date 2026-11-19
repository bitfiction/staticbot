# infrastructure/modules/static-website/redirects.tf

# CloudFront function for language/region redirects
resource "aws_cloudfront_function" "language_redirect" {
  name    = "lang-redir-${substr(sha1("${var.account_name}-${local.domain_part}"), 0, 10)}"
  runtime = "cloudfront-js-1.0"
  comment = "Redirects users based on their location/language"

  code = <<-EOF
function handler(event) {
    var request = event.request;
    var headers = request.headers;
    
    // Skip redirect for existing language paths
    if (request.uri.match(/^\/(en|es|de|fr)\//)) {
        return request;
    }

    // Get user's country from CloudFront header
    var countryCode = headers['cloudfront-viewer-country'] 
        ? headers['cloudfront-viewer-country'].value 
        : 'US';
    
    // Get user's preferred language
    var acceptLanguage = headers['accept-language'] 
        ? headers['accept-language'].value.split(',')[0].slice(0,2) 
        : 'en';
    
    // Language mapping
    var languageMap = {
        'US': 'en',
        'GB': 'en',
        'ES': 'es',
        'MX': 'es',
        'DE': 'de',
        'AT': 'de',
        'FR': 'fr',
        'CA': 'fr'
    };
    
    // Determine language based on country or fallback to accept-language
    var language = languageMap[countryCode] || languageMap[acceptLanguage] || 'en';
    
    // Redirect to language-specific path
    return {
        statusCode: 302,
        statusDescription: 'Found',
        headers: {
            'location': {
                value: '/' + language + request.uri
            },
            'cache-control': {
                value: 'max-age=3600'
            }
        }
    };
}
EOF
}

# Combined viewer-request handler.
#
# Runs on every request and handles three concerns in priority order:
#   1. Maintenance mode  — redirect all traffic (except allowed IPs) to /maintenance.html
#   2. www redirect      — canonicalise the host to www.{domain} (when enabled)
#   3. Directory index   — rewrite clean URLs to their actual S3 object keys:
#        /about/  →  /about/index.html   (Next.js static export with trailingSlash: true)
#        /about   →  /about.html         (Next.js static export without trailingSlash)
#      Static assets (paths containing a dot in the last segment) are left unchanged.
#      This is a no-op for SPAs — extensionless paths still 404 in S3 and the
#      custom_error_response rule then serves root index.html as before.
resource "aws_cloudfront_function" "viewer_request" {
  name    = "viewer-req-${substr(sha1("${var.account_name}-${local.domain_part}"), 0, 10)}"
  runtime = "cloudfront-js-2.0"
  comment = "Directory index routing, optional www redirect, optional maintenance mode"

  lifecycle {
    create_before_destroy = true
  }

  code = <<-EOF
function handler(event) {
    var request = event.request;
    var uri = request.uri;
    var host = request.headers.host ? request.headers.host.value : '';

    // === MAINTENANCE MODE ===
    var maintenanceMode = ${var.maintenance_mode};
    var allowedIPs = ${jsonencode(var.maintenance_allowed_ips)};
    var maintenancePath = '/maintenance.html';

    if (maintenanceMode && uri !== maintenancePath) {
        if (!allowedIPs.includes(event.viewer && event.viewer.ip)) {
            return {
                statusCode: 302,
                statusDescription: 'Found',
                headers: {
                    'location': { value: maintenancePath },
                    'cache-control': { value: 'no-cache' }
                }
            };
        }
    }

    // === PER-STACK REDIRECTS (exact-match) ===
    // Populated from the Stack edit page's "Redirects" field. Matched literally
    // and short-circuits before www canonicalisation and path rewriting so
    // legacy URLs don't get bounced through clean-URL processing first.
    var redirects = ${jsonencode(var.redirects)};
    for (var i = 0; i < redirects.length; i++) {
        var r = redirects[i];
        if (uri === r.from) {
            return {
                statusCode: r.status,
                statusDescription: r.status === 301 ? 'Moved Permanently'
                                 : r.status === 308 ? 'Permanent Redirect'
                                 : r.status === 307 ? 'Temporary Redirect'
                                 : 'Found',
                headers: { 'location': { value: r.to } }
            };
        }
    }

    // === WWW REDIRECT ===
    var wwwRedirect = ${var.www_redirect};
    var domain = '${var.domain_name}';

    if (wwwRedirect && !host.startsWith('dev.')) {
        if (host === domain || !host.startsWith('www.')) {
            return {
                statusCode: 301,
                statusDescription: 'Moved Permanently',
                headers: {
                    'location': { value: 'https://www.' + domain + uri + queryString(request.querystring) },
                    'cache-control': { value: 'max-age=3600' }
                }
            };
        }
    }

    // === DIRECTORY INDEX ===
    // Only rewrite if the last path segment has no file extension (i.e. not an asset).
    var lastSegment = uri.split('/').pop();
    var hasExtension = lastSegment.includes('.');

    // SPA shell served here instead of by custom_error_response, which is off when the site proxies
    // "/functions/*" (functions-proxy.tf). Same rule as the shared preview distribution's router.
    var spaShellInFunction = ${local.functions_proxy_enabled};
    if (spaShellInFunction) {
        if (!hasExtension) {
            request.uri = '/index.html';
        }
        return request;
    }

    if (!hasExtension) {
        if (uri.endsWith('/') && uri.length > 1) {
            // /about/ → /about/index.html  (Next.js trailingSlash: true)
            request.uri = uri + 'index.html';
        } else if (!uri.endsWith('/')) {
            // /about → /about.html  (Next.js default, no trailingSlash)
            request.uri = uri + '.html';
        }
    }

    return request;
}

// "?a=1&b=2" rebuilt from request.querystring, or '' when there is none. The www redirect used to
// drop the query, which lost UTM parameters, shared deep links and a PKCE "?code=" on the apex.
// CloudFront hands names and values over exactly as the viewer sent them, still percent-encoded
// (checked 2026-11-19 on a probe distribution: "x%2Fy" stays "x%2Fy", "foo+bar" stays "foo+bar"),
// so they are joined back unchanged. Re-encoding them would turn "%2F" into "%252F". Only runs of
// characters a Location header cannot carry are encoded: a raw space or non-ASCII character, which
// browsers never send but other clients can. Order across names is not kept (the event is an
// object); repeated names keep theirs (multiValue). A bare "?flag" comes back as "flag=".
function queryString(qs) {
    try {
        var parts = [];
        for (var name in qs) {
            var values = qs[name].multiValue || [qs[name]];
            for (var i = 0; i < values.length; i++) {
                parts.push(headerSafe(name) + '=' + headerSafe(values[i].value));
            }
        }
        return parts.length ? '?' + parts.join('&') : '';
    } catch (e) {
        return ''; // e.g. a lone surrogate encodeURIComponent rejects: redirect without the query
    }
}

function headerSafe(s) {
    return s.replace(/[^\x21-\x7e]+/g, function (run) { return encodeURIComponent(run); });
}
EOF
}
