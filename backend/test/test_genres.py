import pytest_asyncio
from httpx import AsyncClient


class TestGenreEndpoints:
    """ジャンルエンドポイントのテストクラス"""

    @pytest_asyncio.is_async_test
    async def test_create_genre_success(self, client: AsyncClient):
        """ジャンル作成成功のテスト"""
        # テストデータ
        genre_data = {"genre_name": "プログラミング"}

        # APIリクエスト
        response = await client.post("/genres", json=genre_data)

        # アサーション
        assert response.status_code == 200
        data = response.json()
        assert data["genre_name"] == "プログラミング"
        assert "id" in data
        assert "created_at" in data
        assert "updated_at" in data
        assert len(data["id"]) == 36  # UUID形式

    @pytest_asyncio.is_async_test
    async def test_create_genre_duplicate_name(self, client: AsyncClient):
        """ジャンル名重複エラーのテスト"""
        # 最初のジャンルを作成
        genre_data = {"genre_name": "データベース"}
        await client.post("/genres", json=genre_data)

        # 同じ名前で再度作成を試行
        response = await client.post("/genres", json=genre_data)

        # アサーション
        assert response.status_code == 400
        data = response.json()
        assert "既に存在します" in data["detail"]

    @pytest_asyncio.is_async_test
    async def test_create_genre_empty_name(self, client: AsyncClient):
        """空のジャンル名でのバリデーションエラーテスト"""
        genre_data = {"genre_name": ""}

        response = await client.post("/genres", json=genre_data)

        # アサーション
        assert response.status_code == 422  # バリデーションエラー
        data = response.json()
        assert "detail" in data

    @pytest_asyncio.is_async_test
    async def test_create_genre_long_name(self, client: AsyncClient):
        """長すぎるジャンル名でのバリデーションエラーテスト"""
        # 256文字のジャンル名
        long_name = "a" * 256
        genre_data = {"genre_name": long_name}

        response = await client.post("/genres", json=genre_data)

        # アサーション
        assert response.status_code == 422  # バリデーションエラー

    @pytest_asyncio.is_async_test
    async def test_get_genres_empty(self, client: AsyncClient):
        """ジャンル一覧取得（空）のテスト"""
        response = await client.get("/genres")

        # アサーション
        assert response.status_code == 200
        data = response.json()
        assert data == []

    @pytest_asyncio.is_async_test
    async def test_get_genres_with_data(self, client: AsyncClient):
        """ジャンル一覧取得（データあり）のテスト"""
        # テストデータを作成
        genres = [
            {"genre_name": "プログラミング"},
            {"genre_name": "データベース"},
            {"genre_name": "機械学習"},
        ]

        # ジャンルを作成
        for genre in genres:
            await client.post("/genres", json=genre)

        # 一覧取得
        response = await client.get("/genres")

        # アサーション
        assert response.status_code == 200
        data = response.json()
        assert len(data) == 3
        assert all("id" in genre for genre in data)
        assert all("genre_name" in genre for genre in data)

        # ジャンル名の確認
        genre_names = [genre["genre_name"] for genre in data]
        assert "プログラミング" in genre_names
        assert "データベース" in genre_names
        assert "機械学習" in genre_names

    @pytest_asyncio.is_async_test
    async def test_health_check(self, client: AsyncClient):
        """ヘルスチェックエンドポイントのテスト"""
        response = await client.get("/health_check")

        # アサーション
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert "timestamp" in data
