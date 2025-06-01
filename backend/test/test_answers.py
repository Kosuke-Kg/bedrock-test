import pytest_asyncio
from httpx import AsyncClient


class TestAnswerEndpoints:
    """回答エンドポイントのテストクラス"""

    @pytest_asyncio.is_async_test
    async def test_create_answer_success(self, client: AsyncClient):
        """回答作成成功のテスト"""
        # 事前準備：ジャンルと質問を作成
        genre_data = {"genre_name": "プログラミング"}
        genre_response = await client.post("/genres", json=genre_data)
        genre_id = genre_response.json()["id"]

        question_data = {
            "genre_id": genre_id,
            "question": "Pythonの基本的な文法について教えてください",
        }
        question_response = await client.post("/questions", json=question_data)
        question_id = question_response.json()["id"]

        # テストデータ
        answer_data = {
            "question_id": question_id,
            "answer": "Pythonは汎用プログラミング言語で、シンプルな文法が特徴です。",
        }

        # APIリクエスト
        response = await client.post("/answers", json=answer_data)

        # アサーション
        assert response.status_code == 200
        data = response.json()
        assert data["answer"] == answer_data["answer"]
        assert data["question_id"] == question_id
        assert "id" in data
        assert "created_at" in data
        assert "updated_at" in data
        assert len(data["id"]) == 36  # UUID形式

    @pytest_asyncio.is_async_test
    async def test_create_answer_invalid_question_id(self, client: AsyncClient):
        """存在しない質問IDでの回答作成エラーテスト"""
        # 存在しない質問IDを使用
        answer_data = {"question_id": "non-existent-id", "answer": "テスト回答"}

        response = await client.post("/answers", json=answer_data)

        # アサーション
        assert response.status_code == 404
        data = response.json()
        assert "見つかりません" in data["detail"]

    @pytest_asyncio.is_async_test
    async def test_create_answer_empty_answer(self, client: AsyncClient):
        """空の回答でのバリデーションエラーテスト"""
        # 事前準備：ジャンルと質問を作成
        genre_data = {"genre_name": "テストジャンル"}
        genre_response = await client.post("/genres", json=genre_data)
        genre_id = genre_response.json()["id"]

        question_data = {"genre_id": genre_id, "question": "テスト質問"}
        question_response = await client.post("/questions", json=question_data)
        question_id = question_response.json()["id"]

        answer_data = {"question_id": question_id, "answer": ""}

        response = await client.post("/answers", json=answer_data)

        # アサーション
        assert response.status_code == 422  # バリデーションエラー

    @pytest_asyncio.is_async_test
    async def test_get_answers_empty(self, client: AsyncClient):
        """回答一覧取得（空）のテスト"""
        response = await client.get("/answers")

        # アサーション
        assert response.status_code == 200
        data = response.json()
        assert data == []

    @pytest_asyncio.is_async_test
    async def test_get_answers_with_data(self, client: AsyncClient):
        """回答一覧取得（データあり）のテスト"""
        # 事前準備：ジャンル、質問、回答を作成
        genre_data = {"genre_name": "プログラミング"}
        genre_response = await client.post("/genres", json=genre_data)
        genre_id = genre_response.json()["id"]

        question_data = {"genre_id": genre_id, "question": "Pythonとは何ですか？"}
        question_response = await client.post("/questions", json=question_data)
        question_id = question_response.json()["id"]

        answers = [
            {
                "question_id": question_id,
                "answer": "Python は汎用プログラミング言語です。",
            },
            {
                "question_id": question_id,
                "answer": "1991年にGuido van Rossumによって開発されました。",
            },
            {"question_id": question_id, "answer": "簡潔で読みやすい文法が特徴です。"},
        ]

        # 回答を作成
        for answer in answers:
            await client.post("/answers", json=answer)

        # 一覧取得
        response = await client.get("/answers")

        # アサーション
        assert response.status_code == 200
        data = response.json()
        assert len(data) == 3

        # 各回答に質問情報が含まれていることを確認
        for answer in data:
            assert "id" in answer
            assert "answer" in answer
            assert "question_id" in answer
            assert "question" in answer
            assert answer["question"]["question"] == "Pythonとは何ですか？"
            assert answer["question"]["genre"]["genre_name"] == "プログラミング"

    @pytest_asyncio.is_async_test
    async def test_get_answers_filtered_by_question(self, client: AsyncClient):
        """質問IDでフィルタした回答一覧取得のテスト"""
        # 事前準備：複数の質問と回答を作成
        genre_data = {"genre_name": "プログラミング"}
        genre_response = await client.post("/genres", json=genre_data)
        genre_id = genre_response.json()["id"]

        # 質問1
        question1_data = {"genre_id": genre_id, "question": "Pythonとは？"}
        question1_response = await client.post("/questions", json=question1_data)
        question1_id = question1_response.json()["id"]

        # 質問2
        question2_data = {"genre_id": genre_id, "question": "Javaとは？"}
        question2_response = await client.post("/questions", json=question2_data)
        question2_id = question2_response.json()["id"]

        # 各質問に回答を作成
        await client.post(
            "/answers", json={"question_id": question1_id, "answer": "Python回答1"}
        )
        await client.post(
            "/answers", json={"question_id": question1_id, "answer": "Python回答2"}
        )
        await client.post(
            "/answers", json={"question_id": question2_id, "answer": "Java回答1"}
        )

        # question1の回答のみを取得
        response = await client.get(f"/answers?question_id={question1_id}")

        # アサーション
        assert response.status_code == 200
        data = response.json()
        assert len(data) == 2
        assert all(a["question_id"] == question1_id for a in data)
        assert all("Python" in a["answer"] for a in data)

    @pytest_asyncio.is_async_test
    async def test_get_answer_by_id_success(self, client: AsyncClient):
        """回答詳細取得成功のテスト"""
        # 事前準備：ジャンル、質問、回答を作成
        genre_data = {"genre_name": "機械学習"}
        genre_response = await client.post("/genres", json=genre_data)
        genre_id = genre_response.json()["id"]

        question_data = {"genre_id": genre_id, "question": "機械学習とは何ですか？"}
        question_response = await client.post("/questions", json=question_data)
        question_id = question_response.json()["id"]

        answer_data = {
            "question_id": question_id,
            "answer": "機械学習は人工知能の一分野です。",
        }
        answer_response = await client.post("/answers", json=answer_data)
        answer_id = answer_response.json()["id"]

        # 回答詳細を取得
        response = await client.get(f"/answers/{answer_id}")

        # アサーション
        assert response.status_code == 200
        data = response.json()
        assert data["id"] == answer_id
        assert data["answer"] == answer_data["answer"]
        assert data["question"]["question"] == "機械学習とは何ですか？"
        assert data["question"]["genre"]["genre_name"] == "機械学習"

    @pytest_asyncio.is_async_test
    async def test_get_answer_by_id_not_found(self, client: AsyncClient):
        """存在しない回答IDでの詳細取得エラーテスト"""
        response = await client.get("/answers/non-existent-id")

        # アサーション
        assert response.status_code == 404
        data = response.json()
        assert "見つかりません" in data["detail"]

    @pytest_asyncio.is_async_test
    async def test_get_answers_by_question_success(self, client: AsyncClient):
        """質問別回答取得成功のテスト"""
        # 事前準備：ジャンル、質問、回答を作成
        genre_data = {"genre_name": "ウェブ開発"}
        genre_response = await client.post("/genres", json=genre_data)
        genre_id = genre_response.json()["id"]

        question_data = {"genre_id": genre_id, "question": "HTMLとは？"}
        question_response = await client.post("/questions", json=question_data)
        question_id = question_response.json()["id"]

        answers = [
            {"question_id": question_id, "answer": "HTMLはマークアップ言語です。"},
            {"question_id": question_id, "answer": "ウェブページの構造を定義します。"},
        ]

        for answer in answers:
            await client.post("/answers", json=answer)

        # 質問別回答取得
        response = await client.get(f"/questions/{question_id}/answers")

        # アサーション
        assert response.status_code == 200
        data = response.json()
        assert len(data) == 2
        assert all(a["question_id"] == question_id for a in data)

    @pytest_asyncio.is_async_test
    async def test_get_answers_by_question_not_found(self, client: AsyncClient):
        """存在しない質問IDでの回答取得エラーテスト"""
        response = await client.get("/questions/non-existent-question-id/answers")

        # アサーション
        assert response.status_code == 404
        data = response.json()
        assert "見つかりません" in data["detail"]

    @pytest_asyncio.is_async_test
    async def test_get_answers_by_question_empty(self, client: AsyncClient):
        """回答のない質問での取得テスト"""
        # 事前準備：ジャンルと質問のみ作成（回答は作成しない）
        genre_data = {"genre_name": "空の質問"}
        genre_response = await client.post("/genres", json=genre_data)
        genre_id = genre_response.json()["id"]

        question_data = {"genre_id": genre_id, "question": "回答のない質問"}
        question_response = await client.post("/questions", json=question_data)
        question_id = question_response.json()["id"]

        # 質問別回答取得
        response = await client.get(f"/questions/{question_id}/answers")

        # アサーション
        assert response.status_code == 200
        data = response.json()
        assert data == []

    @pytest_asyncio.is_async_test
    async def test_get_question_with_answers_success(self, client: AsyncClient):
        """質問と回答の詳細取得成功のテスト"""
        # 事前準備：ジャンル、質問、回答を作成
        genre_data = {"genre_name": "データサイエンス"}
        genre_response = await client.post("/genres", json=genre_data)
        genre_id = genre_response.json()["id"]

        question_data = {
            "genre_id": genre_id,
            "question": "データサイエンスとは何ですか？",
        }
        question_response = await client.post("/questions", json=question_data)
        question_id = question_response.json()["id"]

        answers = [
            {
                "question_id": question_id,
                "answer": "データから知見を得る学問分野です。",
            },
            {
                "question_id": question_id,
                "answer": "統計学、機械学習、プログラミングを組み合わせます。",
            },
        ]

        for answer in answers:
            await client.post("/answers", json=answer)

        # 質問と回答の詳細取得
        response = await client.get(f"/questions/{question_id}/details")

        # アサーション
        assert response.status_code == 200
        data = response.json()

        # 質問情報の確認
        assert "question" in data
        assert data["question"]["id"] == question_id
        assert data["question"]["question"] == "データサイエンスとは何ですか？"
        assert data["question"]["genre"]["genre_name"] == "データサイエンス"

        # 回答情報の確認
        assert "answers" in data
        assert len(data["answers"]) == 2
        assert "answer_count" in data
        assert data["answer_count"] == 2

        # 各回答の内容確認
        answer_texts = [a["answer"] for a in data["answers"]]
        assert "データから知見を得る学問分野です。" in answer_texts
        assert "統計学、機械学習、プログラミングを組み合わせます。" in answer_texts

    @pytest_asyncio.is_async_test
    async def test_get_question_with_answers_not_found(self, client: AsyncClient):
        """存在しない質問IDでの詳細取得エラーテスト"""
        response = await client.get("/questions/non-existent-question-id/details")

        # アサーション
        assert response.status_code == 404
        data = response.json()
        assert "見つかりません" in data["detail"]


class TestAnswerIntegration:
    """回答機能の統合テストクラス"""

    @pytest_asyncio.is_async_test
    async def test_complete_answer_workflow(self, client: AsyncClient):
        """回答機能の完全なワークフローテスト"""
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

        # 3. 回答作成
        answer_data = {"question_id": question_id, "answer": "統合テストの回答です"}
        answer_response = await client.post("/answers", json=answer_data)
        assert answer_response.status_code == 200
        answer_id = answer_response.json()["id"]

        # 4. 回答一覧で確認
        answers_response = await client.get("/answers")
        assert answers_response.status_code == 200
        answers = answers_response.json()
        assert len(answers) == 1
        assert answers[0]["id"] == answer_id

        # 5. 回答詳細で確認
        detail_response = await client.get(f"/answers/{answer_id}")
        assert detail_response.status_code == 200
        detail = detail_response.json()
        assert detail["answer"] == answer_data["answer"]
        assert detail["question"]["question"] == question_data["question"]

        # 6. 質問別回答取得で確認
        question_answers_response = await client.get(
            f"/questions/{question_id}/answers"
        )
        assert question_answers_response.status_code == 200
        question_answers = question_answers_response.json()
        assert len(question_answers) == 1
        assert question_answers[0]["id"] == answer_id

        # 7. 質問と回答の統合詳細で確認
        integrated_response = await client.get(f"/questions/{question_id}/details")
        assert integrated_response.status_code == 200
        integrated = integrated_response.json()
        assert integrated["question"]["id"] == question_id
        assert len(integrated["answers"]) == 1
        assert integrated["answer_count"] == 1
        assert integrated["answers"][0]["id"] == answer_id

    @pytest_asyncio.is_async_test
    async def test_multiple_answers_per_question(self, client: AsyncClient):
        """1つの質問に対する複数回答のテスト"""
        # 事前準備
        genre_data = {"genre_name": "複数回答テスト"}
        genre_response = await client.post("/genres", json=genre_data)
        genre_id = genre_response.json()["id"]

        question_data = {"genre_id": genre_id, "question": "複数回答が可能な質問"}
        question_response = await client.post("/questions", json=question_data)
        question_id = question_response.json()["id"]

        # 複数の回答を作成
        answers = [
            {"question_id": question_id, "answer": "回答1: 最初の視点から"},
            {"question_id": question_id, "answer": "回答2: 別の角度から"},
            {"question_id": question_id, "answer": "回答3: 追加の情報として"},
        ]

        created_answer_ids = []
        for answer in answers:
            response = await client.post("/answers", json=answer)
            assert response.status_code == 200
            created_answer_ids.append(response.json()["id"])

        # 質問の詳細で全回答が取得できることを確認
        details_response = await client.get(f"/questions/{question_id}/details")
        assert details_response.status_code == 200
        details = details_response.json()

        assert details["answer_count"] == 3
        assert len(details["answers"]) == 3

        # 作成した回答がすべて含まれていることを確認
        returned_answer_ids = [a["id"] for a in details["answers"]]
        for created_id in created_answer_ids:
            assert created_id in returned_answer_ids
