# nextcloud-hwp-viewer

Nextcloud 34용 커스텀 앱 — Viewer에서 `.hwp` / `.hwpx` **열람·편집**, Save로 WebDAV 저장.

별도 studio 서버 없이, 앱에 포함한 **self-hosted rhwp-studio**(`studio/`)를 iframe으로 띄웁니다.

| 구성 | 설명 |
|------|------|
| `@rhwp/editor` | iframe 임베드 SDK |
| `studio/` | rhwp-studio 정적 미러 (~27MB) |
| PHP | MIME 등록, CSP(`wasm-unsafe-eval`, `frame-src 'self'`) |

업스트림 엔진: [edwardkim/rhwp](https://github.com/edwardkim/rhwp) (MIT)

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

## ONLYOFFICE(eurooffice)와 MIME

같은 MIME을 Viewer에 등록하면 기본 열기 앱 충돌이 날 수 있습니다. 파일 형식별 기본 앱을 조정하세요.

## 라이선스

- 앱 코드: **AGPL-3.0-or-later**
- `@rhwp/*` / `studio/` 업스트림: **MIT**
