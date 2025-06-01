# マルチステージビルドを使用して最終イメージサイズを削減
FROM python:3.13-slim as builder

# 環境変数の設定
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# 必要な依存関係のみインストール
RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# uvのインストール
RUN pip install uv

# 作業ディレクトリを設定
WORKDIR /app

# 依存関係ファイルをコピー
COPY pyproject.toml ./

# 依存関係をインストール
RUN uv sync --no-dev

# === 本番用イメージ ===
FROM python:3.13-slim

# 環境変数の設定
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PATH="/app/.venv/bin:$PATH"

# 最小限のパッケージのみインストール
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# 本番用ユーザーの作成（セキュリティのため）
RUN useradd --create-home --shell /bin/bash --uid 1000 appuser

# 作業ディレクトリを設定
WORKDIR /app

# ビルダーステージから仮想環境をコピー
COPY --from=builder /app/.venv /app/.venv

# アプリケーションコードをコピー
COPY main.py database.py models.py schemas.py ./

# ファイルの所有権を変更
RUN chown -R appuser:appuser /app

# 本番用ユーザーに切り替え
USER appuser

# ヘルスチェック
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health_check || exit 1

# ポートを公開
EXPOSE 8000

# アプリケーションを起動
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]