<?php

/**
 * S3 Media Filesystem Module for webtrees
 * 
 * This module replaces the default local filesystem with Amazon S3 for media storage.
 */

declare(strict_types=1);

require_once __DIR__ . '/S3MediaModule.php';

return new S3MediaModule();