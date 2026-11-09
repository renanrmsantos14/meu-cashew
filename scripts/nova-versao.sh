#!/usr/bin/env bash
# Uso: scripts/nova-versao.sh 5.4.4+418
# Atualiza budget/pubspec.yaml, commita e cria a tag v<versão>+<build>. Não faz push.
set -euo pipefail
v="${1:-}"
if ! [[ "$v" =~ ^[0-9]+(\.[0-9]+)*\+[0-9]+$ ]]; then
  echo "Uso: $0 <versão>+<build> (ex.: 5.4.4+418)" >&2
  exit 1
fi
raiz="$(git rev-parse --show-toplevel)"
cd "$raiz"
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Há alterações não commitadas; commite ou guarde antes." >&2
  exit 1
fi
atual=$(grep -m1 '^version:' budget/pubspec.yaml | awk '{print $2}' | tr -d '\r')
if [ "${atual#*+}" -ge "${v#*+}" ]; then
  echo "O build ${v#*+} precisa ser maior que o atual (${atual#*+})." >&2
  exit 1
fi
sed -i "s/^version: .*/version: $v/" budget/pubspec.yaml
git add budget/pubspec.yaml
git commit -m "Versão $v"
git tag "v$v"
echo "Tag v$v criada. Para publicar:"
echo "  git push origin HEAD v$v"
