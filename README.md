# gcloud-wrapper

gcloud の ADC（Application Default Credentials）に含まれる refresh token をローカルに平文保存せず、1Password に退避する仕組みです。

## 背景・目的

`gcloud auth application-default login` が生成する `~/.config/gcloud/application_default_credentials.json` は、長命な refresh token を平文でディスクに保存するため、ディスク走査型マルウェア（Shai-Hulud など）の標的になりえます。

このツールでは、1Password を活用した以下の仕組みで、平文保存を行わないようにしています。
- refresh token を 1Password ドキュメントに退避し、ローカルの平文ファイルを削除
- gcloud 実行時に 1Password から読み出し、OAuth2 トークンエンドポイントで 1h の access token を発行して `CLOUDSDK_AUTH_ACCESS_TOKEN` に注入

gcloud コマンドをラップしているため、今までと同じ使い方で透過的に動作します。

## ファイル構成

```
gcloud-op.zsh   zsh 関数群（~/.zshrc から source する）
mint.py         1Password の ADC JSON → access token 発行（gcloud-op.zsh から呼ばれる）
```

実際の配置先は `~/.config/gcloud-1password/` です。

## セットアップ

### 前提

- [1Password CLI](https://developer.1password.com/docs/cli/)（`op`）インストール済み
- 1Password アプリ → 設定 → 開発者 →「1Password アプリを使って CLI リクエストを認証する」をオン
- `gcloud` CLI インストール済み、`python3` が PATH 上にあること

### インストール

リポジトリをクローンまたはダウンロードし、ディレクトリ内でインストールスクリプトを実行します。

```zsh
git clone https://github.com/Gre212/gcloud-1p-wrapper.git
cd gcloud-1p-wrapper
./install.sh
```

※ スクリプトはファイルのコピーと `~/.zshrc` への `source` コマンド追記を自動で行います。

### 初回セットアップ

```zsh
exec zsh
gcloud-op-init
```

ブラウザで Google 認証を行い、1Password に保存したのち、ローカルの平文ファイルを削除します。

以下のコマンドで疎通確認を行います。

```zsh
gcloud projects list
```

## 日常的な使い方

`gcloud` コマンドをそのまま使うだけで透過的に動作します。

```zsh
gcloud projects list
gcloud compute instances list --project my-project
```

### Terraform コマンドについて

Terraform (GCP プロバイダ) を利用する場合を想定し、`terraform-op` というコマンドを提供しています。このコマンドを使用することで、 Terraform を実行する際にも 1Password 経由で ADC 認証を利用できます。

```zsh
terraform-op plan
```

AWS など他クラウドの作業を意図せず妨害しないよう別名としていますが、Google Cloud のみの利用であれば、`~/.zshrc` に `alias terraform=terraform-op` を設定することで完全に透過的な使い勝手になります。

```zsh:.zshrc
alias terraform=terraform-op
```

### トークンのライフサイクル

- **初回（端末起動後の最初の gcloud）**: 1Password に Touch ID でアクセス → トークン発行
- **2回目以降（同じ端末セッション内）**: シェル変数のキャッシュを使用（高速）
- **トークン期限切れ後**: reauth ポリシーで自動的にブラウザ再ログインを促す → 1Password を自動更新

## アカウント切り替え

別のアカウントに切り替えたい場合は `gcloud-op-init` を再実行してください。1Password ドキュメントが上書きされます。

現在のセッションのキャッシュを即時破棄したい場合は以下を実行します。

```zsh
unset _GCLOUD_OP_TOKEN _GCLOUD_OP_EXP
```

## 環境変数

| 変数 | 既定値 | 用途 |
|---|---|---|
| `OP_GCLOUD_VAULT` | `Private` | 1Password の vault 名 |
| `OP_GCLOUD_ITEM` | `gcloud ADC` | 1Password ドキュメントのタイトル |

## SDK・アプリケーション開発での利用について

本ツールはローカルの `application_default_credentials.json` を物理的に削除するため、**現時点では Python, Go などの Google Cloud Client Libraries (SDK) には非対応です。**

## ロールバック手順

本スクリプトの利用をやめる場合は以下の手順を実行します。

1. `~/.zshrc` から `source` 行を削除して `exec zsh` する
2. 通常通り `gcloud auth application-default login` を再実行します

## 設計上のトレードオフ

- **キャッシュ対象**: 1h の access token のみ（refresh token は非キャッシュ）。非 export のシェル変数に保持し、子プロセスには継承されません。
- **gcloud 本体ストアも削除**: `credentials.db` / `legacy_credentials` も削除するため、素の `gcloud`（関数を通さない）は未認証になります。
- **認証ログの自動制御**: 認証時の `refresh_token` がログに残らないよう、`gcloud-op` は `core/log_http false` の設定適用および `~/.config/gcloud/logs/` の自動削除を行います。
- **gsutil 非対応**: `CLOUDSDK_AUTH_ACCESS_TOKEN` を gsutil は読まないため、`gcloud storage` を使用してください。
- **対話端末前提**: 定期的なブラウザ再認証が必要になる場合があるため、無人バッチ用途には不向きです。
