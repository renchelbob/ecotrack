import argparse
import json
from pathlib import Path
import re
import sys

import yaml

REQUIRED_SCREENS = (
    "wireframes.png",
    "07_Onboarding_Compact_01_Приветствие.png",
    "08_Onboarding_Compact_07_Препермишен_шагомера.png",
    "09_Onboarding_Compact_08_Подарки_и_152ФЗ.png",
    "14_Main_Compact_16_Главная_Маскот_ФИНАЛ.png",
    "15_Calc_Compact_17_Калькулятор_поездок_ФИНАЛ.png",
    "16_Stats_Compact_05_Статистика_обзор_ФИНАЛ.png",
    "17_Stats_Compact_26_График_выбросов_и_доли_ФИНАЛ.png",
    "18_Stats_Compact_24_История_активности_список_ФИНАЛ.png",
    "19_Profile_Compact_18_Профиль_и_настройки_152ФЗ_ФИНАЛ.png",
    "20_Shop_Compact_19_Витрина_промокодов_ФИНАЛ.png",
    "21_Shop_Compact_20_Корзина_заказов_ФИНАЛ.png",
    "22_Shop_Compact_21_Заказы_QR_коды_ФИНАЛ.png",
    "23_Shop_Compact_22_Заказы_буквенный_промокод_ФИНАЛ.png",
)

FORBIDDEN_PACKAGES = frozenset({
    "build_runner",
    "freezed",
    "freezed_annotation",
    "json_serializable",
    "json_annotation",
    "auto_route",
    "auto_route_generator",
    "retrofit",
    "retrofit_generator",
    "injectable",
    "injectable_generator",
    "riverpod",
    "flutter_riverpod",
    "hooks_riverpod",
    "get",
    "get_it",
    "mobx",
    "hive",
    "hive_flutter",
    "isar",
    "objectbox",
    "drift",
    "maplibre_gl",
    "google_maps_flutter",
    "yandex_mapkit",
    "mockito",
    "mocktail",
})

REQUIRED_DEV_DEPS = frozenset({
    "glados",
    "dart_code_linter",
    "import_lint",
    "sqflite_common_ffi",
})

RUNTIME_FLOOR_VERSIONS = {
    "go_router": (15, 0, 0),
    "dio": (5, 8, 0),
    "flutter_bloc": (9, 1, 0),
    "flutter_map": (8, 2, 0),
    "geolocator": (14, 0, 0),
    "health": (12, 1, 0),
    "flutter_foreground_task": (9, 0, 0),
}

REQUIRED_ASSETS = (
    "assets/db/client_sqlite_schema.sql",
    "assets/errors/error_catalog.json",
)

FORBIDDEN_ERROR_IGNORES = frozenset({
    "deprecated_member_use",
    "deprecated_member_use_from_same_package",
    "missing_required_param",
    "missing_return",
    "unused_local_variable",
    "unused_field",
    "dead_code",
    "invalid_use_of_protected_member",
    "todo",
})

REQUIRED_LINTER_RULES = frozenset({
    "use_primary_constructors",
    "use_declaring_parameters",
    "avoid_dynamic_calls",
    "unawaited_futures",
})

FORBIDDEN_PLATFORM_DIRS = ("macos", "windows", "linux", "web")

CANONICAL_DELEGATED_PATHS = {
    "mascot_vector_painter.dart": "features/home_mascot/presentation/widgets/mascot_vector_painter.dart",
    "map_activity_screen.dart": "features/map_activity/presentation/screens/map_activity_screen.dart",
    "outbox_dispatcher.dart": "core/database/outbox_dispatcher.dart",
}

BANNED_SUPPRESSIONS = frozenset({
    "deprecated_member_use",
    "avoid_dynamic_calls",
    "avoid-dynamic",
    "avoid-non-null-assertion",
    "import_lint",
    "unawaited_futures",
    "no-empty-block",
})

PRESENTATION_FORBIDDEN_IMPORTS = (
    "package:dio/",
    "package:sqflite/",
    "package:sqlite3/",
    "package:geolocator/",
    "package:health/",
    "package:pedometer/",
    "package:firebase_messaging/",
    "package:flutter_secure_storage/",
    "package:ecotrack_mobile/core/network/",
    "package:ecotrack_mobile/core/database/",
    "package:ecotrack_mobile/core/sensors/",
)

DOMAIN_FORBIDDEN_IMPORTS = (
    "package:flutter/",
    "package:dio/",
    "package:sqflite/",
    "package:sqlite3/",
    "package:ecotrack_mobile/core/network/",
    "package:ecotrack_mobile/core/database/",
)

LEGACY_OUTBOX_LITERALS = frozenset({
    "PENDING",
    "IN_FLIGHT",
    "CONFIRMED",
    "FAILED",
    "RETRY",
    "mutation_type",
})

STUB_MARKERS = (
    "sample-google-oauth-code",
    "mock-device-token",
)


def parse_min_semver(constraint: object) -> tuple[int, int, int] | None:
    if not isinstance(constraint, str):
        return None
    text = constraint.strip()
    if not text or text == "any":
        return None
    versions: list[tuple[int, int, int]] = []
    for token in text.replace(",", " ").split():
        if token.startswith("<"):
            continue
        match = re.match(r"^(?:>=|\^)?(\d+)\.(\d+)(?:\.(\d+))?", token)
        if match:
            major = int(match.group(1))
            minor = int(match.group(2))
            patch = int(match.group(3) or "0")
            versions.append((major, minor, patch))
    return max(versions) if versions else None


def load_yaml_file(path: Path) -> tuple[object | None, str | None]:
    if not path.is_file():
        return None, f"Missing file: {path}"
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        return data, None
    except Exception as exc:
        return None, f"YAML parse error in {path}: {exc}"


def strip_dart(source: str, strip_strings: bool = False) -> str:
    out: list[str] = []
    i = 0
    n = len(source)
    interp_stack: list[tuple[str, bool, int]] = []
    brace_depth = 0

    while i < n:
        ch = source[i]
        if interp_stack and ch == "{":
            brace_depth += 1
            out.append(ch)
            i += 1
            continue
        if interp_stack and ch == "}" and brace_depth == interp_stack[-1][2]:
            quote, is_triple, _ = interp_stack.pop()
            out.append(ch)
            i += 1
            i = _consume_string_body(
                source, i, quote, False, is_triple, strip_strings, out, interp_stack, brace_depth
            )
            continue
        if interp_stack and ch == "}" and brace_depth > 0:
            brace_depth -= 1
            out.append(ch)
            i += 1
            continue

        if source.startswith("//", i):
            while i < n and source[i] != "\n":
                i += 1
            continue

        if source.startswith("/*", i):
            depth = 1
            i += 2
            while i < n and depth > 0:
                if source.startswith("/*", i):
                    depth += 1
                    i += 2
                elif source.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    if source[i] == "\n":
                        out.append("\n")
                    i += 1
            continue

        is_raw = False
        str_start = i
        if ch == "r" and i + 1 < n and source[i + 1] in ("'", '"'):
            prev = source[i - 1] if i > 0 else " "
            if not (prev.isalnum() or prev == "_"):
                is_raw = True
                str_start = i + 1

        if source[str_start] in ("'", '"'):
            quote = source[str_start]
            is_triple = source.startswith(quote * 3, str_start)
            delim_len = 3 if is_triple else 1
            out.append(source[i : str_start + delim_len])
            i = str_start + delim_len
            i = _consume_string_body(
                source, i, quote, is_raw, is_triple, strip_strings, out, interp_stack, brace_depth
            )
            continue

        out.append(ch)
        i += 1

    return "".join(out)


def _consume_string_body(
    source: str,
    i: int,
    quote: str,
    is_raw: bool,
    is_triple: bool,
    strip_strings: bool,
    out: list[str],
    interp_stack: list[tuple[str, bool, int]],
    brace_depth: int,
) -> int:
    n = len(source)
    delim = quote * 3 if is_triple else quote
    while i < n:
        if source.startswith(delim, i):
            out.append(delim)
            return i + len(delim)
        ch = source[i]
        if not is_triple and ch == "\n":
            out.append("\n")
            return i + 1
        if not is_raw and ch == "\\" and i + 1 < n:
            nxt = source[i + 1]
            if strip_strings:
                out.append("\n" if nxt == "\n" else "  ")
            else:
                out.append(source[i : i + 2])
            i += 2
            continue
        if not is_raw and source.startswith("${", i):
            out.append("${")
            interp_stack.append((quote, is_triple, brace_depth))
            return i + 2
        if strip_strings:
            out.append("\n" if ch == "\n" else " ")
        else:
            out.append(ch)
        i += 1
    return i


def extract_dart_strings(comment_free_source: str) -> list[tuple[int, str]]:
    results: list[tuple[int, str]] = []
    i = 0
    n = len(comment_free_source)
    while i < n:
        ch = comment_free_source[i]
        is_raw = False
        str_start = i
        if ch == "r" and i + 1 < n and comment_free_source[i + 1] in ("'", '"'):
            prev = comment_free_source[i - 1] if i > 0 else " "
            if not (prev.isalnum() or prev == "_"):
                is_raw = True
                str_start = i + 1

        if comment_free_source[str_start] in ("'", '"'):
            quote = comment_free_source[str_start]
            is_triple = comment_free_source.startswith(quote * 3, str_start)
            delim = quote * 3 if is_triple else quote
            line_no = comment_free_source[:i].count("\n") + 1
            j = str_start + len(delim)
            buf: list[str] = []
            while j < n:
                if comment_free_source.startswith(delim, j):
                    j += len(delim)
                    break
                if not is_triple and comment_free_source[j] == "\n":
                    j += 1
                    break
                if not is_raw and comment_free_source[j] == "\\" and j + 1 < n:
                    buf.append(comment_free_source[j : j + 2])
                    j += 2
                    continue
                buf.append(comment_free_source[j])
                j += 1
            results.append((line_no, "".join(buf)))
            i = j
            continue
        i += 1
    return results


def line_number_at(text: str, offset: int) -> int:
    return text[:offset].count("\n") + 1


def resolve_dart_import(raw_import: str, file_rel_to_lib: Path) -> str:
    if raw_import.startswith("package:") or raw_import.startswith("dart:"):
        return raw_import
    base_dir = file_rel_to_lib.parent
    combined = (Path("pkg_root") / base_dir / raw_import).as_posix()
    parts: list[str] = []
    for part in combined.split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            if parts and parts[-1] != "pkg_root":
                parts.pop()
        else:
            parts.append(part)
    if parts and parts[0] == "pkg_root":
        parts = parts[1:]
    return "package:ecotrack_mobile/" + "/".join(parts)


def check_gate_1_screens(root: Path) -> tuple[str, list[str]]:
    errors: list[str] = []
    screens_dir = root / "screens"
    if not screens_dir.is_dir():
        return "FAIL", [f"Missing screens directory: {screens_dir}"]
    for name in REQUIRED_SCREENS:
        target = screens_dir / name
        if not target.is_file():
            errors.append(f"Missing canonical PNG: screens/{name}")
        elif target.stat().st_size <= 0:
            errors.append(f"Empty canonical PNG: screens/{name}")
    return ("PASS" if not errors else "FAIL"), errors


def check_gate_2_pubspec(root: Path) -> tuple[str, list[str]]:
    errors: list[str] = []
    pubspec_path = root / "mobile" / "pubspec.yaml"
    data, load_err = load_yaml_file(pubspec_path)
    if load_err:
        return "FAIL", [load_err]
    if not isinstance(data, dict):
        return "FAIL", ["mobile/pubspec.yaml must be a YAML mapping"]

    env = data.get("environment")
    sdk_spec = env.get("sdk") if isinstance(env, dict) else None
    min_sdk = parse_min_semver(sdk_spec)
    if min_sdk is None or min_sdk < (3, 13, 4):
        errors.append(f"environment.sdk lower bound must be >= 3.13.4 (found: {sdk_spec!r})")

    deps = data.get("dependencies")
    dev_deps = data.get("dev_dependencies")
    deps_map = deps if isinstance(deps, dict) else {}
    dev_map = dev_deps if isinstance(dev_deps, dict) else {}

    for pkg in sorted(FORBIDDEN_PACKAGES):
        if pkg in deps_map or pkg in dev_map:
            errors.append(f"Forbidden package present in mobile/pubspec.yaml: {pkg}")

    for pkg in sorted(REQUIRED_DEV_DEPS):
        if pkg not in dev_map:
            errors.append(f"Missing required dev_dependency: {pkg}")

    for pkg, floor in sorted(RUNTIME_FLOOR_VERSIONS.items()):
        if pkg in deps_map:
            parsed = parse_min_semver(deps_map[pkg])
            if parsed is None or parsed < floor:
                floor_str = ".".join(str(x) for x in floor)
                errors.append(
                    f"Runtime dependency {pkg} version {deps_map[pkg]!r} is below floor >={floor_str}"
                )

    flutter_cfg = data.get("flutter")
    assets = flutter_cfg.get("assets") if isinstance(flutter_cfg, dict) else None
    asset_set = set(assets) if isinstance(assets, list) else set()
    for required_asset in REQUIRED_ASSETS:
        if required_asset not in asset_set:
            errors.append(f"Missing required flutter asset: {required_asset}")

    return ("PASS" if not errors else "FAIL"), errors


def check_gate_3_analysis_options(root: Path) -> tuple[str, list[str]]:
    errors: list[str] = []
    ao_path = root / "mobile" / "analysis_options.yaml"
    data, load_err = load_yaml_file(ao_path)
    if load_err:
        return "FAIL", [load_err]
    if not isinstance(data, dict):
        return "FAIL", ["mobile/analysis_options.yaml must be a YAML mapping"]

    plugins = data.get("plugins")
    plugin_keys: set[str] = set()
    if isinstance(plugins, dict):
        plugin_keys = {str(k) for k in plugins.keys()}
    elif isinstance(plugins, list):
        plugin_keys = {str(x) for x in plugins}
    for required_plugin in ("dart_code_linter", "import_lint"):
        if required_plugin not in plugin_keys:
            errors.append(f"Top-level plugins missing {required_plugin}")

    analyzer = data.get("analyzer")
    if not isinstance(analyzer, dict):
        errors.append("Missing analyzer section")
    else:
        lang = analyzer.get("language")
        if not isinstance(lang, dict):
            errors.append("Missing analyzer.language section")
        else:
            for flag in ("strict-casts", "strict-inference", "strict-raw-types"):
                if lang.get(flag) is not True:
                    errors.append(f"analyzer.language.{flag} must be true")

        err_cfg = analyzer.get("errors")
        if not isinstance(err_cfg, dict):
            errors.append("Missing analyzer.errors section")
        else:
            for code in ("deprecated_member_use", "deprecated_member_use_from_same_package"):
                val = str(err_cfg.get(code, "")).strip().lower()
                if val != "error":
                    errors.append(f"analyzer.errors.{code} must be 'error' (found {val!r})")
            for code in sorted(FORBIDDEN_ERROR_IGNORES):
                val = str(err_cfg.get(code, "")).strip().lower()
                if val == "ignore":
                    errors.append(f"analyzer.errors.{code} must not be 'ignore'")

    linter = data.get("linter")
    rules_node = linter.get("rules") if isinstance(linter, dict) else None
    enabled_rules: set[str] = set()
    if isinstance(rules_node, dict):
        enabled_rules = {str(k) for k, v in rules_node.items() if v is True}
    elif isinstance(rules_node, list):
        enabled_rules = {str(x) for x in rules_node}
    for req_rule in sorted(REQUIRED_LINTER_RULES):
        if req_rule not in enabled_rules:
            errors.append(f"linter.rules missing {req_rule}")

    import_lint = data.get("import_lint")
    il_rules = import_lint.get("rules") if isinstance(import_lint, dict) else None
    if not isinstance(il_rules, dict) or not il_rules:
        errors.append("import_lint.rules must be a non-empty mapping")

    return ("PASS" if not errors else "FAIL"), errors


def check_gate_4_platform_and_paths(root: Path) -> tuple[str, list[str]]:
    errors: list[str] = []
    mobile_dir = root / "mobile"
    for dirname in FORBIDDEN_PLATFORM_DIRS:
        if (mobile_dir / dirname).exists():
            errors.append(f"Forbidden platform runner directory exists: mobile/{dirname}")

    lib_dir = mobile_dir / "lib"
    if lib_dir.is_dir():
        for dart_file in sorted(lib_dir.rglob("*.dart")):
            canonical = CANONICAL_DELEGATED_PATHS.get(dart_file.name)
            if canonical is not None:
                rel_posix = dart_file.relative_to(lib_dir).as_posix()
                if rel_posix != canonical:
                    errors.append(
                        f"Module {dart_file.name} at mobile/lib/{rel_posix} must be at mobile/lib/{canonical}"
                    )

    for gradle_name in ("build.gradle.kts", "build.gradle"):
        gradle_path = mobile_dir / "android" / "app" / gradle_name
        if gradle_path.is_file():
            gradle_text = gradle_path.read_text(encoding="utf-8")
            m = re.search(r'applicationId\s*=?\s*["\']([^"\']+)["\']', gradle_text)
            if m and m.group(1).startswith("com.example."):
                errors.append(f"Android applicationId uses template namespace: {m.group(1)}")

    return ("PASS" if not errors else "FAIL"), errors


def check_gate_5_static_bans_and_imports(root: Path) -> tuple[str, list[str]]:
    mobile_dir = root / "mobile"
    lib_dir = mobile_dir / "lib"
    test_dir = mobile_dir / "test"

    lib_files = sorted(lib_dir.rglob("*.dart")) if lib_dir.is_dir() else []
    test_files = sorted(test_dir.rglob("*.dart")) if test_dir.is_dir() else []

    if not lib_files and not test_files:
        return "SKIP", ["No .dart files found under mobile/lib or mobile/test"]

    errors: list[str] = []

    for dart_file in lib_files + test_files:
        raw = dart_file.read_text(encoding="utf-8")
        rel = dart_file.relative_to(mobile_dir).as_posix()

        for m in re.finditer(r"//\s*ignore(?:_for_file)?\s*:\s*([^\n]+)", raw):
            line_no = line_number_at(raw, m.start())
            body = m.group(1).split("//", 1)[0]
            tokens = [t.strip() for t in body.split(",") if t.strip()]
            for tok in tokens:
                short_tok = tok.split("/")[-1]
                if tok in BANNED_SUPPRESSIONS or short_tok in BANNED_SUPPRESSIONS:
                    errors.append(f"Banned analyzer suppression '{tok}' in {rel}:{line_no}")

        stripped_all = strip_dart(raw, strip_strings=True)
        for m in re.finditer(r"\bdynamic\b", stripped_all):
            line_no = line_number_at(stripped_all, m.start())
            errors.append(f"Forbidden 'dynamic' type in {rel}:{line_no}")

    for dart_file in lib_files:
        raw = dart_file.read_text(encoding="utf-8")
        rel = dart_file.relative_to(mobile_dir).as_posix()
        rel_lib = dart_file.relative_to(lib_dir)
        rel_lib_posix = rel_lib.as_posix()
        comment_free = strip_dart(raw, strip_strings=False)
        stripped_all = strip_dart(raw, strip_strings=True)

        for m in re.finditer(r"\bis!|!=|([A-Za-z0-9_\]\)])!(?!=)", stripped_all):
            if m.group(1) is not None:
                line_no = line_number_at(stripped_all, m.start())
                errors.append(f"Forbidden null-assertion '!' operator in {rel}:{line_no}")

        for m in re.finditer(r"\bshowSnackBar\s*\(", stripped_all):
            line_no = line_number_at(stripped_all, m.start())
            errors.append(f"Forbidden direct showSnackBar( in {rel}:{line_no}")

        for m in re.finditer(r"\bcatch\s*\([^)]*\)\s*\{\s*\}", comment_free):
            line_no = line_number_at(comment_free, m.start())
            errors.append(f"Forbidden empty catch block in {rel}:{line_no}")

        for m in re.finditer(r"\bdeleteDatabase\s*\(", stripped_all):
            line_no = line_number_at(stripped_all, m.start())
            errors.append(f"Forbidden deleteDatabase( in {rel}:{line_no}")

        if rel_lib_posix.startswith("core/theme/") or rel_lib_posix == "app.dart":
            for m in re.finditer(r"\b(?:Brightness\.dark|ThemeData\.dark\s*\()", stripped_all):
                line_no = line_number_at(stripped_all, m.start())
                errors.append(f"Forbidden dark theme API ({m.group(0).strip()}) in {rel}:{line_no}")

        for m in re.finditer(
            r"\bdouble\s+([A-Za-z0-9_]*(?:totalCo2|co2Saved|pointsBalance|costPoints|pricePoints|pointsDelta|lifetimePoints)[A-Za-z0-9_]*)\b",
            stripped_all,
        ):
            line_no = line_number_at(stripped_all, m.start())
            errors.append(f"Forbidden double precision for integer currency/CO2 '{m.group(1)}' in {rel}:{line_no}")

        is_presentation = bool(re.match(r"^features/[^/]+/presentation/", rel_lib_posix))
        is_domain = bool(re.match(r"^features/[^/]+/domain/", rel_lib_posix))
        feat_match = re.match(r"^features/([^/]+)/", rel_lib_posix)
        own_feature = feat_match.group(1) if feat_match else None

        for m in re.finditer(r"^\s*import\s+['\"]([^'\"]+)['\"]", comment_free, re.MULTILINE):
            line_no = line_number_at(comment_free, m.start())
            resolved = resolve_dart_import(m.group(1), rel_lib)

            if is_presentation:
                if any(resolved.startswith(p) for p in PRESENTATION_FORBIDDEN_IMPORTS) or re.match(
                    r"^package:ecotrack_mobile/features/[^/]+/data/", resolved
                ):
                    errors.append(f"Presentation layer violation '{resolved}' in {rel}:{line_no}")

            if is_domain:
                if any(resolved.startswith(p) for p in DOMAIN_FORBIDDEN_IMPORTS) or re.match(
                    r"^package:ecotrack_mobile/features/[^/]+/(?:data|presentation)/", resolved
                ):
                    errors.append(f"Domain layer violation '{resolved}' in {rel}:{line_no}")

            if own_feature is not None:
                target_feat = re.match(r"^package:ecotrack_mobile/features/([^/]+)/(.+)$", resolved)
                if target_feat and target_feat.group(1) != own_feature:
                    if not target_feat.group(2).startswith("domain/"):
                        errors.append(
                            f"Forbidden cross-feature non-domain import '{resolved}' in {rel}:{line_no}"
                        )

    return ("PASS" if not errors else "FAIL"), errors


def _compile_openapi_matchers(openapi_doc: object) -> list[re.Pattern[str]]:
    if not isinstance(openapi_doc, dict):
        return []
    paths = openapi_doc.get("paths")
    if not isinstance(paths, dict):
        return []
    matchers: list[re.Pattern[str]] = []
    for raw_path in paths.keys():
        parts = str(raw_path).split("/")
        regex_parts: list[str] = []
        for part in parts:
            if part.startswith("{") and part.endswith("}"):
                regex_parts.append(r"[^/'\"]+")
            elif "{" in part and "}" in part:
                sub = re.sub(r"\{[^}]+\}", r"[^/'\"]+", part)
                regex_parts.append(sub)
            else:
                regex_parts.append(re.escape(part))
        matchers.append(re.compile("^" + "/".join(regex_parts) + "$"))
    return matchers


def check_gate_6_contracts_and_stubs(root: Path) -> tuple[str, list[str]]:
    mobile_dir = root / "mobile"
    lib_dir = mobile_dir / "lib"
    lib_files = sorted(lib_dir.rglob("*.dart")) if lib_dir.is_dir() else []

    if not lib_files:
        return "SKIP", ["No .dart files found under mobile/lib"]

    errors: list[str] = []

    openapi_doc, oa_err = load_yaml_file(root / "contracts" / "openapi.yaml")
    if oa_err:
        return "FAIL", [oa_err]
    route_matchers = _compile_openapi_matchers(openapi_doc)
    if len(route_matchers) != 38:
        errors.append(f"Expected 38 OpenAPI paths, found {len(route_matchers)}")

    ec_path = root / "contracts" / "error_catalog.json"
    if not ec_path.is_file():
        return "FAIL", [f"Missing {ec_path}"]
    ec_doc = json.loads(ec_path.read_text(encoding="utf-8"))
    catalog_codes = set(ec_doc.get("errors", {}).keys())
    allowed_actions = set(ec_doc.get("allowed_client_actions", []))

    network_dir = lib_dir / "core" / "network"
    network_texts: list[str] = []
    env_read_texts: list[str] = []
    error_parse_texts: list[str] = []

    for dart_file in lib_files:
        raw = dart_file.read_text(encoding="utf-8")
        rel = dart_file.relative_to(mobile_dir).as_posix()
        rel_lib_posix = dart_file.relative_to(lib_dir).as_posix()

        if dart_file.name == "register_screen.dart":
            errors.append(f"Forbidden stub screen file exists: {rel}")

        comment_free = strip_dart(raw, strip_strings=False)
        strings = extract_dart_strings(comment_free)

        if rel_lib_posix.startswith("core/network/"):
            network_texts.append(comment_free)
            env_read_texts.append(comment_free)
            error_parse_texts.append(comment_free)
        elif rel_lib_posix.startswith("core/di/") or rel_lib_posix == "main.dart":
            env_read_texts.append(comment_free)
        elif rel_lib_posix.startswith("core/error/"):
            error_parse_texts.append(comment_free)

        for line_no, literal in strings:
            for route_match in re.finditer(r"/(?:api/)?v1/[A-Za-z0-9_/${}:.-]+", literal):
                raw_route = route_match.group(0).split("?", 1)[0]
                if raw_route.startswith("/v1/"):
                    errors.append(f"Missing /api prefix on API route '{raw_route}' in {rel}:{line_no}")
                elif raw_route.startswith("/api/v1/"):
                    normalized = re.sub(r"\$\{[^}]+\}|\$[A-Za-z_][A-Za-z0-9_]*", "PARAM", raw_route)
                    if not any(rx.match(normalized) for rx in route_matchers):
                        errors.append(
                            f"Unknown API route '{raw_route}' (normalized '{normalized}') not in OpenAPI in {rel}:{line_no}"
                        )

            if re.search(r"\bCREATE\s+TABLE\b", literal, re.IGNORECASE):
                errors.append(f"Forbidden hardcoded CREATE TABLE DDL in {rel}:{line_no}")

            for marker in STUB_MARKERS:
                if marker in literal:
                    errors.append(f"Forbidden stub marker '{marker}' in {rel}:{line_no}")

            if rel_lib_posix == "core/database/outbox_dispatcher.dart":
                if literal in LEGACY_OUTBOX_LITERALS:
                    errors.append(f"Forbidden legacy outbox literal '{literal}' in {rel}:{line_no}")

        for m in re.finditer(r"AppError\.fromCode\(\s*['\"]([A-Z0-9_]+)['\"]", comment_free):
            code = m.group(1)
            if code not in catalog_codes:
                line_no = line_number_at(comment_free, m.start())
                errors.append(f"Unknown AppError code '{code}' in {rel}:{line_no}")

        for m in re.finditer(r"clientAction\s*:\s*['\"]([a-z0-9_]+)['\"]", comment_free):
            action = m.group(1)
            if action not in allowed_actions:
                line_no = line_number_at(comment_free, m.start())
                errors.append(f"Unknown clientAction '{action}' in {rel}:{line_no}")

    if network_dir.is_dir() and network_texts:
        combined_env = "\n".join(env_read_texts)
        if "API_BASE_URL" not in combined_env or "fromEnvironment" not in combined_env:
            errors.append("Missing String.fromEnvironment('API_BASE_URL') configuration for core/network")

        combined_err = "\n".join(error_parse_texts)
        if "'error_code'" not in combined_err and '"error_code"' not in combined_err:
            errors.append("Missing 'error_code' envelope parsing in core/network or core/error")

        combined_net = "\n".join(network_texts)
        for method in ("get", "post", "put", "patch", "delete"):
            has_method = bool(
                re.search(rf"\b{method}\s*(?:<[^>]+>)?\s*\(", combined_net)
            )
            if not has_method:
                errors.append(f"Missing HTTP '{method.upper()}' support across core/network/")

    return ("PASS" if not errors else "FAIL"), errors


def check_gate_7_android_manifest(root: Path) -> tuple[str, list[str]]:
    manifest_path = root / "mobile" / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest_path.is_file():
        return "SKIP", ["No mobile/android/app/src/main/AndroidManifest.xml present"]

    raw_xml = manifest_path.read_text(encoding="utf-8")
    clean_xml = re.sub(r"<!--.*?-->", "", raw_xml, flags=re.DOTALL)
    errors: list[str] = []

    if "ACCESS_BACKGROUND_LOCATION" in clean_xml:
        errors.append("Forbidden ACCESS_BACKGROUND_LOCATION permission in AndroidManifest.xml")

    required_tokens = (
        "android.permission.health.READ_STEPS",
        "android.permission.ACTIVITY_RECOGNITION",
        "android.permission.FOREGROUND_SERVICE_LOCATION",
    )
    for token in required_tokens:
        if token not in clean_xml:
            errors.append(f"Missing required Android permission: {token}")

    if not re.search(r'android:scheme\s*=\s*["\']ecotrack["\']', clean_xml):
        errors.append("Missing OAuth deep-link android:scheme=\"ecotrack\" in AndroidManifest.xml")

    return ("PASS" if not errors else "FAIL"), errors


def check_gate_8_tests(root: Path) -> tuple[str, list[str]]:
    mobile_dir = root / "mobile"
    test_dir = mobile_dir / "test"
    test_files = sorted(test_dir.rglob("*.dart")) if test_dir.is_dir() else []

    lib_dir = mobile_dir / "lib"
    if not test_files and not (lib_dir / "core/database/outbox_dispatcher.dart").is_file():
        return "SKIP", ["No .dart files found under mobile/test"]

    errors: list[str] = []

    pbt_dir = test_dir / "pbt"
    if pbt_dir.is_dir():
        for pbt_file in sorted(pbt_dir.glob("*_pbt_test.dart")):
            raw = pbt_file.read_text(encoding="utf-8")
            clean = strip_dart(raw, strip_strings=False)
            rel = pbt_file.relative_to(mobile_dir).as_posix()
            if "package:glados/glados.dart" not in clean:
                errors.append(f"PBT file missing 'package:glados/glados.dart' import: {rel}")
            if "Glados" not in strip_dart(raw, strip_strings=True):
                errors.append(f"PBT file missing Glados property execution: {rel}")
            if "package:ecotrack_mobile/" not in clean:
                errors.append(f"PBT file does not import production code under package:ecotrack_mobile/: {rel}")

    all_test_clean: list[str] = []
    widget_test_clean: list[str] = []

    for tf in test_files:
        raw = tf.read_text(encoding="utf-8")
        clean = strip_dart(raw, strip_strings=False)
        rel = tf.relative_to(mobile_dir).as_posix()
        all_test_clean.append(clean)
        if tf.is_relative_to(test_dir / "widgets"):
            widget_test_clean.append(clean)

        if re.search(r"import\s+['\"]package:(?:mockito|mocktail)/", clean):
            errors.append(f"Forbidden mocking framework import in test: {rel}")

    if (lib_dir / "core" / "database" / "outbox_dispatcher.dart").is_file():
        if not (pbt_dir / "outbox_fsm_pbt_test.dart").is_file():
            errors.append("Missing required PBT suite: mobile/test/pbt/outbox_fsm_pbt_test.dart")
        if not any("outbox_dispatcher.dart" in txt for txt in all_test_clean):
            errors.append("outbox_dispatcher.dart is not imported by any test in mobile/test/")

    if (lib_dir / "core" / "router" / "app_router.dart").is_file():
        if not any("app_router.dart" in txt for txt in widget_test_clean):
            errors.append("app_router.dart is not imported by any widget test in mobile/test/widgets/")

    return ("PASS" if not errors else "FAIL"), errors


def main() -> int:
    parser = argparse.ArgumentParser(description="EcoTrack mobile CI verification gates")
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="Repository root directory",
    )
    args = parser.parse_args()
    root = args.root.resolve()

    gates = (
        ("1. Visual Reference Canon (screens/)", check_gate_1_screens),
        ("2. pubspec.yaml Integrity & Bans", check_gate_2_pubspec),
        ("3. analysis_options.yaml Guard", check_gate_3_analysis_options),
        ("4. Platform Bloat & Canonical Paths", check_gate_4_platform_and_paths),
        ("5. Static Bans & Import Boundaries", check_gate_5_static_bans_and_imports),
        ("6. Contracts, Error Catalog & Anti-Stub", check_gate_6_contracts_and_stubs),
        ("7. Android Manifest & 152-FZ Gate", check_gate_7_android_manifest),
        ("8. Anti-Tautology Test Quality Gate", check_gate_8_tests),
    )

    print("=" * 88)
    print(f"EcoTrack Mobile CI Verification Gates (root: {root})")
    print("=" * 88)

    has_failure = False
    for title, fn in gates:
        status, details = fn(root)
        print(f"[{status}] {title}")
        for item in details:
            prefix = "  -" if status == "SKIP" else "  *"
            print(f"{prefix} {item}")
        if status == "FAIL":
            has_failure = True

    print("=" * 88)
    if has_failure:
        print("[FAILED] One or more mobile CI verification gates failed.")
        return 1
    print("[SUCCESS] All active mobile CI verification gates passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
