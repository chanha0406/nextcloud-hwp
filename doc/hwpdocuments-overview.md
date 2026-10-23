# HWP Documents 개요

- 작성일: 2026-10-23
- 근거: `appinfo/info.xml`, `README.md`, `package.json`, `src/main.js`, `lib/`, 브랜치 `main`. 원격 URL은 `git remote -v`, 해시는 `git rev-parse HEAD`와 `git rev-parse --short HEAD`
- 상태: 초안

## 목적

Nextcloud에서 `.hwp`와 `.hwpx`를 열고 편집한다. 저장은 WebDAV PUT으로 연 파일 경로에 다시 쓴다. 제품명은 `appinfo/info.xml`의 `HWP Documents`다. 앱 id는 `hwpdocuments`다. `info.xml`의 Nextcloud 의존 범위는 min 34, max 34다.

## 저장소

- 원격 `origin` fetch/push: `git@github.com:chanha0406/nextcloud-hwp.git`
- 브랜치: `main`
- `git rev-parse --short HEAD`: `75564cc`
- `git rev-parse HEAD`: `75564cc04e8495dc5e7147212780baa8770aaf44`
- 서브모듈: 없음. 루트 `.gitmodules`가 없다.

`info.xml`과 `README.md`에는 `https://github.com/chanha0406/nextcloud-hwp` 문자열이 있다. 위 원격 URL만 `git remote -v`로 확인한 값이다.

## 구성

파일시스템에서 확인한 경로다. 내부를 읽지 않은 항목은 미확인이다.

| 경로 | 확인한 내용 |
| --- | --- |
| `appinfo/info.xml` | 앱 id `hwpdocuments`, 이름 `HWP Documents`, version `1.2.5`, repair step `RegisterMimeType` |
| `src/main.js` | Viewer 핸들러와 WebDAV 저장 |
| `lib/AppInfo/Application.php` | 부트스트랩, MIME `registerTypeArray`, `LoadViewer`와 CSP 리스너 등록 |
| `lib/Listener/LoadViewerListener.php` | init script `hwpdocuments-main`, style `hwpdocuments` |
| `lib/Listener/AddContentSecurityPolicyListener.php` | WASM eval, frame `'self'`, worker `'self'`와 `blob:` |
| `lib/Migration/RegisterMimeType.php` | `mimetypemapping.json`, `mimetypealiases.json` 갱신, filecache 확장자 갱신 |
| `lib/Migration/MimeTypeMigration.php` | 위 두 JSON 파일명의 상수 |
| `package.json` | name `hwpdocuments`, version `1.2.5` |
| `vite.config.js` | 엔트리 `src/main.js`, 산출 `js/hwpdocuments-main.mjs`, `js/editor/`로 SDK 복사 |
| `js/hwpdocuments-main.mjs` | 파일 존재. 저장 경로의 `If-Match`, `saveError`, 성공 후 ETag 대입이 `src/main.js`와 같이 있다 |
| `css/hwpdocuments.css`, `img/app.svg`, `l10n/ko.js`, `l10n/ko.json` | 파일 존재. 내용은 이번 검토에서 읽지 않음 |
| `scripts/build-release.sh`, `scripts/fetch-studio.sh`, `scripts/gen-cert.sh`, `scripts/switch-install.sh` | 파일명만 확인. 내용은 미확인 |
| `js/editor/` | 디렉터리 존재. 내용은 미확인 |
| `studio/` | 디렉터리 존재. 내용은 미확인 |
| `node_modules/` | 디렉터리 존재. 내용은 미확인 |
| `build/` | 디렉터리 존재. 내용은 미확인 |

`README.md`는 `studio/`를 앱에 포함한 self-hosted rhwp-studio 정적 미러라고 적고, `@rhwp/editor`로 iframe에 붙인다고 적는다. `studio/` 내부와 WASM 번들은 이번 검토에서 읽지 않았다.

## 주요 기능

`src/main.js`와 `lib/`에서 확인한 동작이다.

- `OCA.Viewer` 핸들러 id `hwpdocuments`. MIME은 `application/x-hwp`, `application/x-hwp-v5`, `application/x-hwpx`.
- 파일 URL로 다운로드한 뒤 에디터에 연다. 다운로드 응답의 ETag를 보관한다.
- Save는 확장자가 `.hwpx`이면 `exportHwpx`, 그 외에는 `exportHwp`를 호출한다.
- 빈 본문과 시그니처가 다른 본문은 저장하지 않는다. HWP는 OLE `D0 CF 11 E0`, HWPX는 `PK`.
- 확장자와 `this.mime`이 `application/x-hwp`, `application/x-hwp-v5`, `application/x-hwpx` 사이에서 어긋나면 저장하지 않는다.
- 저장 실패는 `saveError`에 두고, 열기 실패용 `error`와 분리한다. `saveError`만으로 에디터를 숨기지 않는다.
- PUT에 다운로드 ETag를 `If-Match`로 넣고, 성공 응답에 ETag가 있으면 그 값으로 바꾼다.
- 설치와 post-migration에서 HWP MIME을 등록한다. JSON 디코드에 실패하면 공유 MIME 파일을 다시 쓰지 않는다. 쓰기는 임시 파일 후 `rename`이다.

## 미확인

- Viewer가 `active`, `src`, `source`, `davPath`, `mime`, `basename`을 이 컴포넌트에 어떻게 넘기는지.
- `isActiveSlide`는 `this.active !== false`다. 선언하지 않은 속성의 실제 값과, Viewer가 `active`를 넘기는지는 미확인이다.
- `studio/` 내부, WASM 번들, `js/editor/`, `node_modules/`의 동작.
- `scripts/` 내용, `css/`, `l10n/` 내용.
- Nextcloud가 다운로드와 PUT 응답에 항상 ETag를 주는지.
- `studio/` 안에 중첩 저장소가 있는지는 보지 않았다. 루트 `.gitmodules`는 없다.
