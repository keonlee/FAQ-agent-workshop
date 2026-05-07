"""FAQ search tool — 입문자용 키워드 매칭 구현.

운영 시에는 Azure AI Search 등으로 교체 가능.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

_FAQ_PATH = Path(__file__).parent / "faq.json"
_TOKEN_RE = re.compile(r"[A-Za-z0-9가-힣]+")


def _load_faq() -> list[dict[str, Any]]:
    with _FAQ_PATH.open("r", encoding="utf-8") as fp:
        return json.load(fp)


_FAQ_DATA: list[dict[str, Any]] = _load_faq()


def _tokenize(text: str) -> set[str]:
    return {t.lower() for t in _TOKEN_RE.findall(text)}


def _score(query_tokens: set[str], item: dict[str, Any]) -> int:
    haystack = " ".join(
        [
            item.get("q", ""),
            item.get("a", ""),
            " ".join(item.get("tags", [])),
        ]
    )
    item_tokens = _tokenize(haystack)
    return len(query_tokens & item_tokens)


def search_faq(query: str, top_n: int = 3) -> list[dict[str, Any]]:
    """질의어와 가장 잘 매칭되는 FAQ 항목을 반환합니다.

    Args:
        query: 사용자 질문 텍스트
        top_n: 최대 반환 개수

    Returns:
        [{id, q, a, score}, ...] 점수 내림차순. 매칭 0건이면 빈 리스트.
    """
    qt = _tokenize(query)
    if not qt:
        return []

    scored = []
    for item in _FAQ_DATA:
        s = _score(qt, item)
        if s > 0:
            scored.append({"id": item["id"], "q": item["q"], "a": item["a"], "score": s})

    scored.sort(key=lambda x: x["score"], reverse=True)
    return scored[:top_n]


if __name__ == "__main__":
    # 단위 테스트: python -m src.faq_tool "연차"
    q = " ".join(sys.argv[1:]) or "연차 며칠"
    print(f"Query: {q}\n")
    for hit in search_faq(q):
        print(f"[{hit['id']}] (score={hit['score']}) {hit['q']}")
        print(f"  → {hit['a']}\n")
