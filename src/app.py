"""aiohttp + Microsoft 365 Agents SDK 진입점.

설계 규칙:
- AgentApplication 데코레이터 패턴 사용.
- @AGENT_APP.activity("message") 핸들러에서 copilot_brain.handle()을 await.
- /api/messages 라우트를 aiohttp로 호스팅.
- 단일 워커로 시작 (Copilot SDK 동작 검증 후 다중 워커 도입).

⚠️ 실제 Microsoft 365 Agents SDK Python의 정확한 API 시그니처는
   사용 중인 패키지 버전에 따라 미세 조정이 필요할 수 있습니다.
   참고: https://learn.microsoft.com/microsoft-365/agents-sdk/quickstart
"""
from __future__ import annotations

import logging
import os

from aiohttp import web
from dotenv import load_dotenv

from src.copilot_brain import handle as brain_handle, shutdown_brain

# .env 로드 (로컬 개발용)
load_dotenv()

# --- 로깅 ---
logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
log = logging.getLogger("faq-agent")

# --- Microsoft 365 Agents SDK ---
try:
    from microsoft_agents.hosting.core import (  # type: ignore
        AgentApplication,
        TurnContext,
        TurnState,
        load_configuration_from_env,
    )
    from microsoft_agents.hosting.aiohttp import (  # type: ignore
        CloudAdapter,
        AgentsHttpMiddleware,
    )
    from microsoft_agents.authentication.msal import MsalAuth  # type: ignore
except Exception as e:  # pragma: no cover
    log.error("microsoft-agents-* import 실패: %s", e)
    raise


# --- AgentApplication 구성 ---
CONFIG = load_configuration_from_env()
AUTH = MsalAuth.from_environment()
ADAPTER = CloudAdapter(auth=AUTH)
AGENT_APP = AgentApplication(adapter=ADAPTER)


@AGENT_APP.activity("message")
async def on_message(context: TurnContext, _state: TurnState) -> None:
    user_text = (context.activity.text or "").strip()
    log.info("incoming message: %s", user_text[:200])

    if not user_text:
        await context.send_activity("질문을 입력해주세요.")
        return

    try:
        answer = await brain_handle(user_text)
    except Exception:
        log.exception("brain_handle 실패")
        await context.send_activity("내부 오류가 발생했습니다. 잠시 후 다시 시도해주세요.")
        return

    await context.send_activity(answer)


# --- aiohttp 라우트 ---
async def messages(request: web.Request) -> web.Response:
    return await ADAPTER.process(request, AGENT_APP)


async def healthz(request: web.Request) -> web.Response:
    return web.json_response({"status": "ok"})


def create_app() -> web.Application:
    app = web.Application(middlewares=[AgentsHttpMiddleware(AUTH)])
    app.router.add_post("/api/messages", messages)
    app.router.add_get("/healthz", healthz)

    async def _on_shutdown(_app: web.Application) -> None:
        log.info("Shutting down…")
        await shutdown_brain()

    app.on_shutdown.append(_on_shutdown)
    return app


def main() -> None:
    port = int(os.environ.get("PORT", "3978"))
    app = create_app()
    log.info("Starting FAQ Agent on 0.0.0.0:%d", port)
    web.run_app(app, host="0.0.0.0", port=port)


if __name__ == "__main__":
    main()
