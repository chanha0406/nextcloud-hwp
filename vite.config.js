/**
 * SPDX-FileCopyrightText: 2026 HWP Documents contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import { copyFileSync, existsSync, mkdirSync, readdirSync, rmSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const appName = 'hwpdocuments'
const outDir = path.join(__dirname, 'js')

function emptyJsDirPlugin() {
	return {
		name: 'empty-js-dir',
		buildStart() {
			if (!existsSync(outDir)) {
				return
			}
			for (const entry of readdirSync(outDir)) {
				rmSync(path.join(outDir, entry), { recursive: true, force: true })
			}
		},
	}
}

/**
 * Ship @rhwp/editor SDK as plain ESM (iframe talks to self-hosted studio/).
 */
function copyEditorSdkPlugin() {
	return {
		name: 'copy-rhwp-editor-sdk',
		closeBundle() {
			const editorDir = path.join(__dirname, 'node_modules', '@rhwp', 'editor')
			const destDir = path.join(outDir, 'editor')
			mkdirSync(destDir, { recursive: true })
			for (const name of ['index.js', 'transport.js']) {
				const src = path.join(editorDir, name)
				const dest = path.join(destDir, name)
				if (!existsSync(src)) {
					console.warn('[hwpdocuments] missing', src)
					continue
				}
				copyFileSync(src, dest)
				console.log('[hwpdocuments] copied editor/' + name)
			}
		},
	}
}

export default defineConfig(({ mode }) => ({
	plugins: [
		emptyJsDirPlugin(),
		copyEditorSdkPlugin(),
	],
	build: {
		outDir,
		emptyOutDir: false,
		sourcemap: true,
		lib: {
			entry: path.join(__dirname, 'src', 'main.js'),
			formats: ['es'],
			fileName: () => `${appName}-main.mjs`,
		},
		rollupOptions: {
			external: [/^@rhwp\//],
		},
		target: 'es2020',
		minify: mode === 'production',
		assetsInlineLimit: 0,
	},
}))
