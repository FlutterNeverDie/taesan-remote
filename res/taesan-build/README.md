# res/taesan-build

로컬 빌드 스크립트. 설정값(중계 서버 주소·키, 수신 전용 공통 비밀번호)은 저장소에 두지 않고 빌드 PC 의 env 파일에서 읽는다.

| 파일 | 용도 |
|---|---|
| `build-windows-local.ps1` | Windows x64 — 양방향·수신 전용, `-Inno` 로 설치 파일 |
| `build-android-local.sh` | Android(macOS 호스트) — 양방향(접속하는 쪽) |
| `collect-notices.py`, `about.*`, `notices-extra.txt` | release 빌드의 제3자 라이선스 고지(THIRD_PARTY_NOTICES) |

## env 파일 (git 밖)

`server.env` (Windows `C:\taesan-build\server.env`, Mac `~/taesan-build/server.env`)

```
TAESAN_RENDEZVOUS_SERVER=<중계 서버 IP 또는 도메인>
TAESAN_RS_PUB_KEY=<hbbs 의 id_ed25519.pub 내용>
```

`incoming.env` (Windows 수신 전용 빌드만)

```
TAESAN_INCOMING_PASSWORD=<전 기기 공통 비밀번호>
TAESAN_INCOMING_SALT=<16자 이상 영문·숫자·-·_ — 비밀번호를 바꿀 때만 바꾼다>
```

평문 비밀번호는 `res/taesan-variant/preset_hash.py` 로 해시만 빌드에 들어간다.
