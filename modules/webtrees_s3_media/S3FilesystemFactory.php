<?php

/**
 * S3 Filesystem Factory for webtrees
 */

declare(strict_types=1);

use Aws\S3\S3Client;
use Fisharebest\Webtrees\Contracts\FilesystemFactoryInterface;
use Fisharebest\Webtrees\Site;
use League\Flysystem\AwsS3V3\AwsS3V3Adapter;
use League\Flysystem\Filesystem;
use League\Flysystem\FilesystemOperator;
use League\Flysystem\Local\LocalFilesystemAdapter;
use League\Flysystem\PathPrefixing\PathPrefixedAdapter;

use function realpath;

use const DIRECTORY_SEPARATOR;

/**
 * S3 Filesystem Factory - creates S3-backed filesystems for media storage
 */
class S3FilesystemFactory implements FilesystemFactoryInterface
{
    private const string ROOT_DIR = __DIR__ . '/../../..';

    private string $region;
    private string $bucket;
    private string $key;
    private string $secret;
    private string $endpoint;
    private bool $pathStyle;

    public function __construct(
        string $region,
        string $bucket,
        string $key,
        string $secret,
        string $endpoint = '',
        bool $pathStyle = false
    ) {
        $this->region = $region;
        $this->bucket = $bucket;
        $this->key = $key;
        $this->secret = $secret;
        $this->endpoint = $endpoint;
        $this->pathStyle = $pathStyle;
    }

    /**
     * Create a filesystem for the user's data folder - this will use S3 for media
     *
     * @param string $path_prefix
     *
     * @return FilesystemOperator
     */
    public function data(string $path_prefix = ''): FilesystemOperator
    {
        // For media files, use S3
        if ($path_prefix === 'media/' || strpos($path_prefix, 'media/') === 0) {
            return $this->createS3Filesystem($path_prefix);
        }

        // For other data files (like configs, logs, etc.), use local filesystem
        $adapter = new LocalFilesystemAdapter(Site::getPreference('INDEX_DIRECTORY'));

        if ($path_prefix !== '') {
            $adapter = new PathPrefixedAdapter($adapter, $path_prefix);
        }

        return new Filesystem($adapter);
    }

    /**
     * Describe a filesystem for the user's data folder.
     *
     * @return string
     */
    public function dataName(): string
    {
        return 'S3: ' . $this->bucket . '/' . $this->region;
    }

    /**
     * Create a filesystem for the application's root folder.
     *
     * @param string $path_prefix
     *
     * @return FilesystemOperator
     */
    public function root(string $path_prefix = ''): FilesystemOperator
    {
        $adapter = new LocalFilesystemAdapter(self::ROOT_DIR);

        if ($path_prefix !== '') {
            $adapter = new PathPrefixedAdapter($adapter, $path_prefix);
        }

        return new Filesystem($adapter);
    }

    /**
     * Describe a filesystem for the application's root folder.
     *
     * @return string
     */
    public function rootName(): string
    {
        return realpath(self::ROOT_DIR) . '/';
    }

    /**
     * Create an S3-backed filesystem
     *
     * @param string $path_prefix
     *
     * @return FilesystemOperator
     */
    private function createS3Filesystem(string $path_prefix = ''): FilesystemOperator
    {
        $config = [
            'region' => $this->region,
            'version' => 'latest',
        ];

        // Only add credentials if both key and secret are provided
        // Otherwise, AWS SDK will use the default credential provider chain
        // (IAM roles, environment variables, AWS credentials file, etc.)
        if ($this->key !== '' && $this->secret !== '') {
            $config['credentials'] = [
                'key'    => $this->key,
                'secret' => $this->secret,
            ];
        }

        // Add custom endpoint if specified (for S3-compatible services)
        if ($this->endpoint !== '') {
            $config['endpoint'] = $this->endpoint;
        }

        // Use path-style addressing if specified
        if ($this->pathStyle) {
            $config['use_path_style_endpoint'] = true;
        }

        $client = new S3Client($config);
        $adapter = new AwsS3V3Adapter($client, $this->bucket, $path_prefix);

        return new Filesystem($adapter);
    }
}