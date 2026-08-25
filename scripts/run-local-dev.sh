#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap-lib.sh"

BOOTSTRAP_DOWNLOADED_NODE_BIN="$(bootstrap_node_bin)"
BOOTSTRAP_DOWNLOADED_NPM_BIN="$(bootstrap_npm_bin)"
BOOTSTRAP_DOWNLOADED_JAVA_HOME="$(bootstrap_java_home)"
BOOTSTRAP_DOWNLOADED_JAVA_BIN="$(bootstrap_java_bin)"
BOOTSTRAP_DOWNLOADED_TECTONIC_BIN="$(bootstrap_tectonic_bin)"
BOOTSTRAP_DOWNLOADED_TECTONIC_LIB_DIR="$(bootstrap_tectonic_home)/lib"
BOOTSTRAP_DOWNLOADED_CASSANDRA_HOME="$(bootstrap_cassandra_home)"
BOOTSTRAP_DOWNLOADED_CASSANDRA_BIN="$(bootstrap_cassandra_bin)"
BOOTSTRAP_DOWNLOADED_CQLSH_BIN="$(bootstrap_cqlsh_bin)"
BOOTSTRAP_DOWNLOADED_REDIS_HOME="$(bootstrap_redis_home)"
BOOTSTRAP_DOWNLOADED_REDIS_SERVER_BIN="$(bootstrap_redis_server_bin)"
BOOTSTRAP_DOWNLOADED_REDIS_CLI_BIN="$(bootstrap_redis_cli_bin)"
BOOTSTRAP_CASSANDRA_RUNTIME_ROOT="$BOOTSTRAP_ROOT/cassandra-runtime/$BOOTSTRAP_CASSANDRA_VERSION"
BOOTSTRAP_CASSANDRA_CONF_DIR="$BOOTSTRAP_CASSANDRA_RUNTIME_ROOT/conf"
BOOTSTRAP_CASSANDRA_DATA_DIR="$BOOTSTRAP_CASSANDRA_RUNTIME_ROOT/data"
BOOTSTRAP_CASSANDRA_COMMITLOG_DIR="$BOOTSTRAP_CASSANDRA_RUNTIME_ROOT/commitlog"
BOOTSTRAP_CASSANDRA_SAVED_CACHES_DIR="$BOOTSTRAP_CASSANDRA_RUNTIME_ROOT/saved_caches"
BOOTSTRAP_CASSANDRA_HINTS_DIR="$BOOTSTRAP_CASSANDRA_RUNTIME_ROOT/hints"
BOOTSTRAP_CASSANDRA_CDC_DIR="$BOOTSTRAP_CASSANDRA_RUNTIME_ROOT/cdc_raw"
BOOTSTRAP_NODE_BIN=""
BOOTSTRAP_NPM_BIN=""
BOOTSTRAP_JAVA_BIN=""
BOOTSTRAP_JAVA_HOME=""
BOOTSTRAP_TECTONIC_BIN=""
BOOTSTRAP_TECTONIC_SOURCE=""
BOOTSTRAP_TECTONIC_LIBRARY_PATH=""
BOOTSTRAP_OLLAMA_BIN=""
BOOTSTRAP_CASSANDRA_BIN=""
BOOTSTRAP_CQLSH_BIN=""
BOOTSTRAP_REDIS_SERVER_BIN=""
BOOTSTRAP_REDIS_CLI_BIN=""
BOOTSTRAP_OLLAMA_PID=""
BOOTSTRAP_OLLAMA_STARTED=0
BOOTSTRAP_CASSANDRA_PID=""
BOOTSTRAP_CASSANDRA_STARTED=0
BOOTSTRAP_REDIS_PID=""
BOOTSTRAP_REDIS_STARTED=0
BOOTSTRAP_CLEANUP_DONE=0

bootstrap_parse_local_dev_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --llama3-only)
        BOOTSTRAP_OLLAMA_MODELS="llama3:8b"
        ;;
      -h|--help)
        printf '%s\n' "Usage: $0 [--llama3-only]"
        printf '%s\n' "  --llama3-only  Download and verify only the llama3:8b Ollama model."
        exit 0
        ;;
      *)
        bootstrap_fail "Unknown option: $1"
        ;;
    esac
    shift
  done
}

bootstrap_ensure_core_download_tooling() {
  bootstrap_install_curl_if_missing
}

bootstrap_java_bin_dir() {
  if [ -n "$BOOTSTRAP_JAVA_BIN" ]; then
    dirname "$BOOTSTRAP_JAVA_BIN"
  fi
}

bootstrap_install_node() {
  if [ -x "$BOOTSTRAP_DOWNLOADED_NODE_BIN" ]; then
    bootstrap_log "Repo-local Node.js already installed at $BOOTSTRAP_DOWNLOADED_NODE_BIN"
    return
  fi
  bootstrap_log "Installing Node.js v$BOOTSTRAP_NODE_VERSION for $BOOTSTRAP_PLATFORM"
  mkdir -p "$BOOTSTRAP_CACHE_DIR" "$BOOTSTRAP_TOOLS_DIR/node/$BOOTSTRAP_PLATFORM"
  local archive_name archive_path extract_root
  archive_name="$(bootstrap_node_archive_name)"
  archive_path="$BOOTSTRAP_CACHE_DIR/$archive_name"
  extract_root="$BOOTSTRAP_TOOLS_DIR/node/$BOOTSTRAP_PLATFORM"
  if [ ! -f "$archive_path" ]; then
    bootstrap_download "$(bootstrap_node_archive_url)" "$archive_path"
  fi
  bootstrap_extract_archive "$archive_path" "$extract_root"
  if [ ! -x "$BOOTSTRAP_DOWNLOADED_NODE_BIN" ]; then
    bootstrap_fail "Node.js install completed but $BOOTSTRAP_DOWNLOADED_NODE_BIN was not found."
  fi
  bootstrap_log "Installed Node.js at $BOOTSTRAP_DOWNLOADED_NODE_BIN"
}

bootstrap_select_node_runtime() {
  local existing_node existing_npm
  existing_node="$(bootstrap_existing_node_bin || true)"
  existing_npm="$(bootstrap_existing_npm_bin || true)"
  if [ -n "$existing_node" ] && [ -n "$existing_npm" ]; then
    BOOTSTRAP_NODE_BIN="$existing_node"
    BOOTSTRAP_NPM_BIN="$existing_npm"
    bootstrap_log "Using existing Node.js at $BOOTSTRAP_NODE_BIN"
    return
  fi
  bootstrap_install_node
  BOOTSTRAP_NODE_BIN="$BOOTSTRAP_DOWNLOADED_NODE_BIN"
  BOOTSTRAP_NPM_BIN="$BOOTSTRAP_DOWNLOADED_NPM_BIN"
}

bootstrap_install_java() {
  if [ -x "$BOOTSTRAP_DOWNLOADED_JAVA_BIN" ]; then
    bootstrap_log "Repo-local Java already installed at $BOOTSTRAP_DOWNLOADED_JAVA_BIN"
    return
  fi
  bootstrap_log "Installing Java $BOOTSTRAP_JAVA_VERSION for Cassandra"
  mkdir -p "$BOOTSTRAP_CACHE_DIR" "$BOOTSTRAP_TOOLS_DIR/java/$BOOTSTRAP_PLATFORM"
  local archive_path tmp_extract top_dir
  archive_path="$BOOTSTRAP_CACHE_DIR/temurin-jdk-${BOOTSTRAP_JAVA_VERSION}-${BOOTSTRAP_PLATFORM}.tar.gz"
  if [ ! -f "$archive_path" ]; then
    bootstrap_download "$(bootstrap_java_archive_url)" "$archive_path"
  fi
  tmp_extract="$(mktemp -d)"
  bootstrap_extract_archive "$archive_path" "$tmp_extract"
  top_dir="$(find "$tmp_extract" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [ -z "$top_dir" ]; then
    rm -rf "$tmp_extract"
    bootstrap_fail "Java archive did not extract into a directory."
  fi
  rm -rf "$BOOTSTRAP_DOWNLOADED_JAVA_HOME"
  mkdir -p "$(dirname "$BOOTSTRAP_DOWNLOADED_JAVA_HOME")"
  mv "$top_dir" "$BOOTSTRAP_DOWNLOADED_JAVA_HOME"
  rm -rf "$tmp_extract"
  # macOS JDK archives place java under Contents/Home. Resolve the executable
  # again after extraction instead of retaining the pre-extraction fallback.
  BOOTSTRAP_DOWNLOADED_JAVA_BIN="$(bootstrap_java_bin)"
  if [ ! -x "$BOOTSTRAP_DOWNLOADED_JAVA_BIN" ]; then
    bootstrap_fail "Java install completed but $BOOTSTRAP_DOWNLOADED_JAVA_BIN was not found."
  fi
  bootstrap_log "Installed Java at $BOOTSTRAP_DOWNLOADED_JAVA_BIN"
}

bootstrap_select_java_runtime() {
  local existing_java
  existing_java="$(bootstrap_existing_java_bin || true)"
  if [ -n "$existing_java" ]; then
    BOOTSTRAP_JAVA_BIN="$existing_java"
    BOOTSTRAP_JAVA_HOME=""
    bootstrap_log "Using existing Java at $BOOTSTRAP_JAVA_BIN"
    return
  fi
  bootstrap_install_java
  BOOTSTRAP_JAVA_BIN="$BOOTSTRAP_DOWNLOADED_JAVA_BIN"
  BOOTSTRAP_JAVA_HOME="$(cd "$(dirname "$BOOTSTRAP_JAVA_BIN")/.." && pwd)"
}

bootstrap_install_npm_dependencies() {
  if [ ! -d "$BOOTSTRAP_REPO_ROOT/node_modules" ] || \
    [ "$BOOTSTRAP_REPO_ROOT/package.json" -nt "$BOOTSTRAP_REPO_ROOT/node_modules" ] || \
    [ "$BOOTSTRAP_REPO_ROOT/package-lock.json" -nt "$BOOTSTRAP_REPO_ROOT/node_modules" ]; then
    bootstrap_log "Installing npm dependencies"
    PATH="$(dirname "$BOOTSTRAP_NODE_BIN"):$PATH" \
      "$BOOTSTRAP_NPM_BIN" install --no-fund --no-audit
    bootstrap_log "npm dependencies are ready"
    return
  fi
  bootstrap_log "npm dependencies already look current, moving on"
}

bootstrap_package_current_platform_tectonic_cli() {
  local package_force
  package_force="${BOOTSTRAP_TECTONIC_PACKAGE_FORCE:-0}"
  bootstrap_log "Prebuilt tectonic-cli asset is unavailable, falling back to a local $BOOTSTRAP_PLATFORM build"
  PACKAGE_PLATFORMS="$BOOTSTRAP_PLATFORM" \
    PACKAGE_FORCE="$package_force" \
    bash "$SCRIPT_DIR/package-tectonic-cli.sh"
}

bootstrap_install_tectonic_cli() {
  if [ -x "$BOOTSTRAP_DOWNLOADED_TECTONIC_BIN" ]; then
    bootstrap_log "Repo-local tectonic-cli already installed at $BOOTSTRAP_DOWNLOADED_TECTONIC_BIN"
    return
  fi
  bootstrap_log "Installing tectonic-cli v$BOOTSTRAP_TECTONIC_CLI_VERSION for $BOOTSTRAP_PLATFORM"
  mkdir -p "$BOOTSTRAP_CACHE_DIR" "$BOOTSTRAP_TOOLS_DIR/tectonic-cli/$BOOTSTRAP_PLATFORM"
  local archive_name archive_path dist_asset_path
  archive_name="$(bootstrap_tectonic_asset_name)"
  archive_path="$BOOTSTRAP_CACHE_DIR/$archive_name"
  dist_asset_path="$BOOTSTRAP_REPO_ROOT/dist/$archive_name"
  if [ ! -f "$archive_path" ]; then
    if ! bootstrap_download "$(bootstrap_tectonic_asset_url)" "$archive_path"; then
      rm -f "$archive_path"
      bootstrap_package_current_platform_tectonic_cli
      if [ ! -f "$dist_asset_path" ]; then
        bootstrap_fail "tectonic-cli fallback build did not produce $dist_asset_path."
      fi
      cp "$dist_asset_path" "$archive_path"
    fi
  fi
  rm -rf "$(bootstrap_tectonic_home)"
  mkdir -p "$(bootstrap_tectonic_home)"
  bootstrap_extract_archive "$archive_path" "$(bootstrap_tectonic_home)"
  chmod +x "$BOOTSTRAP_DOWNLOADED_TECTONIC_BIN" 2>/dev/null || true
  if [ ! -x "$BOOTSTRAP_DOWNLOADED_TECTONIC_BIN" ]; then
    bootstrap_fail "tectonic-cli asset did not contain an executable at $BOOTSTRAP_DOWNLOADED_TECTONIC_BIN."
  fi
  bootstrap_log "Installed tectonic-cli at $BOOTSTRAP_DOWNLOADED_TECTONIC_BIN"
}

bootstrap_select_tectonic_cli() {
  local explicit_bin path_bin
  explicit_bin="$(bootstrap_resolve_command "${TECTONIC_BIN:-}" || true)"
  if [ -n "$explicit_bin" ]; then
    BOOTSTRAP_TECTONIC_BIN="$explicit_bin"
    BOOTSTRAP_TECTONIC_SOURCE="explicit"
    BOOTSTRAP_TECTONIC_LIBRARY_PATH=""
    bootstrap_log "Using explicitly configured tectonic-cli at $BOOTSTRAP_TECTONIC_BIN"
    return
  fi
  if [ -x "$BOOTSTRAP_DOWNLOADED_TECTONIC_BIN" ]; then
    BOOTSTRAP_TECTONIC_BIN="$BOOTSTRAP_DOWNLOADED_TECTONIC_BIN"
    BOOTSTRAP_TECTONIC_SOURCE="repo-local"
    if [ -d "$BOOTSTRAP_DOWNLOADED_TECTONIC_LIB_DIR" ]; then
      BOOTSTRAP_TECTONIC_LIBRARY_PATH="$BOOTSTRAP_DOWNLOADED_TECTONIC_LIB_DIR"
    fi
    bootstrap_log "Using repo-local tectonic-cli at $BOOTSTRAP_TECTONIC_BIN"
    return
  fi
  path_bin="$(bootstrap_resolve_command tectonic-cli || true)"
  if [ -n "$path_bin" ]; then
    BOOTSTRAP_TECTONIC_BIN="$path_bin"
    BOOTSTRAP_TECTONIC_SOURCE="path"
    BOOTSTRAP_TECTONIC_LIBRARY_PATH=""
    bootstrap_log "Using existing PATH tectonic-cli at $BOOTSTRAP_TECTONIC_BIN"
    return
  fi
  bootstrap_install_tectonic_cli
  BOOTSTRAP_TECTONIC_BIN="$BOOTSTRAP_DOWNLOADED_TECTONIC_BIN"
  BOOTSTRAP_TECTONIC_SOURCE="repo-local"
  if [ -d "$BOOTSTRAP_DOWNLOADED_TECTONIC_LIB_DIR" ]; then
    BOOTSTRAP_TECTONIC_LIBRARY_PATH="$BOOTSTRAP_DOWNLOADED_TECTONIC_LIB_DIR"
  fi
}

bootstrap_install_ollama_if_missing() {
  BOOTSTRAP_OLLAMA_BIN="$(bootstrap_existing_ollama_bin || true)"
  if [ -n "$BOOTSTRAP_OLLAMA_BIN" ]; then
    bootstrap_log "Using existing Ollama at $BOOTSTRAP_OLLAMA_BIN"
    return
  fi
  bootstrap_log "Installing Ollama v$BOOTSTRAP_OLLAMA_VERSION"
  bootstrap_log "Official install docs: $(bootstrap_ollama_install_hint)"
  bootstrap_install_curl_if_missing
  bootstrap_require_commands sh
  OLLAMA_VERSION="$BOOTSTRAP_OLLAMA_VERSION" OLLAMA_NO_START=1 \
    sh -c "$(curl -fsSL https://ollama.com/install.sh)"
  BOOTSTRAP_OLLAMA_BIN="$(bootstrap_existing_ollama_bin || true)"
  if [ -z "$BOOTSTRAP_OLLAMA_BIN" ]; then
    bootstrap_fail "Ollama install finished, but the ollama command is still unavailable."
  fi
  bootstrap_log "Installed Ollama at $BOOTSTRAP_OLLAMA_BIN"
}

bootstrap_start_ollama_for_session() {
  if bootstrap_wait_for_http "$BOOTSTRAP_OLLAMA_BASE_URL/api/tags" 2; then
    bootstrap_log "Ollama is already responding at $BOOTSTRAP_OLLAMA_BASE_URL, moving on"
    return
  fi
  mkdir -p "$BOOTSTRAP_RUN_DIR"
  bootstrap_log "Starting Ollama for this session"
  OLLAMA_HOST="$BOOTSTRAP_OLLAMA_HOST" "$BOOTSTRAP_OLLAMA_BIN" serve >"$BOOTSTRAP_RUN_DIR/ollama.log" 2>&1 &
  BOOTSTRAP_OLLAMA_PID="$!"
  BOOTSTRAP_OLLAMA_STARTED=1
  printf '%s\n' "$BOOTSTRAP_OLLAMA_PID" >"$BOOTSTRAP_RUN_DIR/ollama.pid"
  if ! bootstrap_wait_for_http "$BOOTSTRAP_OLLAMA_BASE_URL/api/tags" 60; then
    bootstrap_fail "Ollama did not become ready. See $BOOTSTRAP_RUN_DIR/ollama.log."
  fi
  bootstrap_log "Ollama is ready at $BOOTSTRAP_OLLAMA_BASE_URL"
}

bootstrap_configured_ollama_models() {
  "$BOOTSTRAP_NODE_BIN" --input-type=module -e '
    import { readFileSync } from "node:fs";
    const config = JSON.parse(readFileSync(process.argv[1], "utf8"));
    const configured = (config.models || [])
      .map((entry) => entry && typeof entry.id === "string" ? entry.id.trim() : "")
      .filter(Boolean);
    const requested = String(process.argv[2] || "")
      .split(",")
      .map((model) => model.trim())
      .filter(Boolean);
    const selected = requested.length > 0 ? [...new Set(requested)] : configured;
    const unsupported = selected.filter((model) => !configured.includes(model));
    if (unsupported.length > 0) {
      console.error("Requested Ollama model is not configured: " + unsupported.join(", "));
      process.exit(1);
    }
    for (const model of selected) {
      process.stdout.write(model + "\n");
    }
  ' "$BOOTSTRAP_LLM_MODEL_CONFIG" "$BOOTSTRAP_OLLAMA_MODELS"
}

bootstrap_verify_configured_ollama_models() {
  local missing
  missing="$(
    curl --silent --fail "$BOOTSTRAP_OLLAMA_BASE_URL/api/tags" | \
      "$BOOTSTRAP_NODE_BIN" --input-type=module -e '
        import { readFileSync } from "node:fs";
        const config = JSON.parse(readFileSync(process.argv[1], "utf8"));
        const input = await new Promise((resolve, reject) => {
          let text = "";
          process.stdin.setEncoding("utf8");
          process.stdin.on("data", (chunk) => { text += chunk; });
          process.stdin.on("end", () => resolve(text));
          process.stdin.on("error", reject);
        });
        const response = JSON.parse(input || "{}");
        const installed = new Set();
        for (const entry of response.models || []) {
          for (const value of [entry && entry.name, entry && entry.model]) {
            if (typeof value === "string" && value.trim()) {
              installed.add(value.trim());
            }
          }
        }
        const configured = (config.models || [])
          .map((entry) => entry && typeof entry.id === "string" ? entry.id.trim() : "")
          .filter(Boolean);
        const requested = String(process.argv[2] || "")
          .split(",")
          .map((model) => model.trim())
          .filter(Boolean);
        const selected = requested.length > 0 ? [...new Set(requested)] : configured;
        const unsupported = selected.filter((model) => !configured.includes(model));
        if (unsupported.length > 0) {
          console.error("Requested Ollama model is not configured: " + unsupported.join(", "));
          process.exit(1);
        }
        const missing = selected.filter((model) => !installed.has(model));
        process.stdout.write(missing.join("\n"));
      ' "$BOOTSTRAP_LLM_MODEL_CONFIG" "$BOOTSTRAP_OLLAMA_MODELS"
  )"
  if [ -n "$missing" ]; then
    bootstrap_fail "Ollama did not install every selected model. Missing: $(printf '%s' "$missing" | tr '\n' ' ')"
  fi
  bootstrap_log "Verified every selected Ollama model is installed"
}

bootstrap_ensure_ollama_models() {
  local model
  while IFS= read -r model; do
    [ -n "$model" ] || continue
    bootstrap_log "Ensuring Ollama model $model is available"
    OLLAMA_HOST="$BOOTSTRAP_OLLAMA_HOST" "$BOOTSTRAP_OLLAMA_BIN" pull "$model"
  done < <(bootstrap_configured_ollama_models)

  bootstrap_verify_configured_ollama_models

  if [ -n "${BOOTSTRAP_OLLAMA_MODEL_DIGEST:-}" ]; then
    bootstrap_log "Verifying Ollama model digest $BOOTSTRAP_OLLAMA_MODEL_DIGEST"
    local digest
    digest="$(
      curl --silent --fail "$BOOTSTRAP_OLLAMA_BASE_URL/api/tags" | \
        "$BOOTSTRAP_NODE_BIN" --input-type=module -e '
          const expectedName = process.argv[1];
          const baseName = expectedName.replace(/:latest$/, "");
          const input = await new Promise((resolve, reject) => {
            let text = "";
            process.stdin.setEncoding("utf8");
            process.stdin.on("data", (chunk) => {
              text += chunk;
            });
            process.stdin.on("end", () => resolve(text));
            process.stdin.on("error", reject);
          });
          const data = JSON.parse(input || "{}");
          const models = Array.isArray(data.models) ? data.models : [];
          const match = models.find((entry) => {
            const name = String(entry && entry.name ? entry.name : "");
            const model = String(entry && entry.model ? entry.model : "");
            return (
              name === expectedName ||
              model === expectedName ||
              name === baseName ||
              model === baseName
            );
          });
          if (!match) {
            process.exit(2);
          }
          process.stdout.write(String(match.digest || ""));
        ' "$BOOTSTRAP_OLLAMA_MODEL"
    )"
    if [ -z "$digest" ]; then
      bootstrap_fail "Could not resolve a digest for $BOOTSTRAP_OLLAMA_MODEL from Ollama."
    fi
    case "$digest" in
      "$BOOTSTRAP_OLLAMA_MODEL_DIGEST"*) ;;
      *)
      bootstrap_fail "Ollama model $BOOTSTRAP_OLLAMA_MODEL resolved to digest $digest, expected $BOOTSTRAP_OLLAMA_MODEL_DIGEST."
      ;;
    esac
    bootstrap_log "Ollama model digest matches $BOOTSTRAP_OLLAMA_MODEL_DIGEST"
  fi
}

bootstrap_install_cassandra() {
  if [ -x "$BOOTSTRAP_DOWNLOADED_CASSANDRA_BIN" ] && [ -x "$BOOTSTRAP_DOWNLOADED_CQLSH_BIN" ]; then
    bootstrap_log "Repo-local Cassandra already installed at $BOOTSTRAP_DOWNLOADED_CASSANDRA_HOME"
    return
  fi
  bootstrap_log "Installing Cassandra $BOOTSTRAP_CASSANDRA_VERSION"
  mkdir -p "$BOOTSTRAP_CACHE_DIR" "$BOOTSTRAP_TOOLS_DIR/cassandra/$BOOTSTRAP_PLATFORM"
  local archive_name archive_path extract_root
  archive_name="$(bootstrap_cassandra_archive_name)"
  archive_path="$BOOTSTRAP_CACHE_DIR/$archive_name"
  extract_root="$BOOTSTRAP_TOOLS_DIR/cassandra/$BOOTSTRAP_PLATFORM"
  if [ ! -f "$archive_path" ]; then
    bootstrap_download "$(bootstrap_cassandra_archive_url)" "$archive_path"
  fi
  bootstrap_extract_archive "$archive_path" "$extract_root"
  if [ ! -x "$BOOTSTRAP_DOWNLOADED_CASSANDRA_BIN" ] || [ ! -x "$BOOTSTRAP_DOWNLOADED_CQLSH_BIN" ]; then
    bootstrap_fail "Cassandra install completed but the expected binaries were not found in $BOOTSTRAP_DOWNLOADED_CASSANDRA_HOME."
  fi
  bootstrap_log "Installed Cassandra at $BOOTSTRAP_DOWNLOADED_CASSANDRA_HOME"
}

bootstrap_prepare_cassandra_config() {
  bootstrap_log "Preparing Cassandra runtime layout"
  rm -rf "$BOOTSTRAP_CASSANDRA_CONF_DIR"
  mkdir -p \
    "$BOOTSTRAP_CASSANDRA_CONF_DIR" \
    "$BOOTSTRAP_CASSANDRA_DATA_DIR" \
    "$BOOTSTRAP_CASSANDRA_COMMITLOG_DIR" \
    "$BOOTSTRAP_CASSANDRA_SAVED_CACHES_DIR" \
    "$BOOTSTRAP_CASSANDRA_HINTS_DIR" \
    "$BOOTSTRAP_CASSANDRA_CDC_DIR" \
    "$BOOTSTRAP_RUN_DIR/cassandra-logs"
  cp -R "$BOOTSTRAP_CASSANDRA_HOME/conf/." "$BOOTSTRAP_CASSANDRA_CONF_DIR/"
  "$BOOTSTRAP_NODE_BIN" --input-type=module -e '
    const [
      configPath,
      dataDir,
      commitlogDir,
      savedCachesDir,
      hintsDir,
      cdcDir,
      host,
      port,
    ] = process.argv.slice(1);
    import fs from "node:fs";
    const escapeRegex = (text) => String(text).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const replaceOrInsertScalar = (text, key, value) => {
      const activePattern = new RegExp(`^${escapeRegex(key)}:.*$`, "m");
      const commentedPattern = new RegExp(`^#\\s*${escapeRegex(key)}:.*$`, "m");
      const rendered = `${key}: ${value}`;
      if (activePattern.test(text)) {
        return text.replace(activePattern, rendered);
      }
      if (commentedPattern.test(text)) {
        return text.replace(commentedPattern, rendered);
      }
      return `${text.trimEnd()}\n${rendered}\n`;
    };
    const replaceOrInsertList = (text, key, values) => {
      const rendered = `${key}:\n${values.map((value) => `    - ${value}`).join("\n")}`;
      const activePattern = new RegExp(`^${escapeRegex(key)}:\\n(?:\\s*-\\s*.*\\n?)+`, "m");
      const commentedPattern = new RegExp(`^#\\s*${escapeRegex(key)}:\\n(?:\\s*#\\s*-\\s*.*\\n?)+`, "m");
      if (activePattern.test(text)) {
        return text.replace(activePattern, `${rendered}\n`);
      }
      if (commentedPattern.test(text)) {
        return text.replace(commentedPattern, `${rendered}\n`);
      }
      return `${text.trimEnd()}\n${rendered}\n`;
    };
    let text = fs.readFileSync(configPath, "utf8");
    text = replaceOrInsertScalar(text, "commitlog_directory", commitlogDir);
    text = replaceOrInsertScalar(text, "saved_caches_directory", savedCachesDir);
    text = replaceOrInsertScalar(text, "hints_directory", hintsDir);
    text = replaceOrInsertScalar(text, "cdc_raw_directory", cdcDir);
    text = replaceOrInsertScalar(text, "listen_address", host);
    text = replaceOrInsertScalar(text, "rpc_address", host);
    text = replaceOrInsertScalar(text, "native_transport_port", port);
    text = replaceOrInsertList(text, "data_file_directories", [dataDir]);
    fs.writeFileSync(configPath, text);
  ' \
    "$BOOTSTRAP_CASSANDRA_CONF_DIR/cassandra.yaml" \
    "$BOOTSTRAP_CASSANDRA_DATA_DIR" \
    "$BOOTSTRAP_CASSANDRA_COMMITLOG_DIR" \
    "$BOOTSTRAP_CASSANDRA_SAVED_CACHES_DIR" \
    "$BOOTSTRAP_CASSANDRA_HINTS_DIR" \
    "$BOOTSTRAP_CASSANDRA_CDC_DIR" \
    "$BOOTSTRAP_CASSANDRA_HOST" \
    "$BOOTSTRAP_CASSANDRA_PORT"
}

bootstrap_cqlsh_show_version() {
  PATH="$(bootstrap_java_bin_dir):$(dirname "$BOOTSTRAP_NODE_BIN"):$PATH" \
    CQLSH_PYTHON="$(command -v python3.11 2>/dev/null || command -v python3 2>/dev/null)" \
    timeout 10 "$1" "$BOOTSTRAP_CASSANDRA_HOST" "$BOOTSTRAP_CASSANDRA_PORT" -e "SHOW VERSION" 2>&1
}

bootstrap_wait_for_cassandra() {
  local cqlsh_bin timeout_seconds deadline output
  cqlsh_bin="$1"
  timeout_seconds="${2:-120}"
  deadline=$((SECONDS + timeout_seconds))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ -n "$BOOTSTRAP_CASSANDRA_PID" ] && ! kill -0 "$BOOTSTRAP_CASSANDRA_PID" >/dev/null 2>&1; then
      return 1
    fi
    output="$(bootstrap_cqlsh_show_version "$cqlsh_bin" || true)"
    if printf '%s\n' "$output" | grep -q "Cassandra $BOOTSTRAP_CASSANDRA_VERSION"; then
      printf '%s\n' "$output"
      return 0
    fi
    sleep 2
  done
  return 1
}

bootstrap_try_reuse_cassandra() {
  local cqlsh_bin cassandra_bin version_output
  cqlsh_bin="${1:-}"
  cassandra_bin="${2:-}"
  if [ -z "$cqlsh_bin" ]; then
    return 1
  fi
  version_output="$(bootstrap_cqlsh_show_version "$cqlsh_bin" || true)"
  if ! printf '%s\n' "$version_output" | grep -Eq "Cassandra [0-9]+\.[0-9]+"; then
    return 1
  fi

  BOOTSTRAP_CASSANDRA_BIN="$cassandra_bin"
  BOOTSTRAP_CQLSH_BIN="$cqlsh_bin"
  if printf '%s\n' "$version_output" | grep -q "Cassandra $BOOTSTRAP_CASSANDRA_VERSION"; then
    bootstrap_log "Cassandra $BOOTSTRAP_CASSANDRA_VERSION is already functional at $BOOTSTRAP_CASSANDRA_HOST:$BOOTSTRAP_CASSANDRA_PORT, moving on"
  else
    bootstrap_log "Reusing the functional Cassandra instance at $BOOTSTRAP_CASSANDRA_HOST:$BOOTSTRAP_CASSANDRA_PORT"
    bootstrap_log "The running Cassandra version differs from the managed $BOOTSTRAP_CASSANDRA_VERSION pin"
  fi
  printf '%s\n' "$version_output"
  return 0
}

bootstrap_start_cassandra_for_session() {
  local existing_cqlsh existing_cassandra version_output
  existing_cqlsh="$(bootstrap_existing_cqlsh_bin || true)"
  existing_cassandra="$(bootstrap_existing_cassandra_bin || true)"
  if bootstrap_try_reuse_cassandra "$existing_cqlsh" "$existing_cassandra"; then
    return
  fi

  bootstrap_select_java_runtime
  bootstrap_install_cassandra
  BOOTSTRAP_CASSANDRA_HOME="$BOOTSTRAP_DOWNLOADED_CASSANDRA_HOME"
  BOOTSTRAP_CASSANDRA_BIN="$BOOTSTRAP_DOWNLOADED_CASSANDRA_BIN"
  BOOTSTRAP_CQLSH_BIN="$BOOTSTRAP_DOWNLOADED_CQLSH_BIN"
  # The downloaded cqlsh may be the first usable client on this machine. Retry
  # discovery before starting a second Cassandra process on occupied ports.
  if bootstrap_try_reuse_cassandra "$BOOTSTRAP_CQLSH_BIN" "$existing_cassandra"; then
    return
  fi
  bootstrap_prepare_cassandra_config

  bootstrap_log "Starting Cassandra $BOOTSTRAP_CASSANDRA_VERSION for this session"
  rm -f "$BOOTSTRAP_RUN_DIR/cassandra.pid"
  if ! PATH="$(bootstrap_java_bin_dir):$(dirname "$BOOTSTRAP_NODE_BIN"):$PATH" \
      JAVA_HOME="${BOOTSTRAP_JAVA_HOME:-}" \
      CASSANDRA_CONF="$BOOTSTRAP_CASSANDRA_CONF_DIR" \
      CASSANDRA_LOG_DIR="$BOOTSTRAP_RUN_DIR/cassandra-logs" \
      JMX_PORT="$BOOTSTRAP_CASSANDRA_JMX_PORT" \
      MAX_HEAP_SIZE="${BOOTSTRAP_CASSANDRA_MAX_HEAP_SIZE:-512M}" \
      HEAP_NEWSIZE="${BOOTSTRAP_CASSANDRA_HEAP_NEWSIZE:-128M}" \
      "$BOOTSTRAP_CASSANDRA_BIN" -p "$BOOTSTRAP_RUN_DIR/cassandra.pid" >"$BOOTSTRAP_RUN_DIR/cassandra.log" 2>&1; then
    sed -n '1,160p' "$BOOTSTRAP_RUN_DIR/cassandra.log" >&2 || true
    bootstrap_fail "Cassandra failed to launch. See $BOOTSTRAP_RUN_DIR/cassandra.log."
  fi
  BOOTSTRAP_CASSANDRA_PID="$(cat "$BOOTSTRAP_RUN_DIR/cassandra.pid" 2>/dev/null || true)"
  if [ -z "$BOOTSTRAP_CASSANDRA_PID" ]; then
    bootstrap_fail "Cassandra did not write a pid file. See $BOOTSTRAP_RUN_DIR/cassandra.log."
  fi
  BOOTSTRAP_CASSANDRA_STARTED=1
  bootstrap_log "Cassandra started in the background with pid $BOOTSTRAP_CASSANDRA_PID"
  bootstrap_log "Waiting for Cassandra to accept connections on $BOOTSTRAP_CASSANDRA_HOST:$BOOTSTRAP_CASSANDRA_PORT"

  version_output="$(bootstrap_wait_for_cassandra "$BOOTSTRAP_CQLSH_BIN" 300 || true)"
  if [ -z "$version_output" ]; then
    tail -n 120 "$BOOTSTRAP_RUN_DIR/cassandra.log" >&2 || true
    bootstrap_fail "Cassandra did not become ready. See $BOOTSTRAP_RUN_DIR/cassandra.log."
  fi
  bootstrap_log "Cassandra is functional at $BOOTSTRAP_CASSANDRA_HOST:$BOOTSTRAP_CASSANDRA_PORT"
  printf '%s\n' "$version_output"
}

bootstrap_install_redis() {
  if bootstrap_install_redis_package_if_possible; then
    if bootstrap_existing_redis_server_bin >/dev/null 2>&1 && bootstrap_existing_redis_cli_bin >/dev/null 2>&1; then
      bootstrap_log "Redis package install completed"
      return
    fi
    bootstrap_fail "Redis package install completed, but redis-server and redis-cli are still unavailable."
  fi

  if [ -x "$BOOTSTRAP_DOWNLOADED_REDIS_SERVER_BIN" ] && [ -x "$BOOTSTRAP_DOWNLOADED_REDIS_CLI_BIN" ]; then
    bootstrap_log "Repo-local Redis already installed at $BOOTSTRAP_DOWNLOADED_REDIS_HOME"
    return
  fi
  bootstrap_log "Installing repo-local Redis $BOOTSTRAP_REDIS_VERSION from source"
  bootstrap_require_commands make
  bootstrap_install_redis_build_dependencies_if_missing
  mkdir -p "$BOOTSTRAP_CACHE_DIR" "$BOOTSTRAP_TOOLS_DIR/redis/$BOOTSTRAP_PLATFORM"
  local archive_name archive_path extract_root
  archive_name="$(bootstrap_redis_archive_name)"
  archive_path="$BOOTSTRAP_CACHE_DIR/$archive_name"
  extract_root="$BOOTSTRAP_TOOLS_DIR/redis/$BOOTSTRAP_PLATFORM"
  if [ ! -f "$archive_path" ]; then
    bootstrap_download "$(bootstrap_redis_archive_url)" "$archive_path"
  fi
  rm -rf "$BOOTSTRAP_DOWNLOADED_REDIS_HOME"
  bootstrap_extract_archive "$archive_path" "$extract_root"
  make -C "$BOOTSTRAP_DOWNLOADED_REDIS_HOME" BUILD_TLS=no MALLOC=libc redis-server redis-cli
  if [ ! -x "$BOOTSTRAP_DOWNLOADED_REDIS_SERVER_BIN" ] || [ ! -x "$BOOTSTRAP_DOWNLOADED_REDIS_CLI_BIN" ]; then
    bootstrap_fail "Redis install completed but the expected binaries were not found in $BOOTSTRAP_DOWNLOADED_REDIS_HOME."
  fi
  bootstrap_log "Installed Redis at $BOOTSTRAP_DOWNLOADED_REDIS_HOME"
}

bootstrap_redis_ping() {
  "$1" -h "$BOOTSTRAP_REDIS_HOST" -p "$BOOTSTRAP_REDIS_PORT" PING 2>/dev/null
}

bootstrap_wait_for_redis() {
  local redis_cli_bin timeout_seconds deadline output
  redis_cli_bin="$1"
  timeout_seconds="${2:-30}"
  deadline=$((SECONDS + timeout_seconds))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ -n "$BOOTSTRAP_REDIS_PID" ] && ! kill -0 "$BOOTSTRAP_REDIS_PID" >/dev/null 2>&1; then
      return 1
    fi
    output="$(bootstrap_redis_ping "$redis_cli_bin" || true)"
    if [ "$output" = "PONG" ]; then
      printf '%s\n' "$output"
      return 0
    fi
    sleep 1
  done
  return 1
}

bootstrap_start_redis_for_session() {
  local existing_server existing_cli ping_output
  existing_server="$(bootstrap_existing_redis_server_bin || true)"
  existing_cli="$(bootstrap_existing_redis_cli_bin || true)"
  if [ -n "$existing_cli" ]; then
    ping_output="$(bootstrap_redis_ping "$existing_cli" || true)"
    if [ "$ping_output" = "PONG" ]; then
      BOOTSTRAP_REDIS_SERVER_BIN="$existing_server"
      BOOTSTRAP_REDIS_CLI_BIN="$existing_cli"
      bootstrap_log "Redis is already functional at $BOOTSTRAP_REDIS_HOST:$BOOTSTRAP_REDIS_PORT, moving on"
      return
    fi
  fi

  if [ -n "$existing_server" ] && [ -n "$existing_cli" ]; then
    BOOTSTRAP_REDIS_SERVER_BIN="$existing_server"
    BOOTSTRAP_REDIS_CLI_BIN="$existing_cli"
  else
    bootstrap_install_redis
    BOOTSTRAP_REDIS_SERVER_BIN="$(bootstrap_existing_redis_server_bin || true)"
    BOOTSTRAP_REDIS_CLI_BIN="$(bootstrap_existing_redis_cli_bin || true)"
    if [ -z "$BOOTSTRAP_REDIS_SERVER_BIN" ] || [ -z "$BOOTSTRAP_REDIS_CLI_BIN" ]; then
      BOOTSTRAP_REDIS_SERVER_BIN="$BOOTSTRAP_DOWNLOADED_REDIS_SERVER_BIN"
      BOOTSTRAP_REDIS_CLI_BIN="$BOOTSTRAP_DOWNLOADED_REDIS_CLI_BIN"
    fi
  fi

  bootstrap_log "Starting Redis for this session"
  mkdir -p "$BOOTSTRAP_RUN_DIR/redis"
  rm -f "$BOOTSTRAP_RUN_DIR/redis.pid"
  "$BOOTSTRAP_REDIS_SERVER_BIN" \
    --bind "$BOOTSTRAP_REDIS_HOST" \
    --port "$BOOTSTRAP_REDIS_PORT" \
    --save "" \
    --appendonly no \
    --dir "$BOOTSTRAP_RUN_DIR/redis" \
    --pidfile "$BOOTSTRAP_RUN_DIR/redis.pid" \
    --logfile "$BOOTSTRAP_RUN_DIR/redis.log" \
    --daemonize yes
  BOOTSTRAP_REDIS_PID="$(cat "$BOOTSTRAP_RUN_DIR/redis.pid" 2>/dev/null || true)"
  if [ -z "$BOOTSTRAP_REDIS_PID" ]; then
    bootstrap_fail "Redis did not write a pid file. See $BOOTSTRAP_RUN_DIR/redis.log."
  fi
  BOOTSTRAP_REDIS_STARTED=1
  bootstrap_log "Redis started in the background with pid $BOOTSTRAP_REDIS_PID"
  bootstrap_log "Waiting for Redis to accept connections on $BOOTSTRAP_REDIS_HOST:$BOOTSTRAP_REDIS_PORT"

  ping_output="$(bootstrap_wait_for_redis "$BOOTSTRAP_REDIS_CLI_BIN" 30 || true)"
  if [ "$ping_output" != "PONG" ]; then
    bootstrap_fail "Redis did not become ready. See $BOOTSTRAP_RUN_DIR/redis.log."
  fi
  bootstrap_log "Redis is functional at $BOOTSTRAP_REDIS_HOST:$BOOTSTRAP_REDIS_PORT"
}

bootstrap_cleanup() {
  if [ "$BOOTSTRAP_CLEANUP_DONE" = "1" ]; then
    return
  fi
  BOOTSTRAP_CLEANUP_DONE=1
  if [ "$BOOTSTRAP_REDIS_STARTED" = "1" ] && [ -n "$BOOTSTRAP_REDIS_PID" ]; then
    bootstrap_log "Stopping session Redis"
    kill "$BOOTSTRAP_REDIS_PID" >/dev/null 2>&1 || true
    wait "$BOOTSTRAP_REDIS_PID" >/dev/null 2>&1 || true
    rm -f "$BOOTSTRAP_RUN_DIR/redis.pid"
  fi
  if [ "$BOOTSTRAP_CASSANDRA_STARTED" = "1" ] && [ -n "$BOOTSTRAP_CASSANDRA_PID" ]; then
    bootstrap_log "Stopping session Cassandra"
    kill "$BOOTSTRAP_CASSANDRA_PID" >/dev/null 2>&1 || true
    wait "$BOOTSTRAP_CASSANDRA_PID" >/dev/null 2>&1 || true
    rm -f "$BOOTSTRAP_RUN_DIR/cassandra.pid"
  fi
  if [ "$BOOTSTRAP_OLLAMA_STARTED" = "1" ] && [ -n "$BOOTSTRAP_OLLAMA_PID" ]; then
    bootstrap_log "Stopping session Ollama"
    kill "$BOOTSTRAP_OLLAMA_PID" >/dev/null 2>&1 || true
    wait "$BOOTSTRAP_OLLAMA_PID" >/dev/null 2>&1 || true
    rm -f "$BOOTSTRAP_RUN_DIR/ollama.pid"
  fi
}

bootstrap_cleanup_on_exit() {
  local exit_status="$?"
  trap - EXIT INT TERM HUP
  bootstrap_cleanup
  exit "$exit_status"
}

bootstrap_exit_for_signal() {
  case "${1:-}" in
    INT) exit 130 ;;
    TERM) exit 143 ;;
    HUP) exit 129 ;;
    *) exit 1 ;;
  esac
}

trap bootstrap_cleanup_on_exit EXIT
trap 'bootstrap_exit_for_signal INT' INT
trap 'bootstrap_exit_for_signal TERM' TERM
trap 'bootstrap_exit_for_signal HUP' HUP

main() {
  bootstrap_parse_local_dev_args "$@"
  bootstrap_require_commands tar
  bootstrap_ensure_core_download_tooling
  bootstrap_select_node_runtime
  bootstrap_install_npm_dependencies
  bootstrap_select_tectonic_cli
  bootstrap_start_cassandra_for_session
  bootstrap_start_redis_for_session
  bootstrap_install_ollama_if_missing
  bootstrap_start_ollama_for_session
  bootstrap_ensure_ollama_models

  bootstrap_log "Starting app on 0.0.0.0:8787"
  PATH="$(bootstrap_java_bin_dir):$(dirname "$BOOTSTRAP_NODE_BIN"):$PATH" \
    LD_LIBRARY_PATH="${BOOTSTRAP_TECTONIC_LIBRARY_PATH:+$BOOTSTRAP_TECTONIC_LIBRARY_PATH}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
    JAVA_HOME="${BOOTSTRAP_JAVA_HOME:-}" \
    AI_PROVIDER=ollama \
    OLLAMA_MODEL="$BOOTSTRAP_OLLAMA_MODEL" \
    OLLAMA_HOST="$BOOTSTRAP_OLLAMA_HOST" \
    OLLAMA_BASE_URL="$BOOTSTRAP_OLLAMA_BASE_URL" \
    OLLAMA_TIMEOUT_MS="${OLLAMA_TIMEOUT_MS:-300000}" \
    AI_TIMEOUT_MS="${AI_TIMEOUT_MS:-300000}" \
    TECTONIC_BIN="$BOOTSTRAP_TECTONIC_BIN" \
    "$BOOTSTRAP_NODE_BIN" "$BOOTSTRAP_REPO_ROOT/src/server.mjs"
}

if [ "${RUN_LOCAL_DEV_SOURCE_ONLY:-0}" != "1" ]; then
  main "$@"
fi
