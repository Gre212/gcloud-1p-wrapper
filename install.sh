#!/usr/bin/env bash
set -e

INSTALL_DIR="${HOME}/.config/gcloud-1password"
ZSHRC="${HOME}/.zshrc"

echo "=> Installing gcloud-wrapper to ${INSTALL_DIR}..."

# ディレクトリの作成
mkdir -p "$INSTALL_DIR"

# リポジトリ内のファイルをコピー
if [[ -f "gcloud-op.zsh" && -f "mint.py" ]]; then
    cp gcloud-op.zsh mint.py "$INSTALL_DIR/"
else
    echo "Error: gcloud-op.zsh or mint.py not found in current directory."
    echo "Please run this script from the root of the repository."
    exit 1
fi

# ~/.zshrc への追記
SOURCE_LINE="source ${INSTALL_DIR}/gcloud-op.zsh"
if ! grep -qF "$SOURCE_LINE" "$ZSHRC" 2>/dev/null; then
    echo "=> Adding source command to ${ZSHRC}..."
    echo -e "\n# gcloud-wrapper\n$SOURCE_LINE" >> "$ZSHRC"
else
    echo "=> Source command already exists in ${ZSHRC}."
fi

echo "=> Installation completed!"
echo "--------------------------------------------------------"
echo "To apply changes, please restart your terminal or run:"
echo "  exec zsh"
echo ""
echo "After that, run the initial setup:"
echo "  gcloud-1p-init"
echo "--------------------------------------------------------"
