import os

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

# 本番環境では.envファイルを読み込まない
# 開発環境でのみdotenvを使用
try:
    from dotenv import load_dotenv

    if os.getenv("ENVIRONMENT") != "production":
        load_dotenv()
except ImportError:
    # dotenvがインストールされていない場合は無視
    pass

# データベース接続URL
DATABASE_URL = f"mysql+aiomysql://{os.getenv('DB_USER')}:{os.getenv('DB_PASSWORD')}@{os.getenv('DB_HOST')}:{os.getenv('DB_PORT')}/{os.getenv('DB_NAME')}"

# エンジンの作成
engine = create_async_engine(DATABASE_URL, echo=False)  # 本番ではechoをFalseに

# セッションの作成
AsyncSessionLocal = async_sessionmaker(
    autocommit=False, autoflush=False, bind=engine, class_=AsyncSession
)


# ベースクラス
class Base(DeclarativeBase):
    pass


# 依存関数：データベースセッションの取得
async def get_db():
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()
