# SPDX-FileCopyrightText: 2026 mokume-metal
# SPDX-License-Identifier: MIT
#
# リポジトリ設定の定義 (.github/repo-settings.json と .github/rulesets/*.json) と
# GitHub 側の実設定を突き合わせる部品。check-settings.sh と apply-settings.sh が読む (#11)。
#
# **正本は定義ファイルで、GitHub 側はその写しにすぎない。** 本体 mokume の
# .github/rulesets/ と同じ扱いだが、仕組みは tap の規模に合わせて小さくしてある。

REPO="${GITHUB_REPOSITORY:-mokume-metal/homebrew-tap}"
SETTINGS_DEF=.github/repo-settings.json
RULESETS_DIR=.github/rulesets

# 実設定を定義の形へ射影する jq の関数。**定義に書いた鍵だけを比べる。**
# GitHub は返す JSON に既定値の鍵 (id・日時・リンク・後から増えた引数) を足してくるので、
# 全体を比べると定義を変えていないのに毎回ずれて見える。定義に無い**ルール**が増えた場合は、
# 配列の長さが食い違うのでそのまま差分に出る。
#
# rules はどちらも type で並べてから比べる (並び順は意味を持たない)
readonly PROJECT_JQ='
def sort_rules: if type == "object" and has("rules") then .rules |= sort_by(.type) else . end;
def proj($d):
  if ($d | type) == "object" and type == "object" then
    . as $l | reduce ($d | keys[]) as $k ({}; .[$k] = ($l[$k] | proj($d[$k])))
  elif ($d | type) == "array" and type == "array" then
    . as $l | [range(0; length) as $i | $l[$i] | proj($d[$i])]
  else . end;
'

# 名前から repository 自身の ruleset の id を引く。無ければ空
ruleset_id() {
  gh api "repos/$REPO/rulesets?includes_parents=false" \
    --jq ".[] | select(.name == \"$1\") | .id"
}
