# bedrock-test

## 環境構築

Devcontainerの開発を前提にしています。

### 1. 言語管理

開発環境の管理はmiseを使用しています。以下のコマンドでインストールします。

```bash
mise install
mise settings add idiomatic_version_file_enable_tools python
```

### 2. Pythonの依存関係のインストール

Python の依存関係のインストールと仮想環境の有効化は
`backend` ディレクトリで実行します。

```bash
cd backend
uv sync
. .venv/bin/activate
```
