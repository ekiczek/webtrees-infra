<?php

/**
 * S3 Media Filesystem Module for webtrees
 */

declare(strict_types=1);

use Fisharebest\Webtrees\Auth;
use Fisharebest\Webtrees\Contracts\FilesystemFactoryInterface;
use Fisharebest\Webtrees\FlashMessages;
use Fisharebest\Webtrees\Http\RequestHandlers\ModulesAllPage;
use Fisharebest\Webtrees\I18N;
use Fisharebest\Webtrees\Module\AbstractModule;
use Fisharebest\Webtrees\Module\ModuleConfigInterface;
use Fisharebest\Webtrees\Module\ModuleConfigTrait;
use Fisharebest\Webtrees\Module\ModuleCustomInterface;
use Fisharebest\Webtrees\Module\ModuleCustomTrait;
use Fisharebest\Webtrees\Registry;
use Fisharebest\Webtrees\Validator;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;

use function csrf_field;
use function e;
use function redirect;
use function response;
use function route;

require_once __DIR__ . '/S3FilesystemFactory.php';
require_once __DIR__ . '/vendor/autoload.php';

/**
 * S3 Media Module - provides S3 filesystem for media files
 */
class S3MediaModule extends AbstractModule implements ModuleCustomInterface, ModuleConfigInterface
{
    use ModuleCustomTrait;
    use ModuleConfigTrait;

    public function title(): string
    {
        return I18N::translate('S3 Media Storage');
    }

    public function description(): string
    {
        return I18N::translate('Store media files on Amazon S3 instead of local filesystem.');
    }

    public function customModuleAuthorName(): string
    {
        return 'Webtrees S3 Module';
    }

    public function customModuleVersion(): string
    {
        return '1.0.0';
    }

    public function customModuleSupportUrl(): string
    {
        return '';
    }

    public function customModuleLatestVersionUrl(): string
    {
        return '';
    }

    public function boot(): void
    {
        // Check if S3 is enabled and configured
        if ($this->getPreference('s3_enabled', '0') === '1' && $this->isConfigured()) {
            // Replace the default filesystem factory with our S3 version
            $factory = new S3FilesystemFactory(
                $this->getPreference('s3_region', ''),
                $this->getPreference('s3_bucket', ''),
                $this->getPreference('s3_key', ''),
                $this->getPreference('s3_secret', ''),
                $this->getPreference('s3_endpoint', ''),
                $this->getPreference('s3_path_style', '0') === '1'
            );
            
            Registry::filesystem($factory);
        }
    }

    public function isConfigured(): bool
    {
        return $this->getPreference('s3_region', '') !== '' &&
               $this->getPreference('s3_bucket', '') !== '';
    }

    public function getAdminAction(ServerRequestInterface $request): ResponseInterface
    {
        $this->layout = 'layouts/administration';

        // Generate the HTML content directly instead of using a view file
        $title = $this->title();
        $s3_enabled = $this->getPreference('s3_enabled', '0');
        $s3_region = $this->getPreference('s3_region', '');
        $s3_bucket = $this->getPreference('s3_bucket', '');
        $s3_key = $this->getPreference('s3_key', '');
        $s3_secret = $this->getPreference('s3_secret', '');
        $s3_endpoint = $this->getPreference('s3_endpoint', '');
        $s3_path_style = $this->getPreference('s3_path_style', '0');
        $s3_media_prefix = $this->getPreference('s3_media_prefix', 'media/');

        $html = $this->configForm($title, $s3_enabled, $s3_region, $s3_bucket, $s3_key, $s3_secret, $s3_endpoint, $s3_path_style, $s3_media_prefix);

        return response($html);
    }

    private function configForm(string $title, string $s3_enabled, string $s3_region, string $s3_bucket, string $s3_key, string $s3_secret, string $s3_endpoint, string $s3_path_style, string $s3_media_prefix): string
    {
        return '
            <div class="row form-group">
                <div class="col-sm-12">
                    <h1>' . e($title) . '</h1>
                </div>
            </div>

            <form method="post" action="' . e(route('module', ['module' => $this->name(), 'action' => 'Admin'])) . '" class="form-horizontal">
                ' . csrf_field() . '

                <div class="row form-group">
                    <label class="col-sm-3 col-form-label" for="s3_enabled">
                        ' . I18N::translate('Enable S3 Media Storage') . '
                    </label>
                    <div class="col-sm-9">
                        <select class="form-control" name="s3_enabled" id="s3_enabled">
                            <option value="0"' . ($s3_enabled === '0' ? ' selected' : '') . '>' . I18N::translate('Disabled') . '</option>
                            <option value="1"' . ($s3_enabled === '1' ? ' selected' : '') . '>' . I18N::translate('Enabled') . '</option>
                        </select>
                        <div class="form-text">
                            ' . I18N::translate('Enable or disable S3 storage for media files.') . '
                        </div>
                    </div>
                </div>

                <fieldset>
                    <legend>' . I18N::translate('AWS S3 Configuration') . '</legend>

                    <div class="row form-group">
                        <label class="col-sm-3 col-form-label" for="s3_region">
                            ' . I18N::translate('AWS Region') . '
                        </label>
                        <div class="col-sm-9">
                            <input class="form-control" id="s3_region" name="s3_region" type="text" value="' . e($s3_region) . '" placeholder="us-east-1" required>
                            <div class="form-text">
                                ' . I18N::translate('The AWS region where your S3 bucket is located (e.g., us-east-1, eu-west-1).') . '
                            </div>
                        </div>
                    </div>

                    <div class="row form-group">
                        <label class="col-sm-3 col-form-label" for="s3_bucket">
                            ' . I18N::translate('S3 Bucket Name') . '
                        </label>
                        <div class="col-sm-9">
                            <input class="form-control" id="s3_bucket" name="s3_bucket" type="text" value="' . e($s3_bucket) . '" placeholder="my-webtrees-media" required>
                            <div class="form-text">
                                ' . I18N::translate('The name of your S3 bucket where media files will be stored.') . '
                            </div>
                        </div>
                    </div>

                    <div class="row form-group">
                        <label class="col-sm-3 col-form-label" for="s3_key">
                            ' . I18N::translate('AWS Access Key ID') . '
                        </label>
                        <div class="col-sm-9">
                            <input class="form-control" id="s3_key" name="s3_key" type="text" value="' . e($s3_key) . '" placeholder="AKIAIOSFODNN7EXAMPLE">
                            <div class="form-text">
                                ' . I18N::translate('Your AWS Access Key ID with permissions to read/write the S3 bucket. Leave empty to use IAM roles or instance credentials.') . '
                            </div>
                        </div>
                    </div>

                    <div class="row form-group">
                        <label class="col-sm-3 col-form-label" for="s3_secret">
                            ' . I18N::translate('AWS Secret Access Key') . '
                        </label>
                        <div class="col-sm-9">
                            <input class="form-control" id="s3_secret" name="s3_secret" type="password" value="' . e($s3_secret) . '" placeholder="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY">
                            <div class="form-text">
                                ' . I18N::translate('Your AWS Secret Access Key. Leave empty to use IAM roles or instance credentials.') . '
                            </div>
                        </div>
                    </div>

                    <div class="row form-group">
                        <label class="col-sm-3 col-form-label" for="s3_endpoint">
                            ' . I18N::translate('Custom S3 Endpoint') . '
                        </label>
                        <div class="col-sm-9">
                            <input class="form-control" id="s3_endpoint" name="s3_endpoint" type="url" value="' . e($s3_endpoint) . '" placeholder="https://s3.example.com">
                            <div class="form-text">
                                ' . I18N::translate('Optional: Custom endpoint URL for S3-compatible storage services (leave empty for AWS S3).') . '
                            </div>
                        </div>
                    </div>

                    <div class="row form-group">
                        <label class="col-sm-3 col-form-label" for="s3_path_style">
                            ' . I18N::translate('Use Path-Style URLs') . '
                        </label>
                        <div class="col-sm-9">
                            <select class="form-control" name="s3_path_style" id="s3_path_style">
                                <option value="0"' . ($s3_path_style === '0' ? ' selected' : '') . '>' . I18N::translate('No (Virtual-hosted style)') . '</option>
                                <option value="1"' . ($s3_path_style === '1' ? ' selected' : '') . '>' . I18N::translate('Yes (Path style)') . '</option>
                            </select>
                            <div class="form-text">
                                ' . I18N::translate('Some S3-compatible services require path-style URLs. Enable this if using MinIO or similar services.') . '
                            </div>
                        </div>
                    </div>

                    <div class="row form-group">
                        <label class="col-sm-3 col-form-label" for="s3_media_prefix">
                            ' . I18N::translate('Media Path Prefix') . '
                        </label>
                        <div class="col-sm-9">
                            <input class="form-control" id="s3_media_prefix" name="s3_media_prefix" type="text" value="' . e($s3_media_prefix) . '" placeholder="media/">
                            <div class="form-text">
                                ' . I18N::translate('Path prefix for media files in the S3 bucket. Usually "media/" to match local structure.') . '
                            </div>
                        </div>
                    </div>
                </fieldset>

                <div class="row form-group">
                    <div class="offset-sm-3 col-sm-9">
                        <button type="submit" class="btn btn-primary">
                            ' . I18N::translate('save') . '
                        </button>
                        <a class="btn btn-secondary" href="' . e(route(ModulesAllPage::class)) . '">
                            ' . I18N::translate('cancel') . '
                        </a>
                    </div>
                </div>
            </form>

            <div class="card mt-4">
                <div class="card-header">
                    <h5 class="card-title">' . I18N::translate('Setup Instructions') . '</h5>
                </div>
                <div class="card-body">
                    <ol>
                        <li>' . I18N::translate('Create an S3 bucket in your AWS account') . '</li>
                        <li>' . I18N::translate('Choose authentication method:') . '
                            <ul>
                                <li>' . I18N::translate('For credential-based auth: Create an IAM user with permissions to read/write to the bucket') . '</li>
                                <li>' . I18N::translate('For role-based auth: Attach an IAM role to your EC2 instance or use AWS credentials provider chain') . '</li>
                            </ul>
                        </li>
                        <li>' . I18N::translate('Configure the settings above (credentials are optional if using IAM roles)') . '</li>
                        <li>' . I18N::translate('Enable the module and test by uploading a media file') . '</li>
                    </ol>
                    
                    <h6>' . I18N::translate('Required IAM Permissions') . '</h6>
                    <pre><code>{
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
}</code></pre>
                    
                    <div class="alert alert-warning mt-3">
                        <strong>' . I18N::translate('Important:') . '</strong>
                        ' . I18N::translate('Before enabling S3 storage, ensure you have migrated any existing media files to your S3 bucket. This module does not automatically migrate existing files.') . '
                    </div>
                </div>
            </div>
        ';
    }

    public function postAdminAction(ServerRequestInterface $request): ResponseInterface
    {
        $params = (array) $request->getParsedBody();

        $this->setPreference('s3_enabled', Validator::parsedBody($request)->string('s3_enabled', '0'));
        $this->setPreference('s3_region', Validator::parsedBody($request)->string('s3_region', ''));
        $this->setPreference('s3_bucket', Validator::parsedBody($request)->string('s3_bucket', ''));
        $this->setPreference('s3_key', Validator::parsedBody($request)->string('s3_key', ''));
        $this->setPreference('s3_secret', Validator::parsedBody($request)->string('s3_secret', ''));
        $this->setPreference('s3_endpoint', Validator::parsedBody($request)->string('s3_endpoint', ''));
        $this->setPreference('s3_path_style', Validator::parsedBody($request)->string('s3_path_style', '0'));
        $this->setPreference('s3_media_prefix', Validator::parsedBody($request)->string('s3_media_prefix', 'media/'));

        $message = I18N::translate('The preferences for the module "%s" have been updated.', $this->title());
        FlashMessages::addMessage($message, 'success');

        return redirect(route(ModulesAllPage::class));
    }
}