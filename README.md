# gcloud-wrapper

gcloud の ADC（Application Default Credentials）に含まれる refresh token をローカルに平文保存せず、1Password に退避する仕組み。

## 背景・目的

`gcloud auth application-default login` が生成する `~/.config/gcloud/application_default_credentials.json` は、長命な refresh token を平文で well-known パスに置く。ディスク走査型マルウェア（Shai-Hulud など）の格好の標的になる。

この仕組みでは：
- refresh token を 1Password ドキュメントに退避し、ローカルの平文ファイルを削除する
- gcloud 実行時に 1Password から読み出し、OAuth2 トークンエンドポイントで 1h の access token を発行して `CLOUDSDK_AUTH_ACCESS_TOKEN` に注入する
- **refresh token がディスクに一切残らない**

## ファイル構成

```
gcloud-op.zsh   zsh 関数群（~/.zshrc から source する）
mint.py         1Password の ADC JSON → access token 発行（gcloud-op.zsh から呼ばれる）
```

実際の配置先: `~/.config/gcloud-1password/`

## セットアップ

### 前提

- [1Password CLI](https://developer.1password.com/docs/cli/)（`op`）インストール済み
- 1Password アプリ → 設定 → 開発者 →「1Password アプリを使って CLI リクエストを認証する」をオン
- `gcloud` CLI インストール済み、`python3` が PATH 上にあること

### インストール

```zsh
mkdir -p ~/.config/gcloud-1password
cp gcloud-op.zsh mint.py ~/.config/gcloud-1password/
```

`~/.zshrc` の末尾に追記：

```zsh
source ~/.config/gcloud-1password/gcloud-op.zsh
```

### 初回セットアップ

```zsh
exec zsh
gcloud-1p-init
```

ブラウザで Google 認証 → 1Password に保存 → ローカルの平文ファイルを削除。

疎通確認：

```zsh
gcloud projects list
```

## 日常的な使い方

`gcloud` コマンドをそのまま使うだけ。透過的に動作する。

```zsh
gcloud projects list
gcloud compute instances list --project my-project
```

- **初回（端末起動後の最初の gcloud）**: 1Password に Touch ID でアクセス → トークン発行
- **2回目以降（同じ端末セッション内）**: キャッシュを使用（高速）
- **8時間後**: reauth ポリシーで自動的にブラウザ再ログインを促す → 1Password を自動更新

## アカウント切り替え

別のアカウントに切り替えたい場合は `gcloud-1p-init` を再実行する。1Password ドキュメントが上書きされる。

現在のセッションのキャッシュを即時破棄したい場合：

```zsh
unset _GCLOUD_OP_TOKEN _GCLOUD_OP_EXP
```

## 環境変数

| 変数 | 既定値 | 用途 |
|---|---|---|
| `OP_GCLOUD_VAULT` | `Private` | 1Password の vault 名 |
| `OP_GCLOUD_ITEM` | `gcloud ADC` | 1Password ドキュメントのタイトル |

## ロールバック手順

本スクリプトの利用をやめる場合：

1. `~/.zshrc` から `source` 行を削除して `exec zsh` する
2. 通常通り `gcloud auth application-default login` を再実行する

## 設計上のトレードオフ

- **キャッシュ対象**: 1h の access token のみ（refresh token は非キャッシュ）。非 export のシェル変数に保持し、子プロセスには継承されない
- **gcloud 本体ストアも削除**: `credentials.db` / `legacy_credentials` も削除するため、素の `gcloud`（関数を通さない）は未認証になる
- **認証ログの自動制御**: 認証時の `refresh_token` がログに残らないよう、`gcloud-op` は `core/log_http false` の設定適用および `~/.config/gcloud/logs/` の自動削除を行います
- **gsutil 非対応**: `CLOUDSDK_AUTH_ACCESS_TOKEN` を gsutil は読まない。`gcloud storage` を使うこと
- **対話端末前提**: 8h ごとのブラウザ再認証が必要なため、無人バッチ用途には不向き
