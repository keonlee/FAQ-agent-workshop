# =========================================================
# FAQ Agent Workshop - Dockerfile
# 단일 워커로 시작 (Copilot SDK 동작 검증 후 다중 워커 도입)
# =========================================================
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=3978

WORKDIR /app

# 시스템 패키지 (필요 시 추가)
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 의존성 캐시 활용을 위해 requirements를 먼저 복사
COPY requirements.txt ./
RUN pip install --upgrade pip && pip install -r requirements.txt

# 애플리케이션 코드 복사
COPY src/ ./src/

EXPOSE 3978

# 단일 워커 진입점 (aiohttp 직접 실행)
CMD ["python", "src/app.py"]
