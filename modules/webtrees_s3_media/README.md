# Webtrees S3 Media Storage Module

This module allows webtrees to store media files on Amazon S3 instead of the local filesystem.

## Features

- Store media files on Amazon S3 or S3-compatible services
- Seamless integration with webtrees media management
- Support for custom S3 endpoints (MinIO, DigitalOcean Spaces, etc.)
- Configurable path prefixes for organization
- Secure credential storage

## Requirements

- webtrees 2.1+
- PHP 8.2+
- AWS SDK for PHP
- League Flysystem S3 adapter

## Installation

1. **Install dependencies:**
   ```bash
   composer install --no-dev
   ```

2. **Copy module to webtrees:**
   ```bash
   cp -r webtrees_s3_media /path/to/webtrees/modules_v4/
   ```

3. **Enable the module:**
   - Go to webtrees admin panel
   - Navigate to Modules
   - Find "S3 Media Storage" and enable it

## Configuration

1. **Create S3 Bucket:**
   - Create an S3 bucket in your AWS account
   - Configure appropriate permissions (see IAM Policy below)

2. **Create IAM User:**
   Create an IAM user with the following policy:
   ```json
   {
       "Version": "2012-10-17",
       "Statement": [
           {
               "Effect": "Allow",
               "Action": [
                   "s3:GetObject",
                   "s3:PutObject",
                   "s3:DeleteObject",
                   "s3:ListBucket"
               ],
               "Resource": [
                   "arn:aws:s3:::YOUR-BUCKET-NAME",
                   "arn:aws:s3:::YOUR-BUCKET-NAME/*"
               ]
           }
       ]
   }
   ```

3. **Configure Module:**
   - Click "Configure" next to the module
   - Enter your S3 credentials and settings
   - Enable the module

## Configuration Options

- **Enable S3 Media Storage**: Enable/disable the module
- **AWS Region**: Your S3 bucket region (e.g., us-east-1)
- **S3 Bucket Name**: Name of your S3 bucket
- **AWS Access Key ID**: IAM user access key
- **AWS Secret Access Key**: IAM user secret key
- **Custom S3 Endpoint**: For S3-compatible services (optional)
- **Use Path-Style URLs**: Enable for some S3-compatible services
- **Media Path Prefix**: Path prefix in bucket (default: media/)

## Migration

**Important**: This module does not automatically migrate existing media files. You must manually upload existing files to S3 before enabling the module.

### Migration Steps:

1. **Backup your existing media files**
2. **Upload to S3:**
   ```bash
   aws s3 sync /path/to/webtrees/data/media/ s3://your-bucket/media/ --recursive
   ```
3. **Configure and enable the module**
4. **Test by uploading a new media file**

## S3-Compatible Services

This module works with S3-compatible services:

### MinIO
- Set custom endpoint: `https://your-minio-server:9000`
- Enable path-style URLs

### DigitalOcean Spaces
- Set custom endpoint: `https://nyc3.digitaloceanspaces.com`
- Region: `nyc3` (or your region)

### Backblaze B2
- Set custom endpoint: `https://s3.us-west-000.backblazeb2.com`
- Use your B2 region

## Troubleshooting

### Common Issues:

1. **Access Denied Errors**
   - Check IAM permissions
   - Verify bucket policy
   - Ensure credentials are correct

2. **Connection Errors**
   - Verify region setting
   - Check custom endpoint URL
   - Test network connectivity

3. **Path Style Issues**
   - Enable path-style URLs for MinIO/compatible services
   - Check endpoint configuration

### Debug Mode:

Add to your webtrees config:
```php
// Enable detailed S3 error logs
'debug' => true,
```

## Security Considerations

- Store AWS credentials securely
- Use IAM users with minimal required permissions
- Enable S3 bucket versioning for backup
- Consider S3 server-side encryption
- Regularly rotate access keys

## Support

For issues and questions:
- Check the troubleshooting section
- Review AWS S3 documentation
- Ensure all dependencies are installed

## License

GPL-3.0-or-later - same as webtrees core