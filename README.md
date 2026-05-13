# 🐱 claude-pet

> **Claude Code 옆에 떠 있는 고양이.** 작업 중이면 노트북을 두드리고, 멈추면 위를 올려다보며 사용자를 기다린다.

[Claude Code](https://docs.claude.com/claude-code) 위에 얹는 가벼운 Electron 오버레이. 화면 한 켠에 투명/프레임리스/항상 위 창으로 떠서 에이전트의 상태에 따라 그림이 바뀐다.

## 📸 두 가지 상태

| 상태 | 언제 | 모습 |
|------|------|-----|
| `working` | Claude가 작업 중 (UserPromptSubmit ~ Stop 사이, 또는 도구 사용 중) | 발 두드리는 고양이 (기본 SVG, `working.gif` 있으면 교체) |
| `idle` | 사용자 응답을 기다리거나 작업이 끝난 상태 | 자는 고양이 (기본 SVG, `idle.png` 있으면 교체) |

> 여러 세션이 있으면 머리 위 작은 배지에 `●`(working) / `○`(idle) 도트로 표시 (단일 세션은 배지 숨김).

> 인터럽트(ESC)·`SIGHUP`(터미널 창 강제 닫기)·`SIGKILL` 같은 경로에서는 Claude Code가 Stop / SessionEnd hook을 보장하지 않는다. claude-pet은 마지막 heartbeat 시점으로부터 5분이 지나면 자동으로 idle로 강등한다 (`WORKING_MAX_MS`).

## ⚡ 빠른 설치

### 사전 요구사항

| 항목 | 최소 버전 | 확인 |
|------|----------|------|
| macOS | 13+ | `sw_vers` |
| Node.js | 20+ | `node --version` |
| Claude Code | 2.0+ | `claude --version` |
| Python 3 | 3.9+ (시스템 기본) | `/usr/bin/python3 --version` |

> Linux/Windows는 아직 미지원 (`setVisibleOnAllWorkspaces` 등 macOS 전용 코드 사용).

### 권장 — GitHub 마켓플레이스 (2줄)

Claude Code 안에서:

```
/plugin marketplace add superpangE/claude-pet
/plugin install claude-pet@claude-pet
```

확인:

```
/plugin
```

`claude-pet@claude-pet` 가 enabled면 끝. 첫 세션 시작 시 `pet-app/node_modules`가 없으면 자동으로 `npm install`이 실행된다 (1~2분 소요, 한 번만).

### 개발자용 — 로컬 클론

저장소를 직접 만지고 싶다면:

```sh
git clone https://github.com/superpangE/claude-pet.git
cd claude-pet
cd pet-app && npm install && cd ..
```

세 가지 등록 방식 중 택1:

```sh
# A. 한 세션만 (가장 빠름)
claude --plugin-dir /path/to/claude-pet

# B. 로컬 directory 마켓플레이스
claude plugin marketplace add /path/to/claude-pet
claude plugin install claude-pet@claude-pet
```

설치된 `pet-app/node_modules/.bin/electron`을 우선 사용한다. 없으면 `PATH`의 `electron` 으로 fallback.

### 🔄 업데이트

Claude Code 안에서:

```
/plugin marketplace update claude-pet     # GitHub에서 최신 manifest 가져오기
/plugin update claude-pet@claude-pet      # 새 버전 캐시에 설치
/reload-plugins                           # hook 경로가 새 버전을 가리키도록 메모리 reload
```

다음 hook(메시지 전송, tool 사용 등)이 발화될 때 `ensure-app-running.sh`가 떠 있는 펫의 캐시 경로와 활성 plugin 경로를 비교 — 다르면 구버전으로 판단하고 자동 종료 + 새 버전 spawn. 수동 `kill` 불필요.

(원하면 강제로 즉시 재시작: `kill $(pgrep -f "node.*pet-app/node_modules/.bin/electron") 2>/dev/null || true`)

### 🗑 제거

```sh
# 1. 일시적으로 끄기 (다시 켤 가능성이 있을 때)
claude plugin disable claude-pet@claude-pet

# 2. 완전 제거
claude plugin uninstall claude-pet@claude-pet
claude plugin marketplace remove claude-pet

# 3. 런타임 데이터까지 지우기 (선택)
rm -rf ~/.claude/plugins/claude-pet/

# 4. 펫 앱 프로세스가 떠 있으면 정리
kill $(cat ~/.claude/plugins/claude-pet/data/app.pid 2>/dev/null) 2>/dev/null || true
```

저장소 클론 폴더(`pet-app/node_modules/`, `_originals/` 등)는 직접 `rm -rf`로 지우면 된다.

## 🔄 동작 흐름

```
Claude Code session  ──hook──▶  scripts/on-*.sh  ──▶  data/sessions/<sid>.json
                                                         │
                                                         ▼
                                  Electron app가 fs.watch + 1s 폴링으로 감시
                                                         │
                                                         ▼
                                            aggregateState (working > idle)
                                                         │
                                                         ▼
                                                   IPC → renderer
                                                         │
                                                         ▼
                                              GIF / PNG 화면 전환
```

| Hook | 동작 | 파일에 기록되는 state | 집계 후 표시 |
|------|------|----------------------|--------------|
| `SessionStart` | 세션 파일 생성 + 앱 띄움 | idle | idle |
| `UserPromptSubmit` | 사용자가 메시지 전송 | working | working |
| `PreToolUse` / `PostToolUse` | 도구 사용 (heartbeat) | working | working |
| `Notification` | Claude가 사용자 입력 필요 | idle | idle |
| `Stop` (`stop_hook_active: false`) | turn 정상 종료 | idle | idle (즉시) |
| `Stop` (`stop_hook_active: true`) | mid-turn (서브에이전트 / 내부 continuation) | stopping | working (15초 grace) |
| `SessionEnd` | 세션 종료 | 파일 삭제 | (집계에서 제외) |
| (인터럽트 / SIGHUP / SIGKILL) | hook 누락 → 5분 상한 후 자동 강등 | working (그대로) | working → idle |

> `Stop` hook의 `stop_hook_active` 필드로 진짜 종료(`false` → 즉시 idle)와 mid-turn continuation(`true` → 15초 grace 후 idle, 그 사이 `UserPromptSubmit`/`ToolUse`가 들어오면 working으로 되돌아감)을 구분한다.
>
> ESC 인터럽트나 터미널 창을 강제로 닫는 경로에서는 hook이 누락될 수 있어, `WORKING_MAX_MS = 5분`을 마지막 안전망으로 둔다. 그래도 `STALE_MS = 4시간` 컷오프가 죽은 세션 파일을 최종 청소한다.

## 🐈 멀티 세션 (고양이 한 마리, 여러 세션)

여러 터미널에서 `claude`를 동시에 실행해도 고양이는 한 마리. 모든 세션 중 **하나라도** working이면 working으로, 전부 idle이면 idle로 표시한다.

```
priority: working > idle
```

각 세션은 자기 파일(`data/sessions/<session_id>.json`)만 갱신하므로 hook끼리 경쟁이 없다. 트레이 메뉴에 현재 breakdown(예: `2 sessions: 1 working, 1 idle`)이 표시된다.

## 🎨 캐릭터 & 커스텀 아트

### 기본 제공 캐릭터

`cat` / `dog` / `bunny` 3종 내장. **idle 상태와 working 상태를 따로 지정 가능** — 작업 중일 땐 dog, 쉴 땐 cat 같은 조합. 트레이 → **Pet (idle)** / **Pet (working)** 두 서브메뉴 각각에서 라디오로 선택, 또는:

```
/pet list                       # 현재 idle/working + 사용 가능 목록
/pet set dog                    # 두 상태 모두 dog
/pet set idle cat               # idle만 cat
/pet set working dog            # working만 dog
/pet set                        # 인자 없이 호출 → Claude가 라디오 질문 띄움
```

`/pet set` 빈 인자 호출 시 슬래시 커맨드 자체는 인터랙티브 라디오를 못 띄우므로, 스크립트가 `PET_PICK` 블록을 출력하고 Claude(LLM)가 그 출력을 받아 `AskUserQuestion`으로 라디오 질문을 띄운다.

저장 형태:
- 두 상태 동일: `{"theme":"cat"}`
- 두 상태 다름: `{"theme":{"idle":"cat","working":"dog"}}`

경로: `~/.claude/plugins/claude-pet/data/config.json`. 재시작 후에도 유지.

### 내 그림으로 바꾸기 / 새 캐릭터 추가

각 캐릭터는 `pet-app/assets/pets/<name>/` 폴더. 두 파일만 두면 됨:

```
pet-app/assets/pets/cat/
├── working.svg / working.gif / working.png / ...    # Claude 작업 중
└── idle.svg / idle.png / ...                         # 응답 대기 / 완료
```

확장자 우선순위: `gif → webp → apng → png → svg`. raster가 svg 위에 있으면 raster 우선 — ship된 SVG는 안전한 fallback으로 남고 사용자가 같은 폴더에 `working.gif` 두면 그걸 사용.

권장 캔버스: **180×180**, 배경 투명. 자세한 사양과 SVG 클래스 규약(`loaf-typing`, `paw-left`, `dot`, `loaf-breathe`, `z` 등 CSS 애니메이션 hook)은 `pet-app/assets/pets/README.md` 참고.

새 그림 반영하려면 트레이 → Quit 후 다음 hook이 자동으로 다시 띄운다.

## 🎬 슬래시 커맨드 — `/pet`

데모/녹화 중에 펫을 잠깐 숨기거나 캐릭터 바꾸고 싶을 때:

```
/pet hide          # 창 숨김
/pet show          # 다시 보이기 (앱이 꺼져 있으면 spawn)
/pet list          # 사용 가능한 캐릭터 목록 (현재는 * 표시)
/pet set <name>    # 캐릭터 전환 (영구 저장)
```

쉘로 직접 실행되므로 LLM round-trip이나 토큰 비용 없음. show/hide는 `data/app.pid`로 `SIGUSR1`/`SIGUSR2`. set은 `data/config.json` 원자적 write → main.js의 `fs.watch`가 라이브 반영.

> 일반 제어(Show/Hide 토글, Reset position, Quit)는 트레이 메뉴에 모두 있다. 슬래시 커맨드는 키보드를 떠나기 싫을 때만 쓰면 된다.

## 🛠 라이프사이클

- 첫 Claude Code 세션이 열릴 때 자동 spawn.
- 마지막 세션이 닫히면 자동 quit (8초 grace period).
- 세션 파일이 4시간 이상 갱신 없으면 죽은 세션으로 간주 (터미널 SIGKILL 보호용).
- 트레이 메뉴 → Quit으로 언제든 강제 종료 가능.

## ⚙️ 설정

| 변수 / 상수 | 기본값 | 설명 |
|-------------|--------|------|
| `CLAUDE_PET_DATA_DIR` (env) | `~/.claude/plugins/claude-pet/data` | 세션 파일 / 로그 / 위치 저장 경로 |
| `CLAUDE_PET_DEBUG` (env) | `0` | `1`이면 Electron DevTools 자동 오픈 |
| `WORKING_MAX_MS` (main.js) | `300000` (5분) | working 세션이 heartbeat 없이 이 시간을 넘기면 idle로 강등. 인터럽트/SIGHUP/SIGKILL 안전망. |
| `STOP_GRACE_MS` (main.js) | `15000` (15초) | mid-turn `Stop` 후 새 활동이 없으면 idle로 확정. |
| `STALE_MS` (main.js) | `14400000` (4시간) | 세션 파일이 이 시간 이상 갱신 없으면 죽은 세션으로 간주, 집계에서 제외. |

## 📁 데이터 위치

| 경로 | 용도 |
|------|------|
| `~/.claude/plugins/claude-pet/data/sessions/<sid>.json` | 세션별 상태 |
| `~/.claude/plugins/claude-pet/data/hook.log` | hook 호출 로그 |
| `~/.claude/plugins/claude-pet/data/app.log` | Electron 앱 로그 |
| `~/.claude/plugins/claude-pet/data/position.json` | 창 위치 |
| `~/.claude/plugins/claude-pet/data/app.pid` | Electron PID (중복 방지) |
| `~/.claude/plugins/claude-pet/data/config.json` | 선택한 캐릭터 (`{"theme":"cat"}` 등) |

## 🧪 동작 검증

1. `claude` 실행 → 새 세션 시작.
2. 메시지 전송 → 고양이가 **working**으로 전환 (노트북 두드림).
3. 응답 끝까지 진행 → **idle** 로 전환 (위 보고 앉음).
4. 메시지 중간에 ESC → 다음 프롬프트가 들어오면 즉시 working↔idle 사이클이 정상 재개. 다음 프롬프트 없이 방치하면 5분 후 **idle**로 강등.
5. 고양이를 다른 위치로 드래그 → 트레이 → Quit → 다음 hook으로 다시 뜸. 저장된 위치에 다시 나타나야 함.
6. Fullscreen 앱 위에서도 떠 있어야 함.
7. 두 번째 터미널에서 `claude` 실행 → 한쪽이 working이면 고양이도 working, 둘 다 idle이면 고양이도 idle.
8. 종료 경로별 정리 동작:
   - `/exit` 또는 Ctrl+C → `SessionEnd` hook이 세션 파일 삭제 → 마지막 세션이면 8초 grace 후 앱 자동 quit.
   - 터미널 창 직접 닫기 / `kill -9` → `SessionEnd` 보장 안 됨. 세션 파일은 `WORKING_MAX_MS`(5분)이 지나면 집계에서 idle로 보이고, `STALE_MS`(4시간) 후에는 자체적으로 무시. 마지막 세션이 사라지면 8초 grace 후 앱 자동 quit.

수동으로 상태를 강제로 찍어보려면:

```sh
echo '{"session_id":"manual","state":"working","updated_at":'$(date +%s)'}' \
  > ~/.claude/plugins/claude-pet/data/sessions/manual.json
# 정리:
rm ~/.claude/plugins/claude-pet/data/sessions/manual.json
```

100ms 안에 화면이 반응하면 정상.

## 🩺 트러블슈팅

- **고양이가 안 뜬다.** 새 세션 시작 시 SessionStart hook이 `node` / `npm` 누락 / 구버전이면 채팅창에 사유를 표시한다. 메시지에 따라 [nodejs.org](https://nodejs.org/)에서 Node 20+ 설치 후 새 세션 시작. 그래도 안 뜨면 `data/app.log` 확인 (`electron not found`이면 `cd pet-app && npm install`).
- **상태가 안 바뀐다.** `data/hook.log` 확인. hook이 안 찍히면 플러그인이 등록 안 됐거나 비활성 상태.
- **다른 창 뒤로 숨는다.** macOS가 floating 창을 Mission Control 진입 시 가끔 강등시킴. 트레이 → Show/Hide 토글로 다시 promote.
- **영원히 없애고 싶다.** [제거 섹션](#-제거) 참고.

## 📌 알려진 제약 (MVP)

- macOS만 지원. Windows/Linux는 `setVisibleOnAllWorkspaces` 동작 / X11 / Wayland 투명도 검증 필요.
- 머신 당 고양이 한 마리. 동시에 여러 Claude Code 세션이 있어도 통합된 상태(우선순위 working > idle)로 한 창에 표시.
- 인터럽트(ESC) / 터미널 창 강제 닫기(SIGHUP) / `kill -9` 같은 경로는 Claude Code가 hook 발화를 보장하지 않는다. 이런 경우 마지막 heartbeat로부터 `WORKING_MAX_MS` (기본 5분)이 지나면 idle로 강등된다 — 그 전까지는 cosmetic하게 working으로 보일 수 있음.
- mid-turn `Stop` (서브에이전트 / 내부 continuation) 직후 `STOP_GRACE_MS` (기본 15초) 동안은 working으로 유지. 그래서 정상 종료된 turn도 화면상 idle로 잡히는 데 최대 15초 + 5초 tick 정도 걸릴 수 있음. `stop_hook_active=false`(진짜 종료)는 즉시 idle.
