from datetime import datetime
from typing import List

from pydantic import BaseModel, Field


# ジャンル関連
class GenreBase(BaseModel):
    genre_name: str = Field(..., min_length=1, max_length=255, description="ジャンル名")


class GenreCreate(GenreBase):
    pass


class GenreResponse(GenreBase):
    id: str = Field(..., description="UUID形式のID")
    created_at: datetime = Field(..., description="作成日時")
    updated_at: datetime = Field(..., description="更新日時")

    model_config = {"from_attributes": True}


# 質問関連
class QuestionBase(BaseModel):
    question: str = Field(..., min_length=1, description="質問内容")


class QuestionCreate(QuestionBase):
    genre_id: str = Field(..., description="ジャンルID（UUID形式）")


class QuestionResponse(QuestionBase):
    id: str = Field(..., description="UUID形式のID")
    genre_id: str = Field(..., description="ジャンルID（UUID形式）")
    created_at: datetime = Field(..., description="作成日時")
    updated_at: datetime = Field(..., description="更新日時")

    model_config = {"from_attributes": True}


# 回答関連
class AnswerBase(BaseModel):
    answer: str = Field(..., min_length=1, description="回答内容")


class AnswerCreate(AnswerBase):
    question_id: str = Field(..., description="質問ID（UUID形式）")


class AnswerResponse(AnswerBase):
    id: str = Field(..., description="UUID形式のID")
    question_id: str = Field(..., description="質問ID（UUID形式）")
    created_at: datetime = Field(..., description="作成日時")
    updated_at: datetime = Field(..., description="更新日時")

    model_config = {"from_attributes": True}


# リレーション付きレスポンス
class QuestionWithGenre(QuestionResponse):
    genre: GenreResponse = Field(..., description="関連するジャンル情報")


class AnswerWithQuestion(AnswerResponse):
    question: QuestionResponse = Field(..., description="関連する質問情報")


class GenreWithQuestions(GenreResponse):
    questions: List[QuestionResponse] = Field(
        default=[], description="ジャンルに属する質問一覧"
    )
