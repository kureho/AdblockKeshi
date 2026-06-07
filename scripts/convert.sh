#!/usr/bin/env bash
set -euo pipefail

# scripts/convert.sh
# 5本のフィルタを取得 → SafariConverterLib で Safari JSON 変換 → 統合 → docs/cdn/ に出力

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CDN_DIR="$PROJECT_DIR/docs/cdn"
CONVERTER="${SAFARI_CONVERTER_BIN:-$SCRIPT_DIR/converter-build/SafariConverterLib/.build/release/ConverterTool}"

if [ ! -x "$CONVERTER" ]; then
  echo "[ERROR] ConverterTool not found at $CONVERTER" >&2
  echo "  Build with: cd $SCRIPT_DIR/converter-build/SafariConverterLib && swift build -c release" >&2
  exit 1
fi

mkdir -p "$CDN_DIR"

TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# filters.yml から URL を抽出
parse_filters() {
  python3 -c "
import yaml
with open('$SCRIPT_DIR/filters.yml') as f:
    data = yaml.safe_load(f)
for f in data['filters']:
    print(f\"{f['name']}\t{f['url']}\t{f['license']}\")
"
}

# 各フィルタを取得
echo "[fetch] downloading filters..."
declare -a FILES=()
declare -a NAMES=()
declare -a LICENSES=()
while IFS=$'\t' read -r name url license; do
  echo "  - $name ($license): $url"
  out="$TMP_DIR/${name}.txt"
  if curl -fsSL --max-time 60 "$url" -o "$out"; then
    FILES+=("$out")
    NAMES+=("$name")
    LICENSES+=("$license")
  else
    echo "[WARN] $name fetch failed, skipping"
  fi
done < <(parse_filters)

if [ ${#FILES[@]} -eq 0 ]; then
  echo "[ERROR] no filters fetched" >&2
  exit 1
fi

echo "[merge] concatenating ${#FILES[@]} filters..."
cat "${FILES[@]}" > "$TMP_DIR/combined.txt"
COMBINED_LINES=$(wc -l < "$TMP_DIR/combined.txt")
echo "  combined lines: $COMBINED_LINES"

echo "[convert] running SafariConverterLib..."
"$CONVERTER" convert \
  --input-path "$TMP_DIR/combined.txt" \
  --safari-rules-json-path "$TMP_DIR/blockerList.json" \
  --safari-version 17

RULE_COUNT=$(jq 'length' "$TMP_DIR/blockerList.json")
JSON_BYTES=$(wc -c < "$TMP_DIR/blockerList.json")
echo "  converted rules: $RULE_COUNT"
echo "  json size: $JSON_BYTES bytes"

if [ "$RULE_COUNT" -gt 150000 ]; then
  echo "[ERROR] rule count $RULE_COUNT exceeds 150k limit" >&2
  exit 1
fi

# 出力
mv "$TMP_DIR/blockerList.json" "$CDN_DIR/blockerList.json"

# version.json 生成（jq で構築）
SHA256=$(shasum -a 256 "$CDN_DIR/blockerList.json" | awk '{print $1}')
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# filters 配列を jq で組み立て
FILTERS_JSON="[]"
for i in "${!NAMES[@]}"; do
  FILTERS_JSON=$(jq -c \
    --arg name "${NAMES[$i]}" \
    --arg license "${LICENSES[$i]}" \
    '. + [{name: $name, license: $license}]' <<< "$FILTERS_JSON")
done

# Plan C Chunk 5: weekly-cdn-sync.yml が書き込んだ既存 reported セクション
# (= moat 行用の rule_count / added_last_month) を preserve する。
EXISTING_REPORTED="null"
if [ -f "$CDN_DIR/version.json" ]; then
  EXISTING_REPORTED=$(jq -c '.reported // null' "$CDN_DIR/version.json")
fi

jq -n \
  --arg generated_at "$GENERATED_AT" \
  --argjson rule_count "$RULE_COUNT" \
  --argjson size_bytes "$JSON_BYTES" \
  --arg sha256 "$SHA256" \
  --argjson filters "$FILTERS_JSON" \
  --argjson reported "$EXISTING_REPORTED" \
  '{generated_at: $generated_at, rule_count: $rule_count, size_bytes: $size_bytes, blocker_list_sha256: $sha256, filters: $filters}
   + (if $reported != null then {reported: $reported} else {} end)' \
  > "$CDN_DIR/version.json"

# bundle 同梱: CDN DL 失敗時の初回起動でも「最終更新日」を表示できるよう App/Resources に同期
cp "$CDN_DIR/version.json" "$PROJECT_DIR/App/Resources/version.json"

echo "[done]"
echo "  $CDN_DIR/blockerList.json ($RULE_COUNT rules, $JSON_BYTES bytes)"
echo "  $CDN_DIR/version.json"
echo "  $PROJECT_DIR/App/Resources/version.json (bundle copy)"
cat "$CDN_DIR/version.json"
