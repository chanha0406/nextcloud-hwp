<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 HWP Documents contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\HwpViewer\Listener;

use OCA\HwpViewer\AppInfo\Application;
use OCA\Viewer\Event\LoadViewer;
use OCP\EventDispatcher\Event;
use OCP\EventDispatcher\IEventListener;
use OCP\Util;

/** @template-implements IEventListener<Event> */
class LoadViewerListener implements IEventListener {
	public function handle(Event $event): void {
		if (!($event instanceof LoadViewer)) {
			return;
		}

		Util::addInitScript(Application::APP_ID, Application::APP_ID . '-main');
		Util::addStyle(Application::APP_ID, 'viewer');
	}
}
