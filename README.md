# Codex Usage Widget

Windows 11에서 Codex의 **5시간 사용량**과 **주간 사용량**을 간단히 확인하는 오픈 소스 위젯입니다.

![Windows 11](https://img.shields.io/badge/Windows-11-0078D4?logo=windows11)
![License](https://img.shields.io/badge/license-MIT-green)

## 기능

- Codex 5시간 한도와 주간 한도의 사용률, 남은 비율, 초기화 시각 표시
- 60초 자동 갱신과 `account/rateLimits/updated` 이벤트 기반 갱신
- 수동 새로고침 및 항상 위 옵션
- 현재 Windows 사용자의 Codex 설치 위치와 WSL 홈 자동 탐색
- 별도 API 키 없이 현재 Codex 로그인 사용

## 설치

GitHub Releases에서 최신 `CodexUsageWidget-Setup-*.exe`를 내려받아 실행합니다. 현재 사용자 영역에 설치되므로 관리자 권한이 필요하지 않습니다. 바탕 화면과 시작 메뉴에 바로가기가 생성되며, Windows 설정의 설치된 앱에서 제거할 수 있습니다.

Windows에서 미서명 오픈 소스 실행 파일 경고가 표시될 수 있습니다. 배포 파일의 SHA-256은 릴리스 노트에서 확인할 수 있습니다.

## 직접 실행

`app` 폴더를 내려받아 `Start-CodexUsageWidget.vbs`를 더블 클릭합니다.

요구 사항:

- Windows 11
- Codex Desktop 또는 Codex CLI 설치
- Codex에 로그인된 상태
- Codex Desktop의 WSL 기반 설치를 사용할 경우 WSL 사용 가능 상태

## 개인정보 보호

이 앱은 인증 파일, 액세스 토큰, 계정 ID 또는 이메일을 직접 읽지 않습니다. 로컬 `codex app-server --stdio`에 사용량만 요청하며 받은 값은 메모리에만 유지합니다. 로그, 분석 데이터, 사용량 기록을 파일에 저장하거나 제3자 서버로 전송하지 않습니다. 자세한 내용은 [PRIVACY.md](PRIVACY.md)를 확인하세요.

## 빌드

Windows PowerShell 5.1에서 다음 명령을 실행합니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\installer\Build-Installer.ps1
```

Windows에 기본 포함된 IExpress를 사용하며 결과는 `dist`에 생성됩니다.

## 주의

이 프로젝트는 비공식 커뮤니티 도구이며 OpenAI의 보증이나 지원을 받는 공식 제품이 아닙니다. Codex `app-server` 프로토콜은 버전에 따라 바뀔 수 있습니다.

## 라이선스

MIT
