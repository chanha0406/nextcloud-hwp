<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 HWP Documents contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\HWPDocuments\Migration;

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
			if ($content === false) {
				throw new \RuntimeException('Could not read ' . $filename);
			}
			$decoded = json_decode($content, true);
			if (!is_array($decoded)) {
				throw new \RuntimeException('Refusing to rewrite broken MIME config ' . $filename);
			}
			$obj = $decoded;
		}
		foreach ($data as $key => $value) {
			$obj[$key] = $value;
		}
		$encoded = json_encode($obj, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
		if ($encoded === false) {
			throw new \RuntimeException('Could not encode MIME config ' . $filename);
		}
		$tmp = $filename . '.hwpdocuments.tmp';
		if (file_put_contents($tmp, $encoded) === false) {
			throw new \RuntimeException('Could not write ' . $tmp);
		}
		if (!rename($tmp, $filename)) {
			@unlink($tmp);
			throw new \RuntimeException('Could not replace ' . $filename);
		}
	}
}
