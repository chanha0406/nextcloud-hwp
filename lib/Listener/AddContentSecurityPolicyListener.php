<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 HWP Viewer contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\HwpViewer\Listener;

use OCP\AppFramework\Http\EmptyContentSecurityPolicy;
use OCP\EventDispatcher\Event;
use OCP\EventDispatcher\IEventListener;
use OCP\Security\CSP\AddContentSecurityPolicyEvent;

/** @template-implements IEventListener<Event> */
class AddContentSecurityPolicyListener implements IEventListener {
	public function handle(Event $event): void {
		if (!($event instanceof AddContentSecurityPolicyEvent)) {
			return;
		}

		$policy = new EmptyContentSecurityPolicy();
		// rhwp-studio WASM
		$policy->allowEvalWasm(true);
		// Self-hosted studio iframe under /custom_apps/hwp_viewer/studio/
		$policy->addAllowedFrameDomain('\'self\'');
		$policy->addAllowedWorkerSrcDomain('\'self\'');
		$policy->addAllowedWorkerSrcDomain('blob:');
		$event->addPolicy($policy);
	}
}
