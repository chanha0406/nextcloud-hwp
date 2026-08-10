<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 HWP Documents contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\HwpViewer\Migration;

use OCP\Migration\IOutput;

class RegisterMimeType extends MimeTypeMigration {
	public function getName(): string {
		return 'Register MIME types for HWP Documents';
	}

	public function run(IOutput $output): void {
		$output->info('Registering HWP/HWPX mimetypes…');
		$this->registerForExistingFiles();
		$this->registerForNewFiles();
		$output->info('HWP/HWPX mimetypes registered.');
	}

	private function registerForExistingFiles(): void {
		$hwpId = $this->mimeTypeLoader->getId('application/x-hwp');
		$this->mimeTypeLoader->updateFilecache('hwp', $hwpId);

		$hwpxId = $this->mimeTypeLoader->getId('application/x-hwpx');
		$this->mimeTypeLoader->updateFilecache('hwpx', $hwpxId);
	}

	private function registerForNewFiles(): void {
		$configDir = \OC::$configDir;
		$this->appendToFile($configDir . self::CUSTOM_MIMETYPEALIASES, [
			'application/x-hwp' => 'x-office-document',
			'application/x-hwp-v5' => 'x-office-document',
			'application/x-hwpx' => 'x-office-document',
		]);
		$this->appendToFile($configDir . self::CUSTOM_MIMETYPEMAPPING, [
			'hwp' => ['application/x-hwp'],
			'hwpx' => ['application/x-hwpx'],
		]);
	}

	/**
	 * @param array<string, mixed> $data
	 */
	private function appendToFile(string $filename, array $data): void {
		$obj = [];
		if (file_exists($filename)) {
			$content = file_get_contents($filename);
			$decoded = json_decode((string)$content, true);
			if (is_array($decoded)) {
				$obj = $decoded;
			}
		}
		foreach ($data as $key => $value) {
			$obj[$key] = $value;
		}
		file_put_contents($filename, json_encode($obj, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
	}
}
