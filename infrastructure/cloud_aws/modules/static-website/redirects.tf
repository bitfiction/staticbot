# infrastructure/modules/static-website/redirects.tf

# CloudFront function for language/region redirects
resource "aws_cloudfront_function" "language_redirect" {
  name    = "lang-redir-${substr(sha1("${var.account_name}-${var.stage_subdomain}-${var.domain_name}"), 0, 10)}"
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

# CloudFront function for www/non-www redirects
resource "aws_cloudfront_function" "www_redirect" {
  count   = var.www_redirect ? 1 : 0
  name    = "www-redir-${substr(sha1("${var.account_name}-${var.stage_subdomain}-${var.domain_name}"), 0, 10)}"
  runtime = "cloudfront-js-1.0"
  comment = "Redirects between www and non-www versions"

  code = <<-EOF
function handler(event) {
    var request = event.request;
    var host = request.headers.host.value;
    var domain = '${var.domain_name}';
    
    if (host.startsWith('dev.')) {
        // Don't redirect dev environments
        return request;
    }

    // Configure preferred domain format (www or non-www)
    var useWWW = true;  // Set to false to prefer non-www
    
     // Handle both direct domain and www cases
     if (useWWW && (host === domain || !host.startsWith('www.'))) {
        return {
            statusCode: 301,
            statusDescription: 'Moved Permanently',
            headers: {
                'location': {
                    value: 'https://www.' + domain + request.uri
                },
                'cache-control': {
                    value: 'max-age=3600'
                }
            }
        };
    } else if (!useWWW && host.startsWith('www.')) {
        return {
            statusCode: 301,
            statusDescription: 'Moved Permanently',
            headers: {
                'location': {
                    value: 'https://' + domain + request.uri
                },
                'cache-control': {
                    value: 'max-age=3600'
                }
            }
        };
    }
    
    return request;
}
EOF
}

# CloudFront function for maintenance mode
resource "aws_cloudfront_function" "maintenance_mode" {
  name    = "maint-mode-${substr(sha1("${var.account_name}-${var.stage_subdomain}-${var.domain_name}"), 0, 10)}"
  runtime = "cloudfront-js-1.0"
  comment = "Handles maintenance mode redirects"

  code = <<-EOF
function handler(event) {
    var request = event.request;
    
    // Maintenance mode configuration
    var maintenanceMode = false;  // Control via variable or SSM Parameter
    var allowedIPs = ['1.2.3.4', '5.6.7.8'];  // Admin IPs that can bypass
    var maintenancePath = '/maintenance.html';
    
    // Skip redirect for maintenance page itself
    if (request.uri === maintenancePath) {
        return request;
    }
    
    // Check if maintenance mode is active
    if (maintenanceMode) {
        // Allow specific IPs to bypass
        var clientIP = request.clientIp;
        if (allowedIPs.includes(clientIP)) {
            return request;
        }
        
        // Redirect all other traffic to maintenance page
        return {
            statusCode: 302,
            statusDescription: 'Found',
            headers: {
                'location': {
                    value: maintenancePath
                },
                'cache-control': {
                    value: 'no-cache'
                }
            }
        };
    }
    
    return request;
}
EOF
}

# Create maintenance page
resource "aws_s3_object" "maintenance_page" {
  bucket       = aws_s3_bucket.website.id
  key          = "maintenance.html"
  content      = <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Maintenance - ${var.domain_name}</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            background: #f5f5f5;
            text-align: center;
        }
        .maintenance-container {
            max-width: 600px;
            padding: 40px;
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 { color: #333; margin-bottom: 20px; }
        p { color: #666; }
    </style>
</head>
<body>
    <div class="maintenance-container">
        <h1>Site Maintenance</h1>
        <p>We're currently performing scheduled maintenance. Please check back soon.</p>
        <p>Expected duration: 30 minutes</p>
    </div>
</body>
</html>
EOF
  content_type = "text/html"
}
