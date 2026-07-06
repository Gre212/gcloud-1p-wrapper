# gcloud-op.zsh
# gcloud ADC の refresh token を 1Password に退避し、実行時にアクセストークンを注入する。
# ~/.zshrc から source する。
#
# 環境変数で上書き可能:
#   OP_GCLOUD_VAULT   1Password の vault 名（既定: Private）
#   OP_GCLOUD_ITEM    1Password ドキュメントのタイトル（既定: gcloud ADC）
#
# 初回セットアップ: gcloud-1p-init を実行する。

zmodload zsh/datetime 2>/dev/null

: ${OP_GCLOUD_VAULT:=Private}
: ${OP_GCLOUD_ITEM:=gcloud ADC}

_GCLOUD_OP_DIR="${${(%):-%x}:A:h}"

# 1Password から ADC JSON を読み、アクセストークンを発行する。
# 成功: access_token と expires_in を改行区切りで stdout に出力。
# reauth 失効: 終了コード 2（セッション切れ）。
# その他の失敗: 終了コード 1。
_gcloud_op_mint() {
  command op document get "$OP_GCLOUD_ITEM" --vault "$OP_GCLOUD_VAULT" --force 2>/dev/null \
    | command python3 -I "$_GCLOUD_OP_DIR/mint.py" \
    || return $?
}

# ADC 再取得 → 1Password 上書き → ローカル平文削除の一連。
# gcloud-1p-init と reauth 失効時の両方から呼ばれる。
# 引数: なし（OP_GCLOUD_VAULT / OP_GCLOUD_ITEM を参照）
_gcloud_op_relogin() {
  local adc_path="${CLOUDSDK_CONFIG:-$HOME/.config/gcloud}/application_default_credentials.json"
  local vault="$OP_GCLOUD_VAULT"
  local item="$OP_GCLOUD_ITEM"

  # ログ無効化設定
  command gcloud config set core/log_http false &>/dev/null

  # ブラウザ認証（新 refresh token を発行）
  print "[gcloud-op] gcloud auth application-default login を実行します…"
  command gcloud auth application-default login || return 1

  [[ -f "$adc_path" ]] || { print -u2 "[gcloud-op] ADC ファイルが見つかりません: $adc_path"; return 1; }

  # 1Password ドキュメントに反映（あれば更新、なければ作成）
  if command op document get "$item" --vault "$vault" &>/dev/null; then
    command op document edit "$item" "$adc_path" --vault "$vault" || return 1
    print "[gcloud-op] 1Password ドキュメントを更新しました（$item）"
  else
    command op document create "$adc_path" --title "$item" --vault "$vault" || return 1
    print "[gcloud-op] 1Password ドキュメントを作成しました（$item）"
  fi

  # ローカル平文・ログを secure delete
  local gcloud_dir="${CLOUDSDK_CONFIG:-$HOME/.config/gcloud}"
  local targets=(
    "$gcloud_dir/application_default_credentials.json"
    "$gcloud_dir/credentials.db"
    "$gcloud_dir/access_tokens.db"
    "$gcloud_dir/legacy_credentials"
    "$gcloud_dir/logs"
  )
  for t in $targets; do
    if [[ -e "$t" ]]; then
      command rm -Prf "$t" 2>/dev/null && print "[gcloud-op] 削除: $t" || print -u2 "[gcloud-op] 削除失敗: $t"
    fi
  done

  # セッションキャッシュを無効化（次回呼び出しで再発行させる）
  unset _GCLOUD_OP_TOKEN _GCLOUD_OP_EXP
  print "[gcloud-op] 完了。"
}

# トークンを確実に取得・キャッシュする内部関数
_gcloud_op_ensure_token() {
  local now=$EPOCHSECONDS out rc

  if [[ -z "${_GCLOUD_OP_TOKEN:-}" || -z "${_GCLOUD_OP_EXP:-}" || $now -ge $_GCLOUD_OP_EXP ]]; then
    out=$(_gcloud_op_mint); rc=$?
    if (( rc == 2 )); then
      print -u2 "[gcloud-op] セッション切れ。再ログインします…"
      _gcloud_op_relogin || return 1
      out=$(_gcloud_op_mint); rc=$?
    fi
    (( rc == 0 )) || { print -u2 "[gcloud-op] トークン取得に失敗しました"; return 1; }
    _GCLOUD_OP_TOKEN=${out%%$'\n'*}
    local ttl=${out##*$'\n'}
    _GCLOUD_OP_EXP=$(( now + ttl - 300 ))
  fi
  return 0
}

# gcloud を上書きする関数。
# - 非 export の _GCLOUD_OP_TOKEN / _GCLOUD_OP_EXP にアクセストークンをセッション内キャッシュ。
# - 失効時のみ 1Password を読む。refresh token は python stdin にだけ流し argv に載せない。
# - reauth 失敗（終了コード 2）を検知したら _gcloud_op_relogin を実行し一度だけリトライ。
# - env で本物の gcloud に渡すので関数再帰しない。トークンは子プロセスのみに継承され export されない。
gcloud() {
  emulate -L zsh
  _gcloud_op_ensure_token || return 1
  env CLOUDSDK_AUTH_ACCESS_TOKEN="$_GCLOUD_OP_TOKEN" command gcloud "$@"
}

# terraform 向けに 1h の Access Token を透過的に注入するオプショナルラッパー。
# AWS など他クラウドの利用時に意図せず 1Password 認証が走るのを防ぐため、別名で定義。
terraform-op() {
  emulate -L zsh
  _gcloud_op_ensure_token || return 1
  env GOOGLE_OAUTH_ACCESS_TOKEN="$_GCLOUD_OP_TOKEN" command terraform "$@"
}

# 初回ブートストラップ。一度だけ実行する。
# - _gcloud_op_relogin でブラウザ認証 → 1Password 保存 → ローカル削除
gcloud-1p-init() {
  print "[gcloud-op] 初回セットアップを開始します。"

  _gcloud_op_relogin || return 1

  print ""
  print "[gcloud-op] セットアップ完了！次のコマンドで疎通確認してください:"
  print "  gcloud projects list"
}
