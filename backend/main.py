from datetime import datetime
from typing import Dict, List

from database import Base, engine, get_db
from fastapi import Depends, FastAPI, HTTPException
from models import Answer, Genre, Question
from schemas import (
    AnswerCreate,
    AnswerResponse,
    AnswerWithQuestion,
    GenreCreate,
    GenreResponse,
    QuestionCreate,
    QuestionResponse,
    QuestionWithGenre,
)
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

app = FastAPI(
    title="Bedrock Test API", description="ジャンル・質問・回答管理API", version="0.1.0"
)


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


# ===== ジャンル関連エンドポイント =====
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


# ===== 質問関連エンドポイント =====
@app.post("/questions", response_model=QuestionResponse, summary="質問作成")
async def create_question(
    question: QuestionCreate, db: AsyncSession = Depends(get_db)
) -> QuestionResponse:
    """
    新しい質問を作成します。

    - **genre_id**: 関連するジャンルのID（UUID形式）
    - **question**: 質問内容
    """
    # ジャンルの存在確認
    genre_result = await db.execute(select(Genre).where(Genre.id == question.genre_id))
    if not genre_result.scalar_one_or_none():
        raise HTTPException(
            status_code=404, detail=f"ジャンルID '{question.genre_id}' が見つかりません"
        )

    # 質問を作成
    db_question = Question(**question.model_dump())
    db.add(db_question)
    await db.commit()
    await db.refresh(db_question)

    return db_question


@app.get("/questions", response_model=List[QuestionWithGenre], summary="質問一覧取得")
async def get_questions(
    genre_id: str | None = None, db: AsyncSession = Depends(get_db)
) -> List[QuestionWithGenre]:
    """
    質問の一覧を取得します。

    - **genre_id**: 指定した場合、そのジャンルの質問のみを取得
    """
    # クエリの構築
    query = select(Question).options(selectinload(Question.genre))

    if genre_id:
        query = query.where(Question.genre_id == genre_id)

    result = await db.execute(query)
    questions = result.scalars().all()

    return list(questions)


@app.get(
    "/questions/{question_id}", response_model=QuestionWithGenre, summary="質問詳細取得"
)
async def get_question(
    question_id: str, db: AsyncSession = Depends(get_db)
) -> QuestionWithGenre:
    """
    指定されたIDの質問詳細を取得します。

    - **question_id**: 質問のID（UUID形式）
    """
    result = await db.execute(
        select(Question)
        .options(selectinload(Question.genre))
        .where(Question.id == question_id)
    )
    question = result.scalar_one_or_none()

    if not question:
        raise HTTPException(
            status_code=404, detail=f"質問ID '{question_id}' が見つかりません"
        )

    return question


@app.get(
    "/genres/{genre_id}/questions",
    response_model=List[QuestionResponse],
    summary="ジャンル別質問取得",
)
async def get_questions_by_genre(
    genre_id: str, db: AsyncSession = Depends(get_db)
) -> List[QuestionResponse]:
    """
    指定されたジャンルに属する質問の一覧を取得します。

    - **genre_id**: ジャンルのID（UUID形式）
    """
    # ジャンルの存在確認
    genre_result = await db.execute(select(Genre).where(Genre.id == genre_id))
    if not genre_result.scalar_one_or_none():
        raise HTTPException(
            status_code=404, detail=f"ジャンルID '{genre_id}' が見つかりません"
        )

    # 質問を取得
    result = await db.execute(select(Question).where(Question.genre_id == genre_id))
    questions = result.scalars().all()

    return list(questions)


# ===== 回答関連エンドポイント =====
@app.post("/answers", response_model=AnswerResponse, summary="回答作成")
async def create_answer(
    answer: AnswerCreate, db: AsyncSession = Depends(get_db)
) -> AnswerResponse:
    """
    新しい回答を作成します。

    - **question_id**: 関連する質問のID（UUID形式）
    - **answer**: 回答内容
    """
    # 質問の存在確認
    question_result = await db.execute(
        select(Question).where(Question.id == answer.question_id)
    )
    if not question_result.scalar_one_or_none():
        raise HTTPException(
            status_code=404, detail=f"質問ID '{answer.question_id}' が見つかりません"
        )

    # 回答を作成
    db_answer = Answer(**answer.model_dump())
    db.add(db_answer)
    await db.commit()
    await db.refresh(db_answer)

    return db_answer


@app.get("/answers", response_model=List[AnswerWithQuestion], summary="回答一覧取得")
async def get_answers(
    question_id: str | None = None, db: AsyncSession = Depends(get_db)
) -> List[AnswerWithQuestion]:
    """
    回答の一覧を取得します。

    - **question_id**: 指定した場合、その質問の回答のみを取得
    """
    # クエリの構築
    query = select(Answer).options(
        selectinload(Answer.question).selectinload(Question.genre)
    )

    if question_id:
        query = query.where(Answer.question_id == question_id)

    result = await db.execute(query)
    answers = result.scalars().all()

    return list(answers)


@app.get(
    "/answers/{answer_id}", response_model=AnswerWithQuestion, summary="回答詳細取得"
)
async def get_answer(
    answer_id: str, db: AsyncSession = Depends(get_db)
) -> AnswerWithQuestion:
    """
    指定されたIDの回答詳細を取得します。

    - **answer_id**: 回答のID（UUID形式）
    """
    result = await db.execute(
        select(Answer)
        .options(selectinload(Answer.question).selectinload(Question.genre))
        .where(Answer.id == answer_id)
    )
    answer = result.scalar_one_or_none()

    if not answer:
        raise HTTPException(
            status_code=404, detail=f"回答ID '{answer_id}' が見つかりません"
        )

    return answer


@app.get(
    "/questions/{question_id}/answers",
    response_model=List[AnswerResponse],
    summary="質問別回答取得",
)
async def get_answers_by_question(
    question_id: str, db: AsyncSession = Depends(get_db)
) -> List[AnswerResponse]:
    """
    指定された質問に対する回答の一覧を取得します。

    - **question_id**: 質問のID（UUID形式）
    """
    # 質問の存在確認
    question_result = await db.execute(
        select(Question).where(Question.id == question_id)
    )
    if not question_result.scalar_one_or_none():
        raise HTTPException(
            status_code=404, detail=f"質問ID '{question_id}' が見つかりません"
        )

    # 回答を取得
    result = await db.execute(select(Answer).where(Answer.question_id == question_id))
    answers = result.scalars().all()

    return list(answers)


@app.get(
    "/questions/{question_id}/details",
    response_model=Dict,
    summary="質問と回答の詳細取得",
)
async def get_question_with_answers(
    question_id: str, db: AsyncSession = Depends(get_db)
) -> Dict:
    """
    質問とその回答をまとめて取得します。

    - **question_id**: 質問のID（UUID形式）
    """
    # 質問を取得（ジャンルと回答を含む）
    question_result = await db.execute(
        select(Question)
        .options(selectinload(Question.genre), selectinload(Question.answers))
        .where(Question.id == question_id)
    )
    question = question_result.scalar_one_or_none()

    if not question:
        raise HTTPException(
            status_code=404, detail=f"質問ID '{question_id}' が見つかりません"
        )

    # レスポンス用のデータを構築
    return {
        "question": {
            "id": question.id,
            "question": question.question,
            "genre_id": question.genre_id,
            "created_at": question.created_at,
            "updated_at": question.updated_at,
            "genre": {
                "id": question.genre.id,
                "genre_name": question.genre.genre_name,
                "created_at": question.genre.created_at,
                "updated_at": question.genre.updated_at,
            },
        },
        "answers": [
            {
                "id": answer.id,
                "answer": answer.answer,
                "question_id": answer.question_id,
                "created_at": answer.created_at,
                "updated_at": answer.updated_at,
            }
            for answer in question.answers
        ],
        "answer_count": len(question.answers),
    }
