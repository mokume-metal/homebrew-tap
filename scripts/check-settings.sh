#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 mokume-metal
# SPDX-License-Identifier: MIT
#
# リポジトリ設定とルールセットが、.github/ の定義どおりかを照合する (#11)。
#
#   check-settings.sh                          全部を照合する (メンテナが手元で打つ)
#   check-settings.sh --without-bypass-actors  bypass_actors を除いて照合する (CI 用)
#
# **塞ぐのは「守っているつもりの設定が黙って外れている」である。** main が無保護で
# auto-merge も不許可のあいだ、`gh pr merge --auto` は CI を待たずに即マージした —
# しかもエラーにならないので、赤にも出なかった (#11)。設定は PR の内容と独立に
# 管理画面から変わるので、定期的に照合して外れたら名乗る (settings-drift.yml)。
#
# **bypass_actors は ruleset を書ける認証にしか返らない** (本体 mokume#99 で実測)。
# CI の GITHUB_TOKEN では読めないので、そこだけ「見ていない」と名乗って残りを照合する。
# 引数なしでは、読めなければ赤になる。
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
# shellcheck source=scripts/settings-lib.sh
. scripts/settings-lib.sh

with_bypass=1
case "${1:-}" in
  --without-bypass-actors) with_bypass=0 ;;
  "") ;;
  *) echo "使い方: check-settings.sh [--without-bypass-actors]" >&2; exit 64 ;;
esac

ng=0
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# 定義と実設定 (定義の形へ射影済み) を並べて差分を出す。一致すれば 0
compare() {
  local label="$1" def="$2" live="$3"
  if diff -u --label "定義 ($label)" --label "実設定 ($label)" "$def" "$live"; then
    echo "ok: $label"
  else
    echo "NG: $label が定義とずれている (- 定義 / + 実設定)" >&2
    ng=1
  fi
}

# --- リポジトリ設定 ---
gh api "repos/$REPO" >"$work/repo.json"
jq -S . "$SETTINGS_DEF" >"$work/repo.def"
jq -S --slurpfile d "$SETTINGS_DEF" "$PROJECT_JQ proj(\$d[0])" "$work/repo.json" >"$work/repo.live"
compare "repo-settings" "$work/repo.def" "$work/repo.live"

# --- ルールセット ---
# 定義の側から引く。定義に無い ruleset が実設定にあれば、それも外れとして名乗る
declare -a names=()
for f in "$RULESETS_DIR"/*.json; do
  name="$(jq -r .name "$f")"
  names+=("$name")
  id="$(ruleset_id "$name")"
  if [ -z "$id" ]; then
    echo "NG: ruleset $name が実設定に無い (定義はあるが未適用)" >&2
    ng=1
    continue
  fi
  gh api "repos/$REPO/rulesets/$id" >"$work/rs.json"

  if [ "$with_bypass" = 1 ] && ! jq -e 'has("bypass_actors")' "$work/rs.json" >/dev/null; then
    echo "NG: ruleset $name の bypass_actors が読めない (ruleset を書ける認証で打つか、--without-bypass-actors)" >&2
    ng=1
    continue
  fi

  strip='.'
  [ "$with_bypass" = 1 ] || strip='del(.bypass_actors)'
  jq -S "$PROJECT_JQ sort_rules | $strip" "$f" >"$work/rs.def"
  jq -S --slurpfile d "$work/rs.def" "$PROJECT_JQ sort_rules | proj(\$d[0]) | $strip" "$work/rs.json" >"$work/rs.live"
  compare "ruleset $name" "$work/rs.def" "$work/rs.live"
done

while read -r extra; do
  [ -n "$extra" ] || continue
  printf '%s\n' "${names[@]}" | grep -qxF "$extra" && continue
  echo "NG: ruleset $extra は実設定にだけある (定義に足すか、実設定から消す)" >&2
  ng=1
done < <(gh api "repos/$REPO/rulesets?includes_parents=false" --jq '.[].name')

if [ "$with_bypass" = 0 ]; then
  echo "注: bypass_actors は照合していない (--without-bypass-actors)"
fi
exit "$ng"
