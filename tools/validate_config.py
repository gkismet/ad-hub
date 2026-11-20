"""校验 config/apps/*.json。用法：python tools/validate_config.py [文件...]
不带参数时校验 config/apps/ 下所有非 _ 开头的文件。只用标准库。
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APPS = ROOT / "config" / "apps"
FORMATS = {"interstitial", "rewarded", "banner", "app_open"}
OPTIONAL_UNITS = {"app_open"}  # 0.3.0 新增，旧配置可以没有这个键
MEDIATIONS = {"max", "admob"}
NAME_RE = re.compile(r"^[a-z][a-z0-9_]{1,39}$")
ADMOB_TEST_PUB = "ca-app-pub-3940256099942544"
GLOBAL_KEYS = ["firstInterstitialDelaySec", "interstitialMinIntervalSec",
               "interstitialMaxPerSession", "interstitialMaxPerDay"]
CAP_KEYS = ["minIntervalSec", "maxPerSession", "maxPerDay"]


def check(path: Path) -> list[str]:
    errs, warns = [], []
    try:
        cfg = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        return [f"JSON 解析失败: {e}"]

    def need(key, typ):
        if key not in cfg:
            errs.append(f"缺少字段 {key}")
            return None
        if not isinstance(cfg[key], typ):
            errs.append(f"{key} 类型应为 {typ.__name__}")
            return None
        return cfg[key]

    if need("schemaVersion", int) not in (None, 1):
        errs.append("schemaVersion 目前只支持 1")
    app = need("app", str)
    if app is not None:
        if not NAME_RE.match(app):
            errs.append("app 只能用小写字母/数字/下划线")
        if app != path.stem:
            errs.append(f"app ({app}) 必须和文件名 ({path.stem}) 一致")
    need("owner", str)
    need("enabled", bool)
    med = need("mediation", str)
    if med is not None and med not in MEDIATIONS:
        errs.append(f"mediation 只能是 {sorted(MEDIATIONS)}")
    test_mode = need("testMode", bool)
    if test_mode:
        warns.append("testMode=true（上线前必须改成 false，否则 AdMob 走测试广告没有收入）")
    sdk_key = cfg.get("maxSdkKey", "")
    if not isinstance(sdk_key, str):
        errs.append("maxSdkKey 应为字符串")
    elif med == "max" and not sdk_key:
        warns.append("mediation=max 但 maxSdkKey 为空（Flutter 端初始化需要；Unity 端在 Integration Manager 里填）")

    units = need("units", dict) or {}
    for plat in ("android", "ios"):
        u = units.get(plat)
        if not isinstance(u, dict):
            errs.append(f"units.{plat} 缺失")
            continue
        for fmt in FORMATS:
            v = u.get(fmt, "" if fmt in OPTIONAL_UNITS else None)
            if not isinstance(v, str):
                errs.append(f"units.{plat}.{fmt} 应为字符串（没有就填空串）")
                continue
            if med == "admob" and v and not v.startswith("ca-app-pub-"):
                errs.append(f"units.{plat}.{fmt}: mediation=admob 时应为 ca-app-pub- 开头")
            if med == "max" and v.startswith("ca-app-pub-"):
                errs.append(f"units.{plat}.{fmt}: mediation=max 时应填 MAX 的 Ad Unit ID，不是 AdMob 的")
            if test_mode is False and ADMOB_TEST_PUB in v:
                errs.append(f"units.{plat}.{fmt}: testMode=false 但用的是 Google 测试 ID")

    glob = need("global", dict) or {}
    for k in GLOBAL_KEYS:
        if not isinstance(glob.get(k), int) or glob.get(k) < 0:
            errs.append(f"global.{k} 应为 >=0 的整数（0 = 不限制）")
    v = glob.get("appOpenMinBackgroundSec", 0)  # 可选
    if not isinstance(v, int) or isinstance(v, bool) or v < 0:
        errs.append("global.appOpenMinBackgroundSec 应为 >=0 的整数（0 = 不限制）")

    pls = need("placements", list) or []
    seen = set()
    used_formats = set()
    for i, p in enumerate(pls):
        tag = f"placements[{i}]"
        if not isinstance(p, dict):
            errs.append(f"{tag} 应为对象")
            continue
        n = p.get("name")
        if not isinstance(n, str) or not NAME_RE.match(n):
            errs.append(f"{tag}.name 只能用小写字母/数字/下划线")
        elif n in seen:
            errs.append(f"广告位名重复: {n}")
        else:
            seen.add(n)
            tag = f"placement '{n}'"
        fmt = p.get("format")
        if fmt not in FORMATS:
            errs.append(f"{tag}.format 只能是 {sorted(FORMATS)}")
        else:
            used_formats.add(fmt)
        if not isinstance(p.get("enabled"), bool):
            errs.append(f"{tag}.enabled 应为 true/false")
        for k in CAP_KEYS:
            if not isinstance(p.get(k), int) or p.get(k) < 0:
                errs.append(f"{tag}.{k} 应为 >=0 的整数（0 = 不限制）")

    for plat in ("android", "ios"):
        u = units.get(plat) if isinstance(units.get(plat), dict) else {}
        for fmt in used_formats:
            if not u.get(fmt):
                warns.append(f"有 {fmt} 广告位，但 units.{plat}.{fmt} 是空的（该平台不会出广告）")

    return errs + [f"[警告] {w}" for w in warns]


def main(argv):
    files = [Path(a) for a in argv] or sorted(p for p in APPS.glob("*.json") if not p.name.startswith("_"))
    bad = 0
    for f in files:
        problems = check(f)
        hard = [p for p in problems if not p.startswith("[警告]")]
        status = "FAIL" if hard else "OK"
        print(f"{status}  {f.name}")
        for p in problems:
            print(f"      - {p}")
        bad += bool(hard)
    print(f"\n{len(files) - bad}/{len(files)} 通过")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
