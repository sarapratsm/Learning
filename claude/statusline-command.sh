#!/usr/bin/env bash
# Claude Code statusLine command
# Replica el status line de referencia:
#   ruta-truncada | [rama] | Modelo (ctx) | thinking | effort:X | 5h:X% 7d:X% | ctx:X% left | sesion in:X out:X ult in:X out:X cr:X

input=$(cat)

# ---------------------------------------------------------------------------
# JSON helpers (sin dependencia de jq)
# ---------------------------------------------------------------------------
get_str() { # $1=json $2=key -> primer valor string
  printf '%s' "$1" \
    | grep -oE "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 \
    | sed -E "s/.*:[[:space:]]*\"([^\"]*)\".*/\1/"
}
get_num_raw() { # $1=json $2=key -> valor numérico completo (con decimales)
  printf '%s' "$1" \
    | grep -oE "\"$2\"[[:space:]]*:[[:space:]]*[0-9][0-9.]*" | head -1 \
    | grep -oE '[0-9][0-9.]*'
}
get_num() { # $1=json $2=key -> parte entera
  get_num_raw "$1" "$2" | cut -d. -f1
}
get_bool() { # $1=json $2=key -> "true" o "false"
  printf '%s' "$1" \
    | grep -oE "\"$2\"[[:space:]]*:[[:space:]]*(true|false)" | head -1 \
    | grep -oE '(true|false)'
}
# Extrae el bloque JSON de un objeto anidado (un nivel)
get_block() { # $1=json $2=clave -> contenido interior del {}
  printf '%s' "$1" \
    | grep -oE "\"$2\"[[:space:]]*:[[:space:]]*\{[^}]*\}" | head -1 \
    | sed -E 's/^[^{]*\{//' | sed -E 's/\}[^}]*$//'
}

# ---------------------------------------------------------------------------
# ANSI colors
# ---------------------------------------------------------------------------
RESET=$'\033[0m'
DIR_C=$'\033[38;2;245;220;160m'       # amarillo pastel  -> ruta
BR_C=$'\033[1;32m'                     # verde negrita    -> rama
MODEL_C=$'\033[38;2;255;183;128m'      # naranja pastel   -> modelo
THINK_C=$'\033[38;2;180;180;180m'      # gris claro       -> thinking
EFFORT_C=$'\033[38;2;180;180;180m'     # gris claro       -> effort
TOK_C=$'\033[38;2;180;200;180m'        # verde grisáceo   -> tokens
RST_C=$'\033[38;2;180;180;180m'        # gris claro       -> resets_at
SEP_C=$'\033[38;2;100;100;110m'        # gris oscuro      -> separador

SEP=" ${SEP_C}|${RESET} "

# verde / amarillo / rojo según porcentaje (para ctx y rate)
color_pct_remaining() { # $1=pct_restante
  if   [ "$1" -ge 50 ]; then printf '\033[32m'
  elif [ "$1" -ge 20 ]; then printf '\033[33m'
  else                       printf '\033[31m'; fi
}
color_pct_used() { # $1=pct_usado (más uso = más rojo)
  local left=$(( 100 - $1 ))
  color_pct_remaining "$left"
}

# Formatea tokens en "k" con 1 decimal: 535300 -> "535.3k", 1200 -> "1.2k", 500 -> "0.5k"
fmt_k() { # $1=numero entero
  local n="$1"
  [ -z "$n" ] && { printf '?'; return; }
  # dividir entre 1000 con 1 decimal usando bash integer arithmetic
  local int=$(( n / 1000 ))
  local dec=$(( (n % 1000) / 100 ))
  printf '%d.%dk' "$int" "$dec"
}

# ---------------------------------------------------------------------------
# Extraer campos del JSON
# ---------------------------------------------------------------------------

# Directorio actual
dir_raw=$(get_str "$input" "current_dir")
[ -z "$dir_raw" ] && dir_raw=$(get_str "$input" "cwd")
dir_norm="${dir_raw//\\//}"   # backslashes -> slashes

# Mostrar solo la carpeta actual (basename)
dir_disp="${dir_norm##*/}"
[ -z "$dir_disp" ] && dir_disp="?"

# Modelo con tamaño de contexto window
model=$(get_str "$input" "display_name")
[ -z "$model" ] && model="Unknown"
model_str="$model"
# Añadir la ventana de contexto solo si el display_name no la incluye ya
case "$model" in
  *ontext*) ;;  # el nombre ya trae "(... context)"
  *)
    ctx_size_raw=$(get_num_raw "$input" "context_window_size")
    if [ -n "$ctx_size_raw" ]; then
      ctx_k=$(( ${ctx_size_raw%.*} / 1000 ))
      model_str="${model} (${ctx_k}k context)"
    fi
    ;;
esac

# Thinking enabled
thinking_enabled=$(get_bool "$(get_block "$input" "thinking")" "enabled")
thinking_str=""
[ "$thinking_enabled" = "true" ] && thinking_str="${THINK_C}thinking${RESET}"

# Effort level
effort_block=$(get_block "$input" "effort")
effort_level=$(get_str "$effort_block" "level")
effort_str=""
[ -n "$effort_level" ] && effort_str="${EFFORT_C}effort:${effort_level}${RESET}"

# Rate limits (porcentaje usado)
five_block=$(get_block "$(get_block "$input" "rate_limits")" "five_hour")
[ -z "$five_block" ] && five_block=$(get_block "$input" "five_hour")
week_block=$(get_block "$(get_block "$input" "rate_limits")" "seven_day")
[ -z "$week_block" ] && week_block=$(get_block "$input" "seven_day")

five_used=$(get_num "$five_block" "used_percentage")
week_used=$(get_num "$week_block" "used_percentage")

# Horas de reseteo de los límites (timestamps Unix -> hora/fecha local)
five_reset=$(get_num "$five_block" "resets_at")
week_reset=$(get_num "$week_block" "resets_at")
five_reset_t=""; week_reset_t=""
[ -n "$five_reset" ] && five_reset_t=$(date -d "@$five_reset" +%H:%M 2>/dev/null)
[ -n "$week_reset" ] && week_reset_t=$(date -d "@$week_reset" +%d/%m 2>/dev/null)

# Cada límite con su hora de reseteo entre paréntesis grises al lado
rate_str=""
if [ -n "$five_used" ]; then
  # etiqueta "5h:" en gris; solo el número% con color de semáforo
  rate_str="${rate_str}${RST_C}5h:$(color_pct_used "$five_used")${five_used}%${RESET}"
  [ -n "$five_reset_t" ] && rate_str="${rate_str} ${RST_C}(${five_reset_t})${RESET}"
fi
if [ -n "$week_used" ]; then
  [ -n "$rate_str" ] && rate_str="${rate_str} "
  rate_str="${rate_str}${RST_C}7d:$(color_pct_used "$week_used")${week_used}%${RESET}"
  [ -n "$week_reset_t" ] && rate_str="${rate_str} ${RST_C}(${week_reset_t})${RESET}"
fi

# Contexto restante
ctx_pct=$(get_num "$input" "remaining_percentage")
ctx_str=""
if [ -n "$ctx_pct" ]; then
  # "ctx:" y "left" en gris; solo el número% con color de semáforo
  ctx_str="${RST_C}ctx:$(color_pct_remaining "$ctx_pct")${ctx_pct}%${RST_C} left${RESET}"
else
  ctx_str="${SEP_C}ctx:-${RESET}"
fi

# Tokens NUEVOS (sin caché), del uso del turno/contexto actual.
# nuevos de entrada = input_tokens (no cacheado) + cache_creation (recién escrito);
# las lecturas de caché (cache_read) NO cuentan como nuevas.
cur_block=$(get_block "$input" "current_usage")
new_input_tok=$(get_num "$cur_block" "input_tokens")
cache_creation=$(get_num "$cur_block" "cache_creation_input_tokens")
out_tok=$(get_num "$cur_block" "output_tokens")
[ -z "$out_tok" ] && out_tok=$(get_num "$input" "total_output_tokens")

new_in=$(( ${new_input_tok:-0} + ${cache_creation:-0} ))

tok_str=""
if [ -n "$cur_block" ]; then
  tok_str="${TOK_C}$(fmt_k "$new_in")↑ $(fmt_k "${out_tok:-0}")↓${RESET}"
fi

# ---------------------------------------------------------------------------
# Rama git (desde el directorio de trabajo)
# ---------------------------------------------------------------------------
branch=""
[ -n "$dir_norm" ] && branch=$(git -C "$dir_norm" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
[ -z "$branch" ] && branch=$(git --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)

case "$branch" in
  SP_*)          BR_C=$'\033[38;2;255;182;193m' ;;  # rosa pastel (ramas Sara)
  "")            BR_C=$'\033[2;37m';  branch="no-branch" ;;
  *)             BR_C=$'\033[1;32m' ;;
esac

# ---------------------------------------------------------------------------
# Ensamblar línea — solo incluir secciones que tengan contenido
# ---------------------------------------------------------------------------
parts=()
parts+=("${DIR_C}${dir_disp}${RESET}")
parts+=("${BR_C}${branch}${RESET}")
parts+=("${MODEL_C}${model_str}${RESET}")
[ -n "$rate_str"     ] && parts+=("$rate_str")
parts+=("$ctx_str")
[ -n "$tok_str"      ] && parts+=("$tok_str")
[ -n "$thinking_str" ] && parts+=("$thinking_str")
[ -n "$effort_str"   ] && parts+=("$effort_str")

# Unir con separador
result=""
for part in "${parts[@]}"; do
  if [ -z "$result" ]; then
    result="$part"
  else
    result="${result}${SEP}${part}"
  fi
done

printf ' %s ' "$result"
