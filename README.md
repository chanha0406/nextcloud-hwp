# nextcloud-hwp-viewer

Nextcloud 34용 커스텀 앱 **HWP Documents** — `.hwp` / `.hwpx` **열람·편집**, Save로 WebDAV 저장.

별도 studio 서버 없이, 앱에 포함한 **self-hosted rhwp-studio**(`studio/`)를 iframe으로 띄웁니다.

| 구성 | 설명 |
|------|------|
| `@rhwp/editor` | iframe 임베드 SDK |
| `studio/` | rhwp-studio 정적 미러 (~27MB) |
| PHP | MIME 등록, CSP(`wasm-unsafe-eval`, `frame-src 'self'`) |

업스트림 엔진: [edwardkim/rhwp](https://github.com/edwardkim/rhwp) (MIT)

## 참고한 프로젝트

| 프로젝트 | 참고한 점 |
|----------|-----------|
| [edwardkim/rhwp](https://github.com/edwardkim/rhwp) / [@rhwp/core](https://www.npmjs.com/package/@rhwp/core) | 초기 읽기 전용 SVG 렌더, WASM 파서 |
| [@rhwp/editor](https://www.npmjs.com/package/@rhwp/editor) / rhwp-studio | 편집 UI iframe 임베드, `loadFile` / `exportHwp` / `notifySaved` |
| [nextcloud/viewer](https://github.com/nextcloud/viewer) | `OCA.Viewer.registerHandler`, `LoadViewer` 이벤트, `active` 슬라이드 프리로드 |
| [nextcloud/richdocuments](https://github.com/nextcloud/richdocuments) (Collabora) | CSP `allowEvalWasm(true)` 패턴 |
| [nextcloud/files_pdfviewer](https://github.com/nextcloud/files_pdfviewer) | Viewer 핸들러·`wasm-unsafe-eval` 선행 사례 |
| eurooffice (ONLYOFFICE, 이 서버에 설치됨) | 동일 HWP MIME을 Viewer에 등록할 때의 충돌·우선순위 이슈 |

이 앱은 위 프로젝트들의 **포크가 아니라** API·패턴을 참고해 Nextcloud 커스텀 앱으로 새로 구성한 것입니다. HWP 엔진/스튜디오 바이너리는 rhwp 업스트림(MIT)을 사용·미러합니다.

## 수정 후 적용 방법

변경 종류에 따라 해야 할 일이 다릅니다.

| 수정한 것 | 해야 할 동작 |
|-----------|----------------|
| `src/` (JS) | `npm run build` → 브라우저 **하드 새로고침** (Ctrl+Shift+R) |
| `css/viewer.css` | 빌드 불필요. 하드 새로고침 |
| `js/`를 직접 수정 | 빌드 없이 하드 새로고침 (다음 `npm run build` 시 덮어씌워질 수 있음) |
| `studio/` | 빌드 불필요. 하드 새로고침. 업스트림 갱신은 `./scripts/fetch-studio.sh` |
| `lib/` · `appinfo/info.xml` (PHP, 버전) | `info.xml` **version**을 올린 뒤 `occ upgrade` (또는 앱 비활성/활성). PHP만 바꾸면 버전 없이 되는 경우도 있으나, 리스너/CSP는 버전 업+upgrade가 안전 |
| MIME / repair | `occ maintenance:repair --include-expensive` 또는 `occ maintenance:mimetype:update-db --repair-filecache` |
| Docker에서 파일만 바뀜 | 컨테이너 재시작은 보통 불필요. 정적 파일은 즉시 반영, PHP는 opcache 때문에 수 초~재시작이 필요할 수 있음 |

Docker 예시:

```bash
cd /ssd1/nextcloud/custom_apps/hwp_viewer   # 또는 ~/Workspace/nextcloud-hwp-viewer
npm run build

# appinfo version을 올린 경우
docker exec -u www-data nextcloud-app php occ upgrade
```

CSP·init 스크립트는 **문서(페이지)를 다시 로드**해야 헤더/스크립트가 갱신됩니다. Viewer 모달만 닫았다 여는 것으로는 부족한 경우가 많습니다.

## 요구 사항

- Nextcloud **34**
- Node.js 22+ (프론트 빌드 시)
- 쓰기 가능한 `custom_apps/` (또는 동등 경로)

## 설치

```bash
# 1) 이 저장소를 Nextcloud custom_apps 로 복사/클론
git clone https://github.com/<you>/nextcloud-hwp-viewer.git \
  /path/to/nextcloud/custom_apps/hwp_viewer

cd /path/to/nextcloud/custom_apps/hwp_viewer
npm ci
npm run build

# 2) 앱 활성화 (Docker 예시)
docker exec -u www-data nextcloud-app php occ app:enable hwp_viewer
docker exec -u www-data nextcloud-app php occ upgrade   # 버전 올릴 때
```

또는 개발 중에는 Workspace에서 심볼릭 링크:

```bash
ln -s ~/Workspace/nextcloud-hwp-viewer /path/to/nextcloud/custom_apps/hwp_viewer
```

## 사용

파일 목록에서 `.hwp` / `.hwpx` 클릭 → Viewer 모달에 rhwp-studio → 상단 **Save**로 원본 경로에 저장.

## MIME / 다운로드만 되는 경우

기존 파일이 `application/octet-stream`이면 Viewer가 안 열릴 수 있습니다.

```bash
docker exec -u www-data nextcloud-app php occ maintenance:repair --include-expensive
docker exec -u www-data nextcloud-app php occ maintenance:mimetype:update-db --repair-filecache
```

## studio 갱신

업스트림 Pages 배포가 바뀌면:

```bash
chmod +x scripts/fetch-studio.sh
./scripts/fetch-studio.sh
```

경로 치환은 `/custom_apps/hwp_viewer/studio/` 기준입니다. Nextcloud을 서브디렉터리에 두면 `scripts/fetch-studio.sh`의 `APP_BASE`를 맞춘 뒤 다시 받으세요.

## 개발

```bash
npm run watch    # vite 감시 빌드
npm run build    # 프로덕션
```

산출물: `js/hwp_viewer-main.mjs`, `js/editor/*`

## App Store 배포 패키지 · 서명

스토어 업로드용 `tar.gz`와 (인증서가 있으면) 코드 서명을 만듭니다.

```bash
# 1) 한 번만: 키 + CSR 생성 (~/.nextcloud/certificates/hwp_viewer.*)
npm run cert
# CSR을 https://github.com/nextcloud/app-certificate-requests 에 PR로 제출
# 승인된 .crt 를 같은 폴더에 hwp_viewer.crt 로 저장

# 2) 프론트 빌드 + 스테이징 + (가능하면) integrity:sign-app + tar.gz
npm run release
# 서명 없이 패키지만: npm run release:unsigned
```

산출물: `build/artifacts/appstore/hwp_viewer-<version>.tar.gz`  
인증서가 있으면 같은 경로에 `.tar.gz.sig`(App Store용 openssl 서명)도 생성됩니다.

`integrity:sign-app`에는 `occ`가 필요합니다. 기본으로 Docker 컨테이너 `nextcloud-app`을 찾습니다. 다른 환경이면:

```bash
export OCC="php /path/to/nextcloud/occ"
# 또는
export NEXTCLOUD_ROOT=/path/to/nextcloud
npm run release
```

업로드: [apps.nextcloud.com](https://apps.nextcloud.com/developer/apps/releases/new) 에 아카이브 URL + `.sig` 내용을 넣습니다.

## ONLYOFFICE(eurooffice)와 MIME

같은 MIME을 Viewer에 등록하면 기본 열기 앱 충돌이 날 수 있습니다. 파일 형식별 기본 앱을 조정하세요.

## 라이선스

- 앱 코드: **AGPL-3.0-or-later**
- `@rhwp/*` / `studio/` 업스트림: **MIT**
