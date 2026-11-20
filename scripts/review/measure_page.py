#!/usr/bin/env python3
"""
scripts/review/measure_page.py — 自動判定の Claude が報告ページを計測するための道具（計測ツールを直接は渡さない）

  python3 -I measure_page.py run   <名前> <規則>            # 束の計測ページを全部 2 回ずつ開く
  python3 -I measure_page.py shoot <名前> <規則> <番号>     # 束の計測ページの <番号>（1 から）を 1 枚撮る

- 開けるのは束の sites.txt に載っている報告ページだけ（ほかの場所を開かせない＝外へ何かを送る道にしない）
- <規則> は "" か、ファイル名のカンマ区切り。ファイルは今の規則の置き場か作業場所にある .json だけ
  （例: merged-rules.json,popunder-rules.json,rules-reported.json,security-rules.json,try-1.json）
- 出力は作業場所の measure-<名前>.json / shot-<名前>.png に固定（上書きはしない）
- 場所は auto_judge.py が環境変数で渡す: AUTO_JUDGE_SCRATCH・AUTO_JUDGE_SITES・AUTO_JUDGE_RULES・AUTO_JUDGE_BIN
"""
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I でも同じ場所の fetch_page を読む（Claude は書けない場所）
from fetch_page import is_public, load_sites  # noqa: E402

NAME = re.compile(r"[A-Za-z0-9_-]{1,60}")
RULE = re.compile(r"[A-Za-z0-9_-][A-Za-z0-9_.-]{0,80}\.json")


def fail(msg: str) -> int:
    print(msg, file=sys.stderr)
    return 2


def main() -> int:
    try:
        scratch = Path(os.environ["AUTO_JUDGE_SCRATCH"])
        sites_file = Path(os.environ["AUTO_JUDGE_SITES"])
        rules_dir = Path(os.environ["AUTO_JUDGE_RULES"])
        binary = os.environ["AUTO_JUDGE_BIN"]
    except KeyError as e:
        return fail(f"{e} が無い")
    a = sys.argv[1:]
    if len(a) < 3 or a[0] not in ("run", "shoot") or (a[0] == "shoot") != (len(a) == 4) or len(a) > 4:
        return fail("使い方: run <名前> <規則> / shoot <名前> <規則> <番号>")
    mode, name, rules_arg = a[0], a[1], a[2]
    if not NAME.fullmatch(name):
        return fail("名前は英数字と _- だけ（60 文字まで）")
    rules: list[str] = []
    for r in filter(None, rules_arg.split(",")):
        if not RULE.fullmatch(r) or ".." in r:
            return fail(f"規則はファイル名だけ: {r}")
        p = rules_dir / r if (rules_dir / r).exists() else scratch / r
        if not p.exists():
            return fail(f"規則のファイルが無い: {r}")
        rules.append(str(p))
    # 報告者が送った URL なので、http/https で外のアドレスのページだけ開く（家の中のネットワークなどは開かない）
    sites = load_sites(sites_file)
    bad = [i + 1 for i, u in enumerate(sites) if not is_public(u)]
    if bad:
        print(f"開かない（外のアドレスでない・http/https でない）: 番号 {bad}")
    if mode == "run":
        checked = scratch / ".sites-checked.txt"
        checked.write_text("".join(u + "\n" for u in sites if is_public(u)))
        sites_file = checked
        out = scratch / f"measure-{name}.json"
        if out.exists():
            return fail(f"もうある: {out.name}")
        cmd = [binary, "run", "--config", name, "--rules", ",".join(rules), "--sites", str(sites_file),
               "--out", str(out), "--wait", "10", "--repeat", "2", "--concurrency", "1"]
    else:
        if not a[3].isdigit() or not 1 <= int(a[3]) <= len(sites):
            return fail(f"番号は 1〜{len(sites)}")
        if int(a[3]) in bad:
            return fail("そのページは開かない（外のアドレスでない）")
        out = scratch / f"shot-{name}.png"
        if out.exists():
            return fail(f"もうある: {out.name}")
        cmd = [binary, "shoot", "--site", sites[int(a[3]) - 1], "--rules", ",".join(rules),
               "--out", str(out), "--wait", "10"]
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
    print((p.stdout + p.stderr)[-1500:])
    if p.returncode == 0:
        print(f"保存: {out}")
    return p.returncode


if __name__ == "__main__":
    sys.exit(main())
