"""GitHub Copilot SDK 기반 추론 엔진 (Wrapper).

설계 규칙:
- CopilotClient는 앱 시작 시 1회만 생성합니다 (싱글톤).
- 세션은 매 요청마다 새로 만들고 사용 후 정리합니다.
- 핸들러 안에서 `asyncio.run()`을 호출하지 않습니다.
- BYOM = Azure OpenAI + DefaultAzureCredential 토큰 (Managed Identity 권장).
- 응답 타임아웃 30초 적용.

⚠️ 학습용 스타터 코드입니다. 실제 GitHub Copilot SDK 함수/클래스 시그니처는
   사용 중인 SDK 버전에 따라 다를 수 있으니 공식 문서를 확인하고 미세 조정하세요:
   https://github.com/github/copilot-sdk
"""
from __future__ import annotations

import asyncio
import logging
import os
from typing import Optional

from src.faq_tool import search_faq

log = logging.getLogger(__name__)

# --- GitHub Copilot SDK import ---
# 패키지 버전에 따라 import 경로가 달라질 수 있습니다.
# 시작 시 import 실패 시 명확한 에러를 발생시킵니다.
try:
    from copilot import CopilotClient  # type: ignore
    from copilot.session import PermissionHandler  # type: ignore
except Exception as e:  # pragma: no cover
    log.warning("github-copilot-sdk import 실패: %s", e)
    CopilotClient = None  # type: ignore
    PermissionHandler = None  # type: ignore

_RESPONSE_TIMEOUT_SEC = 30.0


class CopilotBrain:
    """GitHub Copilot SDK 래퍼 — Agent의 추론 두뇌."""

    def __init__(self) -> None:
        if CopilotClient is None:
            raise RuntimeError(
                "github-copilot-sdk를 import할 수 없습니다. "
                "requirements.txt 설치 또는 Track A 폴백을 검토하세요."
            )
        self._client: Optional["CopilotClient"] = None

    async def start(self) -> None:
        """앱 시작 시 1회 호출."""
        # NOTE: 실제 CopilotClient 초기화 옵션은 SDK 문서 참고.
        # BYOM 환경 변수: AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_CHAT_DEPLOYMENT_NAME 등을 SDK가 인지합니다.
        self._client = CopilotClient()
        await self._client.__aenter__()  # async context manager 진입
        log.info("CopilotClient started")

    async def stop(self) -> None:
        if self._client is not None:
            await self._client.__aexit__(None, None, None)
            self._client = None
            log.info("CopilotClient stopped")

    async def handle(self, user_text: str) -> str:
        """단일 turn 처리. 새 session을 만들어 사용 후 정리."""
        if self._client is None:
            raise RuntimeError("CopilotBrain.start()가 먼저 호출되어야 합니다.")

        # 세션 생성 (요청별)
        session_ctx = await self._client.create_session(
            on_permission_request=PermissionHandler.approve_all,
            model=os.environ.get("AZURE_OPENAI_CHAT_DEPLOYMENT_NAME", "gpt-4o"),
        )

        async with session_ctx as session:
            # 도구 등록
            session.register_tool(search_faq)

            # 답변 수집용 이벤트
            done = asyncio.Event()
            collected: list[str] = []

            def on_event(event):  # type: ignore[no-untyped-def]
                etype = getattr(event.type, "value", str(event.type))
                if etype == "assistant.message":
                    collected.append(getattr(event.data, "content", ""))
                elif etype == "session.idle":
                    done.set()

            session.on(on_event)

            system_prompt = (
                "당신은 사내 FAQ 도우미입니다. 반드시 search_faq 도구로 KB를 조회한 뒤 "
                "그 결과를 근거로만 답변하세요. 매칭 결과가 없으면 '관련 FAQ를 찾을 수 없습니다.'라고 답하세요. "
                "답변 마지막에 참고한 FAQ ID를 [출처: id1, id2] 형식으로 표시하세요."
            )

            await session.send(f"{system_prompt}\n\n사용자 질문: {user_text}")

            try:
                await asyncio.wait_for(done.wait(), timeout=_RESPONSE_TIMEOUT_SEC)
            except asyncio.TimeoutError:
                log.error("Copilot 응답 타임아웃 (%.0fs)", _RESPONSE_TIMEOUT_SEC)
                return "응답 생성이 지연되어 처리하지 못했습니다. 잠시 후 다시 시도해주세요."

        return "\n".join(collected) or "(빈 응답)"


# --- 모듈 레벨 싱글톤 ---
_brain: Optional[CopilotBrain] = None


async def get_brain() -> CopilotBrain:
    global _brain
    if _brain is None:
        _brain = CopilotBrain()
        await _brain.start()
    return _brain


async def shutdown_brain() -> None:
    global _brain
    if _brain is not None:
        await _brain.stop()
        _brain = None


# 편의 함수
async def handle(user_text: str) -> str:
    brain = await get_brain()
    return await brain.handle(user_text)


if __name__ == "__main__":
    # 단위 테스트: python -m src.copilot_brain "연차 며칠?"
    import sys

    async def _main() -> None:
        q = " ".join(sys.argv[1:]) or "연차 며칠?"
        try:
            answer = await handle(q)
            print(answer)
        finally:
            await shutdown_brain()

    asyncio.run(_main())
