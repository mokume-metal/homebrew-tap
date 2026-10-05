#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 mokume-metal
# SPDX-License-Identifier: MIT
#
# .github/ の定義をリポジトリ設定とルールセットへ書き込む (#11)。メンテナが手で打つ。
#
# 定義を変える PR を merge したら、main を最新にしてから打つ。打ち忘れは
# settings-drift.yml の push 契機が赤で知らせる。
#
# **古いツリーからは書き込まない。** 照合と違って書き込みは実設定を巻き戻せてしまう —
# merge 済みの定義より古い定義を書けば、守りを黙って外すことになる。手元の定義が
# origin/main と違えば止める (確かめた上で PR の定義を先に当てたいときは --force)。
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
# shellcheck source=scripts/settings-lib.sh
. scripts/settings-lib.sh

force=0
case "${1:-}" in
  --force) force=1 ;;
  "") ;;
  *) echo "使い方: apply-settings.sh [--force]" >&2; exit 64 ;;
esac

git fetch -q origin main
if ! git diff --quiet FETCH_HEAD -- "$SETTINGS_DEF" "$RULESETS_DIR"; then
  if [ "$force" = 1 ]; then
    echo "注: 手元の定義は origin/main と違う。--force なのでそのまま書き込む" >&2
  else
    echo "NG: 手元の定義が origin/main と違う。main を最新にしてから打つ (承知の上なら --force)" >&2
    git diff --stat FETCH_HEAD -- "$SETTINGS_DEF" "$RULESETS_DIR" >&2
    exit 1
  fi
fi

gh api -X PATCH "repos/$REPO" --input "$SETTINGS_DEF" >/dev/null
echo "applied: repo-settings"

for f in "$RULESETS_DIR"/*.json; do
  name="$(jq -r .name "$f")"
  id="$(ruleset_id "$name")"
  if [ -n "$id" ]; then
    gh api -X PUT "repos/$REPO/rulesets/$id" --input "$f" >/dev/null
    echo "applied: ruleset $name (更新 id=$id)"
  else
    id="$(gh api -X POST "repos/$REPO/rulesets" --input "$f" --jq .id)"
    echo "applied: ruleset $name (作成 id=$id)"
  fi
done

echo "照合: bash scripts/check-settings.sh"
