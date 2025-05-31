from datetime import datetime
from typing import Dict, List

from database import Base, engine, get_db
from fastapi import Depends, FastAPI, HTTPException
from models import Genre
from schemas import GenreCreate, GenreResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

app = FastAPI()


# データベーステーブルの作成
@app.on_event("startup")
async def create_tables():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


@app.get("/")
def hello_world() -> Dict[str, str]:
    return {"Hello": "World"}


@app.get("/health_check")
def health_check() -> Dict[str, str | datetime]:
    return {"status": "healthy", "timestamp": datetime.now()}


# ジャンル作成エンドポイント
@app.post("/genres", response_model=GenreResponse, summary="ジャンル作成")
async def create_genre(
    genre: GenreCreate, db: AsyncSession = Depends(get_db)
) -> GenreResponse:
    """
    新しいジャンルを作成します。

    - **genre_name**: ジャンル名（1文字以上255文字以下）
    """
    # ジャンル名の重複チェック
    existing_genre = await db.execute(
        select(Genre).where(Genre.genre_name == genre.genre_name)
    )
    if existing_genre.scalar_one_or_none():
        raise HTTPException(
            status_code=400, detail=f"ジャンル名 '{genre.genre_name}' は既に存在します"
        )

    # 新しいジャンルを作成
    db_genre = Genre(**genre.model_dump())
    db.add(db_genre)
    await db.commit()
    await db.refresh(db_genre)

    return db_genre


# ジャンル一覧取得エンドポイント
@app.get("/genres", response_model=List[GenreResponse], summary="ジャンル一覧取得")
async def get_genres(db: AsyncSession = Depends(get_db)) -> List[GenreResponse]:
    """
    登録されているジャンルの一覧を取得します。
    """
    result = await db.execute(select(Genre))
    genres = result.scalars().all()
    return list(genres)
