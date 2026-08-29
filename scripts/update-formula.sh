#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 mokume-metal
# SPDX-License-Identifier: MIT
#
# mokume のリリースに formula を追随させる。
#
# **formula がこのリポジトリに居る理由。** formula は url + sha256 を固定で持つので
# 版が上がるたびにファイルが変わる。これを mokume 側に置くと「リリースがリポジトリの
# ファイルを変える」ことになり、あちらの release.yml がまさに避けている迂回 (main へ
# 入れるための PR と必須チェック) が要る (mokume-metal/mokume#398)。
#
# **ビルドし直さない。** 引くのは mokume のリリースが既に作っている配布物そのもの。
# 同じタグから 2 通りの実行ファイルが出る状態を作らないため。
set -euo pipefail

repo="${MOKUME_REPO:-mokume-metal/mokume}"
asset="mokume-macos-arm64.tar.gz"
template="scripts/formula.rb.template"
formula="Formula/mokume.rb"

tag="${1:-}"
if [ -z "$tag" ]; then
  tag="$(gh release view --repo "$repo" --json tagName --jq .tagName)"
fi
version="${tag#v}"
url="https://github.com/$repo/releases/download/$tag/$asset"

# **資産が無いことは失敗ではない。** #397 が入る前のリリースには載っていないので、
# その版に追随しないだけで静かに終える。赤にすると「出す物がまだ無い」と「壊れた」の
# 区別が付かなくなる
if ! gh release view "$tag" --repo "$repo" --json assets --jq '.assets[].name' | grep -qx "$asset"; then
  echo "$tag に $asset が無い。追随しない"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl -fsSL "$url" -o "$work/$asset"
sha="$(shasum -a 256 "$work/$asset" | cut -d' ' -f1)"

mkdir -p "$(dirname "$formula")"
sed -e "s|{{URL}}|$url|" -e "s|{{VERSION}}|$version|" -e "s|{{SHA256}}|$sha|" \
  "$template" > "$work/rendered.rb"

# 置き換え残しは通さない。テンプレートに鍵を足したときに気付ける唯一の場所
if grep -q '{{.*}}' "$work/rendered.rb"; then
  echo "差し込めていない鍵が残っている:" >&2
  grep -o '{{[^}]*}}' "$work/rendered.rb" >&2
  exit 1
fi

if [ -f "$formula" ] && cmp -s "$work/rendered.rb" "$formula"; then
  echo "$tag のまま。変えるものは無い"
  exit 0
fi

cp "$work/rendered.rb" "$formula"
echo "$formula を $tag ($sha) に更新した"

# 呼び手 (ワークフロー) が commit の文言に使う。formula の中身から読み直すより、
# 決めた側がそのまま渡すほうが壊れない
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "tag=$tag"
    echo "changed=true"
  } >> "$GITHUB_OUTPUT"
fi
