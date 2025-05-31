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

pythonの依存関係のインストール

```bash
cd backend
uv sync
```

pythonの仮想環境実行

```bash
. ./.venv/bin/activate
```
