import pytest_asyncio
from httpx import AsyncClient


class TestQuestionEndpoints:
    """質問エンドポイントのテストクラス"""

    @pytest_asyncio.is_async_test
    async def test_create_question_success(self, client: AsyncClient):
        """質問作成成功のテスト"""
        # 事前準備：ジャンルを作成
        genre_data = {"genre_name": "プログラミング"}
        genre_response = await client.post("/genres", json=genre_data)
        genre_id = genre_response.json()["id"]

        # テストデータ
        question_data = {
            "genre_id": genre_id,
            "question": "Pythonの基本的な文法について教えてください",
        }

        # APIリクエスト
        response = await client.post("/questions", json=question_data)

        # アサーション
        assert response.status_code == 200
        data = response.json()
        assert data["question"] == question_data["question"]
        assert data["genre_id"] == genre_id
        assert "id" in data
        assert "created_at" in data
        assert "updated_at" in data
        assert len(data["id"]) == 36  # UUID形式

    @pytest_asyncio.is_async_test
    async def test_create_question_invalid_genre_id(self, client: AsyncClient):
        """存在しないジャンルIDでの質問作成エラーテスト"""
        # 存在しないジャンルIDを使用
        question_data = {"genre_id": "non-existent-id", "question": "テスト質問"}

        response = await client.post("/questions", json=question_data)

        # アサーション
        assert response.status_code == 404
        data = response.json()
        assert "見つかりません" in data["detail"]

    @pytest_asyncio.is_async_test
    async def test_create_question_empty_question(self, client: AsyncClient):
        """空の質問でのバリデーションエラーテスト"""
        # 事前準備：ジャンルを作成
        genre_data = {"genre_name": "テストジャンル"}
        genre_response = await client.post("/genres", json=genre_data)
        genre_id = genre_response.json()["id"]

        question_data = {"genre_id": genre_id, "question": ""}

        response = await client.post("/questions", json=question_data)

        # アサーション
        assert response.status_code == 422  # バリデーションエラー

    @pytest_asyncio.is_async_test
    async def test_get_questions_empty(self, client: AsyncClient):
        """質問一覧取得（空）のテスト"""
        response = await client.get("/questions")

        # アサーション
        assert response.status_code == 200
        data = response.json()
        assert data == []

    @pytest_asyncio.is_async_test
    async def test_get_questions_with_data(self, client: AsyncClient):
        """質問一覧取得（データあり）のテスト"""
        # 事前準備：ジャンルと質問を作成
        genre_data = {"genre_name": "プログラミング"}
        genre_response = await client.post("/genres", json=genre_data)
        genre_id = genre_response.json()["id"]

        questions = [
            {"genre_id": genre_id, "question": "Pythonとは何ですか？"},
            {"genre_id": genre_id, "question": "変数の宣言方法を教えてください"},
            {"genre_id": genre_id, "question": "ループ処理について説明してください"},
        ]

        # 質問を作成
        for question in questions:
            await client.post("/questions", json=question)

        # 一覧取得
        response = await client.get("/questions")

        # アサーション
        assert response.status_code == 200
        data = response.json()
        assert len(data) == 3

        # 各質問にジャンル情報が含まれていることを確認
        for question in data:
            assert "id" in question
            assert "question" in question
            assert "genre_id" in question
            assert "genre" in question
            assert question["genre"]["genre_name"] == "プログラミング"

    @pytest_asyncio.is_async_test
    async def test_get_questions_filtered_by_genre(self, client: AsyncClient):
        """ジャンルIDでフィルタした質問一覧取得のテスト"""
        # 事前準備：複数のジャンルと質問を作成
        genre1_data = {"genre_name": "プログラミング"}
        genre1_response = await client.post("/genres", json=genre1_data)
        genre1_id = genre1_response.json()["id"]

        genre2_data = {"genre_name": "データベース"}
        genre2_response = await client.post("/genres", json=genre2_data)
        genre2_id = genre2_response.json()["id"]

        # 各ジャンルに質問を作成
        await client.post(
            "/questions", json={"genre_id": genre1_id, "question": "Python質問1"}
        )
        await client.post(
            "/questions", json={"genre_id": genre1_id, "question": "Python質問2"}
        )
        await client.post(
            "/questions", json={"genre_id": genre2_id, "question": "DB質問1"}
        )

        # genre1の質問のみを取得
        response = await client.get(f"/questions?genre_id={genre1_id}")

        # アサーション
        assert response.status_code == 200
        data = response.json()
        assert len(data) == 2
        assert all(q["genre_id"] == genre1_id for q in data)
        assert all("Python" in q["question"] for q in data)

    @pytest_asyncio.is_async_test
    async def test_get_question_by_id_success(self, client: AsyncClient):
        """質問詳細取得成功のテスト"""
        # 事前準備：ジャンルと質問を作成
        genre_data = {"genre_name": "機械学習"}
        genre_response = await client.post("/genres", json=genre_data)
        genre_id = genre_response.json()["id"]

        question_data = {"genre_id": genre_id, "question": "機械学習とは何ですか？"}
        question_response = await client.post("/questions", json=question_data)
        question_id = question_response.json()["id"]

        # 質問詳細を取得
        response = await client.get(f"/questions/{question_id}")

        # アサーション
        assert response.status_code == 200
        data = response.json()
        assert data["id"] == question_id
        assert data["question"] == question_data["question"]
        assert data["genre"]["genre_name"] == "機械学習"

    @pytest_asyncio.is_async_test
    async def test_get_question_by_id_not_found(self, client: AsyncClient):
        """存在しない質問IDでの詳細取得エラーテスト"""
        response = await client.get("/questions/non-existent-id")

        # アサーション
        assert response.status_code == 404
        data = response.json()
        assert "見つかりません" in data["detail"]

    @pytest_asyncio.is_async_test
    async def test_get_questions_by_genre_success(self, client: AsyncClient):
        """ジャンル別質問取得成功のテスト"""
        # 事前準備：ジャンルと質問を作成
        genre_data = {"genre_name": "ウェブ開発"}
        genre_response = await client.post("/genres", json=genre_data)
        genre_id = genre_response.json()["id"]

        questions = [
            {"genre_id": genre_id, "question": "HTMLとは？"},
            {"genre_id": genre_id, "question": "CSSの基本は？"},
        ]

        for question in questions:
            await client.post("/questions", json=question)

        # ジャンル別質問取得
        response = await client.get(f"/genres/{genre_id}/questions")

        # アサーション
        assert response.status_code == 200
        data = response.json()
        assert len(data) == 2
        assert all(q["genre_id"] == genre_id for q in data)

    @pytest_asyncio.is_async_test
    async def test_get_questions_by_genre_not_found(self, client: AsyncClient):
        """存在しないジャンルIDでの質問取得エラーテスト"""
        response = await client.get("/genres/non-existent-genre-id/questions")

        # アサーション
        assert response.status_code == 404
        data = response.json()
        assert "見つかりません" in data["detail"]

    @pytest_asyncio.is_async_test
    async def test_get_questions_by_genre_empty(self, client: AsyncClient):
        """質問のないジャンルでの取得テスト"""
        # 事前準備：ジャンルのみ作成（質問は作成しない）
        genre_data = {"genre_name": "空のジャンル"}
        genre_response = await client.post("/genres", json=genre_data)
        genre_id = genre_response.json()["id"]

        # ジャンル別質問取得
        response = await client.get(f"/genres/{genre_id}/questions")

        # アサーション
        assert response.status_code == 200
        data = response.json()
        assert data == []


class TestQuestionIntegration:
    """質問機能の統合テストクラス"""

    @pytest_asyncio.is_async_test
    async def test_complete_question_workflow(self, client: AsyncClient):
        """質問機能の完全なワークフローテスト"""
        # 1. ジャンル作成
        genre_data = {"genre_name": "統合テスト"}
        genre_response = await client.post("/genres", json=genre_data)
        assert genre_response.status_code == 200
        genre_id = genre_response.json()["id"]

        # 2. 質問作成
        question_data = {"genre_id": genre_id, "question": "統合テストの質問です"}
        question_response = await client.post("/questions", json=question_data)
        assert question_response.status_code == 200
        question_id = question_response.json()["id"]

        # 3. 質問一覧で確認
        questions_response = await client.get("/questions")
        assert questions_response.status_code == 200
        questions = questions_response.json()
        assert len(questions) == 1
        assert questions[0]["id"] == question_id

        # 4. 質問詳細で確認
        detail_response = await client.get(f"/questions/{question_id}")
        assert detail_response.status_code == 200
        detail = detail_response.json()
        assert detail["question"] == question_data["question"]
        assert detail["genre"]["genre_name"] == "統合テスト"

        # 5. ジャンル別質問取得で確認
        genre_questions_response = await client.get(f"/genres/{genre_id}/questions")
        assert genre_questions_response.status_code == 200
        genre_questions = genre_questions_response.json()
        assert len(genre_questions) == 1
        assert genre_questions[0]["id"] == question_id
