#!/usr/bin/env bash
set -euo pipefail

# Finds the terraform root from wherever the script is called.
# Supports being called from repo root or from the infrastructure/ dir directly.
find_tf_root() {
  local backend_file
  backend_file=$(find "$PWD" -maxdepth 3 -name '*.backend' -print -quit 2>/dev/null)
  if [[ -n "$backend_file" ]]; then
    echo "$(dirname "$(dirname "$backend_file")")" "$(basename "$(dirname "$backend_file")")"
  else
    echo "Error: Cannot find terraform root."
    echo "No *.backend files found under $PWD."
    exit 1
  fi
}

read -r TF_ROOT ENV_DIR < <(find_tf_root)

# Expected files, to be configured by the developer. See README for details.
RESOURCES_FILE="$TF_ROOT/local-tf-resources.json"
BACKEND_CONFIG="$TF_ROOT/$ENV_DIR/local.backend"
# I configure them in .zshrc so that they are automatically set when I switch AWS profiles
TFVARS_FILE="$TF_ROOT/$ENV_DIR/$WORKSPACE_TFVARS_FILE"
PERSONAL_TF_WORKSPACE=$PERSONAL_TF_WORKSPACE_BUCKET

if [[ ! -f "$BACKEND_CONFIG" ]]; then
  echo "Creating $BACKEND_CONFIG..."
  mkdir -p "$(dirname "$BACKEND_CONFIG")"
  echo 'bucket = "$PERSONAL_TF_WORKSPACE"' > "$BACKEND_CONFIG"
  echo "Created with bucket = \"$PERSONAL_TF_WORKSPACE\""
fi

if [[ ! -f "$RESOURCES_FILE" ]]; then
  echo "Error: $RESOURCES_FILE not found."
  echo "Create it with your target modules, e.g.:"
  echo '  { "targets": ["module.my_module"] }'
  exit 1
fi

build_targets() {
  local targets=""
  local state_list=""
  local need_state=false

  # Decide if we really need to list state. A "whole-prefix" wildcard like
  # `module.foo.*` can be rewritten to `module.foo` — terraform treats that as
  # "whole module, present and future", so it works on a fresh env with empty
  # state. We only need state for finer-grained wildcards like `module.foo.aws_iam_*`.
  while IFS= read -r target; do
    if [[ "$target" == *'*'* || "$target" == *'?'* ]]; then
      if [[ "$target" == *.\* ]]; then
        local prefix="${target%.\*}"
        if [[ "$prefix" != *'*'* && "$prefix" != *'?'* ]]; then
          continue
        fi
      fi
      need_state=true
      break
    fi
  done < <(jq -r '.targets[]' "$RESOURCES_FILE")

  if $need_state; then
    echo "Expanding wildcard targets against terraform state..." >&2
    state_list=$(terraform -chdir="$TF_ROOT" state list 2>/dev/null) || {
      echo "Error: failed to list terraform state. Run 'local-tf init' first." >&2
      exit 1
    }
  fi

  while IFS= read -r target; do
    # Whole-prefix wildcards: rewrite `module.X.*` to `module.X`.
    if [[ "$target" == *.\* ]]; then
      local prefix="${target%.\*}"
      if [[ "$prefix" != *'*'* && "$prefix" != *'?'* ]]; then
        targets="$targets -target=$prefix"
        echo "Target '$target' -> '$prefix' (whole-prefix expansion, no state needed)." >&2
        continue
      fi
    fi

    if [[ "$target" == *'*'* || "$target" == *'?'* ]]; then
      local matched=0
      while IFS= read -r resource; do
        [[ -z "$resource" ]] && continue
        # shellcheck disable=SC2254
        if [[ "$resource" == $target ]]; then
          targets="$targets -target=$resource"
          matched=$((matched + 1))
        fi
      done <<< "$state_list"
      if [[ $matched -eq 0 ]]; then
        echo "Warning: wildcard '$target' matched no resources in state (state may be empty on first apply)." >&2
      else
        echo "Wildcard '$target' matched $matched resource(s)." >&2
      fi
    else
      targets="$targets -target=$target"
    fi
  done < <(jq -r '.targets[]' "$RESOURCES_FILE")
  echo "$targets"
}

cmd_init() {
  echo "TF root: $TF_ROOT"
  echo "Backend: $BACKEND_CONFIG"
  echo "Initializing with local backend..."
  terraform -chdir="$TF_ROOT" init -backend-config="$BACKEND_CONFIG" -reconfigure "$@"
}

cmd_plan() {
  local targets
  targets=$(build_targets)
  echo "TF root: $TF_ROOT"
  echo "Targets: $(jq -r '.targets | join(", ")' "$RESOURCES_FILE")"
  terraform -chdir="$TF_ROOT" plan -var-file="$TFVARS_FILE" $targets "$@"
}

cmd_apply() {
  local targets
  targets=$(build_targets)
  echo "TF root: $TF_ROOT"
  echo "Targets: $(jq -r '.targets | join(", ")' "$RESOURCES_FILE")"
  terraform -chdir="$TF_ROOT" apply -var-file="$TFVARS_FILE" -auto-approve $targets "$@"
}

cmd_destroy() {
  local targets
  targets=$(build_targets)
  echo "TF root: $TF_ROOT"
  echo "Targets to be destroyed: $(jq -r '.targets | join(", ")' "$RESOURCES_FILE")"
  terraform -chdir="$TF_ROOT" destroy -var-file="$TFVARS_FILE" $targets "$@"
}

cmd_destroy_all() {
  echo "TF root: $TF_ROOT"
  echo "WARNING: this will destroy EVERYTHING in the tfstate, not just the targets in $RESOURCES_FILE."
  read -r -p "Are you sure? [y/N] " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
  fi
  terraform -chdir="$TF_ROOT" destroy -var-file="$TFVARS_FILE" "$@"
}

cmd_output() {
  terraform -chdir="$TF_ROOT" output "$@"
}

usage() {
  echo "local-tf: Run terraform with a personal backend and targeted resources."
  echo ""
  echo "Usage: local-tf <command> [extra terraform flags]"
  echo ""
  echo "Commands:"
  echo "  init      Initialize terraform with local backend"
  echo "  plan      Plan targeted resources"
  echo "  apply     Apply targeted resources"
  echo "  destroy       Destroy targeted resources"
  echo "  destroy-all   Destroy everything in the tfstate (with confirmation)"
  echo "  output    Show terraform outputs"
  echo ""
  echo "Expected files in the repo's terraform root:"
  echo "  environment/local.backend     Your personal S3 backend config"
  echo "  environment/staging.tfvars    Your tfvars"
  echo "  local-tf-resources.json       Modules to target"
}

case "${1:-}" in
  init)    shift; cmd_init "$@" ;;
  plan)    shift; cmd_plan "$@" ;;
  apply)   shift; cmd_apply "$@" ;;
  destroy) shift; cmd_destroy "$@" ;;
  destroy-all) shift; cmd_destroy_all "$@" ;;
  output)  shift; cmd_output "$@" ;;
  help)    usage ;;
  *)       usage ;;
esac
