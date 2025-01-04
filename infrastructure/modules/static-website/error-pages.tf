# infrastructure/modules/static-website/error-pages.tf

# Error pages configuration for S3
resource "aws_s3_object" "error_404" {
  bucket = aws_s3_bucket.website.id
  key    = "404.html"
  content_type = "text/html"
  
  content = <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Page Not Found - ${var.domain_name}</title>
    <style>
        body {
            font-family: -apple-system, system-ui, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            background: #f5f5f5;
            color: #333;
        }
        .error-container {
            max-width: 600px;
            padding: 40px;
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            text-align: center;
        }
        h1 { color: #333; margin-bottom: 20px; }
        p { color: #666; }
        .back-link {
            display: inline-block;
            margin-top: 20px;
            padding: 10px 20px;
            background: #007bff;
            color: white;
            text-decoration: none;
            border-radius: 4px;
        }
        .stage-info {
            margin-top: 20px;
            font-size: 0.9em;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="error-container">
        <h1>Page Not Found</h1>
        <p>The page you're looking for doesn't exist or has been moved.</p>
        <a href="/" class="back-link">Return Home</a>
        <div class="stage-info">
            Environment: ${var.environment}<br>
            Stage: ${var.stage_subdomain}.${var.domain_name}
        </div>
    </div>
</body>
</html>
EOF
}

resource "aws_s3_object" "error_500" {
  bucket = aws_s3_bucket.website.id
  key    = "500.html"
  content_type = "text/html"
  
  content = <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Server Error - ${var.domain_name}</title>
    <style>
        body {
            font-family: -apple-system, system-ui, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            background: #f5f5f5;
            color: #333;
        }
        .error-container {
            max-width: 600px;
            padding: 40px;
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            text-align: center;
        }
        h1 { color: #333; margin-bottom: 20px; }
        p { color: #666; }
        .back-link {
            display: inline-block;
            margin-top: 20px;
            padding: 10px 20px;
            background: #007bff;
            color: white;
            text-decoration: none;
            border-radius: 4px;
        }
        .stage-info {
            margin-top: 20px;
            font-size: 0.9em;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="error-container">
        <h1>Server Error</h1>
        <p>Something went wrong. Please try again later.</p>
        <a href="/" class="back-link">Return Home</a>
        <div class="stage-info">
            Environment: ${var.environment}<br>
            Stage: ${var.stage_subdomain}.${var.domain_name}
        </div>
    </div>
</body>
</html>
EOF
}

resource "aws_s3_object" "maintenance" {
  bucket = aws_s3_bucket.website.id
  key    = "maintenance.html"
  content_type = "text/html"
  
  content = <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Maintenance - ${var.domain_name}</title>
    <style>
        body {
            font-family: -apple-system, system-ui, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            background: #f5f5f5;
            color: #333;
        }
        .maintenance-container {
            max-width: 600px;
            padding: 40px;
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            text-align: center;
        }
        h1 { color: #333; margin-bottom: 20px; }
        p { color: #666; }
        .stage-info {
            margin-top: 20px;
            font-size: 0.9em;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="maintenance-container">
        <h1>Scheduled Maintenance</h1>
        <p>We're currently performing scheduled maintenance.</p>
        <p>Please check back shortly.</p>
        <div class="stage-info">
            Environment: ${var.environment}<br>
            Stage: ${var.stage_subdomain}.${var.domain_name}
        </div>
    </div>
</body>
</html>
EOF
}