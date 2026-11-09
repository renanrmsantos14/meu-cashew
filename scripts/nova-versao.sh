#!/usr/bin/env bash
# Uso: scripts/nova-versao.sh [5.4.4+418]  (sem argumento: incrementa o PATCH e o build)
# Atualiza budget/pubspec.yaml e commita. Não cria tag nem faz push: ao chegar na main,
# o workflow Release Android publica essa versão. Use para mudar MAJOR/MINOR; o PATCH
# já sobe sozinho a cada merge.
set -euo pipefail
v="${1:-}"
raiz="$(git rev-parse --show-toplevel)"
cd "$raiz"
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Há alterações não commitadas; commite ou guarde antes." >&2
  exit 1
fi
atual=$(grep -m1 '^version:' budget/pubspec.yaml | awk '{print $2}' | tr -d '\r')
if [ -z "$v" ]; then
  base="${atual%%+*}"
  v="${base%.*}.$(( ${base##*.} + 1 ))+$(( ${atual#*+} + 1 ))"
fi
if ! [[ "$v" =~ ^[0-9]+(\.[0-9]+)*\+[0-9]+$ ]]; then
  echo "Uso: $0 [<versão>+<build>] (ex.: 5.4.4+418)" >&2
  exit 1
fi
if [ "${atual#*+}" -ge "${v#*+}" ]; then
  echo "O build ${v#*+} precisa ser maior que o atual (${atual#*+})." >&2
  exit 1
fi
sed -i "s/^version: .*/version: $v/" budget/pubspec.yaml
git add budget/pubspec.yaml
git commit -m "Versão $v"
echo "Versão $v commitada; o merge na main publica a Release."
