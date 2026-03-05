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
        if (!allowedIPs.includes(request.clientIp)) {
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

    // === WWW REDIRECT ===
    var wwwRedirect = ${var.www_redirect};
    var domain = '${var.domain_name}';

    if (wwwRedirect && !host.startsWith('dev.')) {
        if (host === domain || !host.startsWith('www.')) {
            return {
                statusCode: 301,
                statusDescription: 'Moved Permanently',
                headers: {
                    'location': { value: 'https://www.' + domain + uri },
                    'cache-control': { value: 'max-age=3600' }
                }
            };
        }
    }

    // === DIRECTORY INDEX ===
    // Only rewrite if the last path segment has no file extension (i.e. not an asset).
    var lastSegment = uri.split('/').pop();
    var hasExtension = lastSegment.includes('.');

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
EOF
}
