<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 HWP Documents contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\HWPDocuments\Migration;

use OCP\Files\IMimeTypeLoader;
use OCP\Migration\IRepairStep;

/**
 * Persist HWP MIME mappings in config/ and update the filecache.
 * Uses \OC::$configDir (same approach as drawio / Nextcloud docs).
 */
abstract class MimeTypeMigration implements IRepairStep {
	public const CUSTOM_MIMETYPEMAPPING = 'mimetypemapping.json';
	public const CUSTOM_MIMETYPEALIASES = 'mimetypealiases.json';

	public function __construct(
		protected IMimeTypeLoader $mimeTypeLoader,
	) {
	}
}
