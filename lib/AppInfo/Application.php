<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 HWP Documents contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\HWPDocuments\AppInfo;

use OCA\HWPDocuments\Listener\LoadViewerListener;
use OCP\AppFramework\App;
use OCP\AppFramework\Bootstrap\IBootContext;
use OCP\AppFramework\Bootstrap\IBootstrap;
use OCP\AppFramework\Bootstrap\IRegistrationContext;
use OCP\Files\IMimeTypeDetector;
use OCP\Server;

class Application extends App implements IBootstrap {
	public const APP_ID = 'hwpdocuments';

	public function __construct() {
		parent::__construct(self::APP_ID);
	}

	public function register(IRegistrationContext $context): void {
		$this->registerMimeTypes();
		// ::class is a string — does not autoload Viewer. Safe for early filesystem apps.
		$context->registerEventListener(
			\OCA\Viewer\Event\LoadViewer::class,
			LoadViewerListener::class,
		);
		$context->registerEventListener(
			\OCP\Security\CSP\AddContentSecurityPolicyEvent::class,
			\OCA\HWPDocuments\Listener\AddContentSecurityPolicyListener::class,
		);
	}

	public function boot(IBootContext $context): void {
	}

	private function registerMimeTypes(): void {
		$mimeTypeDetector = Server::get(IMimeTypeDetector::class);
		$mimeTypeDetector->getAllMappings();
		$mimeTypeDetector->registerTypeArray([
			'hwp' => ['application/x-hwp'],
			'hwpx' => ['application/x-hwpx'],
		]);
	}
}
