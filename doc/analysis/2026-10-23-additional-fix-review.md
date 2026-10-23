# 추가 수정 재검토

- 작성일: 2026-10-23
- 근거: `src/main.js`, `lib/AppInfo/Application.php`, `lib/Listener/LoadViewerListener.php`, `lib/Listener/AddContentSecurityPolicyListener.php`, `lib/Migration/MimeTypeMigration.php`, `lib/Migration/RegisterMimeType.php`, `appinfo/info.xml`. 브랜치 `main`. `git rev-parse --short HEAD` = `75564cc` (`75564cc04e8495dc5e7147212780baa8770aaf44`). 검토 시점 `git status`는 작업 트리 clean, `origin/main`과 일치
- 상태: 초안

## 판정

추가 수정 없음.

지금 코드에서 사용자 파일을 잃거나 열기·저장이 깨지는 경로를, 확인되지 않은 가정 없이, 이미 유지하기로 한 동작을 바꾸지 않는 수정으로 고칠 항목은 없다.

## 범위

읽은 파일은 `src/main.js`, `lib/` 다섯 파일, `appinfo/info.xml`이다. 버전 문자열 확인에 `package.json`, `vite.config.js`, `README.md`를 함께 봤다. `js/hwpdocuments-main.mjs`는 저장 분기가 소스와 같은지만 검색했다.

읽지 않은 경로: `js/editor/`, `node_modules/`, `studio/`, WASM 번들. `js/editor`와 `node_modules/@rhwp/editor`는 vite가 덮어쓰므로 수정 후보에서 제외한다.

앱 소스는 수정하지 않았다.

## 이미 반영된 동작

version `1.2.5`에 들어 있는 아래 동작은 다시 고치지 않는다.

- `src/main.js` `documentBytes`: 빈 본문을 거절한다. HWP 시그니처는 OLE `D0 CF 11 E0`, HWPX 시그니처는 `PK`.
- 확장자와 MIME이 어긋나면 저장을 거절한다. `.hwpx`가 아닌데 `application/x-hwpx`이거나, `.hwpx`인데 `application/x-hwp` 또는 `application/x-hwp-v5`이면 거절한다.
- 저장 실패는 `saveError`다. 렌더에서 에디터를 숨기는 조건은 `loading`과 `error`다. `saveError`는 그 조건에 없다.
- 다운로드 응답 ETag를 PUT `If-Match`에 쓴다. 성공 응답에 ETag가 있으면 `fileEtag`를 그 값으로 바꾼다.
- `lib/Migration/RegisterMimeType.php` `appendToFile`: JSON 디코드 결과가 배열이 아니면 공유 MIME 파일을 다시 쓰지 않고 예외를 던진다. 인코딩 결과는 임시 파일에 쓴 뒤 `rename`한다.

## 유지

- 숨은 슬라이드. `isActiveSlide`는 `this.active !== false`다. Vue 2에서 선언하지 않은 속성이 `this.active`로 보이는지, Viewer가 `active`를 넘기는지는 미확인이다. 기본값을 바꾸면 문서가 안 열릴 수 있어 그대로 둔다.
- `js/editor/`와 `node_modules/@rhwp/editor`는 수정하지 않는다. `studio/`와 WASM 번들은 리뷰하지 않았다.

## 탈락한 후보

### 저장 중 `fileUrl`이 바뀌면 다른 경로에 PUT할 수 있는 제어 흐름

`saveDocument`는 `exportHwp` 또는 `exportHwpx`를 `await`한 다음, 그 시점의 `this.fileUrl`과 `this.fileEtag`로 `uploadFile`을 호출한다. `fileUrl` watcher는 `scheduleLoad`를 부르고, `loadDocument`는 시작하자마자 `fileEtag`를 `null`로 만든다. `uploadFile`은 etag가 없으면 `If-Match`를 넣지 않는다.

이 조합은, 같은 인스턴스에서 저장 도중 `fileUrl`이 바뀌고 export가 바이트를 돌려주면, 이전 문서 바이트를 새 URL에 조건 없이 PUT할 수 있다. 그 경우 새로 연 파일을 덮어쓴다.

탈락한다. `fileUrl`은 `this.src`, `this.source`, `this.davPath`에서 오고, 이 값들이 같은 Vue 인스턴스에서 바뀌는지는 Viewer가 `active`를 넘기는지와 같은 종류의 미확인이다. 그 가정 위에 수정을 올리지 않는다. `isActiveSlide`는 유지 대상이다.

### 선언하지 않은 Viewer prop

`props` 선언이 없다. `fileUrl`, `fileName`, `this.mime`, `this.active`는 모두 선언 없이 읽는다. 선언하지 않은 값이 인스턴스에 없다는 이유로 기본값을 바꾸거나 prop 목록을 고정하면, 지금 열리던 문서가 안 열릴 수 있다. `active`와 같은 이유로 유지한다. 전달 방식은 미확인이다.

### ETag가 비었을 때의 동작

다운로드 ETag가 없으면 `If-Match`를 생략한다. 성공 응답에 ETag가 없으면 기존 `fileEtag`를 유지한다. 이 분기는 이미 반영한 동작이다. 응답 헤더가 항상 있는지는 미확인이다. 헤더가 없을 때 저장을 거절하도록 바꾸면 유지하기로 한 ETag 처리가 바뀐다.

### HWPX 검사를 `PK` 두 바이트보다 좁히는 것

HWPX 거절 조건은 `PK`다. 더 좁히면 지금 저장되는 파일이 거절될 수 있다. 이미 반영한 시그니처 규칙을 유지한다.

### `RegisterMimeType`의 짧은 쓰기와 동시 갱신

`appendToFile`은 `file_put_contents`의 반환값이 `false`인지만 본다. 반환 길이가 인코딩 길이보다 짧으면 그 임시 파일을 `rename`한다. 임시 파일 이름은 고정이다.

탈락한다. 이 경로는 사용자 문서가 아니라 `config/`의 MIME JSON을 바꾼다. 짧은 쓰기나 동시에 도는 repair가 실제로 일어나는지, 잘린 JSON이 파일 열기를 깨는지는 이 저장소에서 확인하지 않았다. JSON 디코드 실패 시 다시 쓰지 않는 동작과 임시 파일 후 `rename`은 유지 대상이다.

### `loadFile` 결과와 export 반환형

`loadFile`의 반환값은 로그만 하고 성공으로 진행한다. `documentBytes`는 `Uint8Array`가 아니면 `Uint8Array`로 만든다. export가 예외 없이 잘못된 성공 값을 주는지는 `js/editor/`와 WASM에 있다. 그 경로는 읽지 않았고, 반환 계약은 미확인이다.

### CSP를 페이지 전역 이벤트에 추가

`AddContentSecurityPolicyListener`는 `AddContentSecurityPolicyEvent`마다 WASM eval과 `blob:` worker를 더한다. 사용자 파일이 사라지거나 열기·저장이 실패하는 경로로 확인되지 않았다.

### `application/x-hwp-v5`와 `.hwpx` 조합

이 조합은 확장자·MIME 불일치로 저장이 거절된다. 그 거절은 유지 동작이다. 그런 MIME이 붙은 `.hwpx`가 있는지는 미확인이다.

### eurooffice와 같은 MIME

`README.md`는 같은 MIME을 여러 앱이 열 때 기본 앱이 겹칠 수 있다고 적는다. 이번 범위의 코드가 그 충돌로 사용자 파일 바이트를 덮어쓰는 경로는 확인하지 않았다.

## 빌드 산출

`js/hwpdocuments-main.mjs`에는 `If-Match`, `saveError`, 성공 후 `fileEtag` 대입이 있다. 1.2.5 소스가 번들에 반영되지 않은 상태는 아니다. `js/editor/`는 열지 않았다.
