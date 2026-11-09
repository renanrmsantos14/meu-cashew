---
name: verificar-editorial-web
description: "Verifica o tema Editorial, a Início, o layout desktop, a versão visível e o build web em /app/. Use após mudar budget/lib/struct/editorial.dart, budget/lib/widgets/editorial, budget/lib/pages/homePage, bottomNavBar, navigationFramework, budget/web, pubspec ou scripts."
---
# Verificar Editorial e web

## Cobre
- Código: `budget/lib/struct/editorial.dart`, `budget/lib/widgets/editorial/**`, `budget/lib/pages/homePage/**`, `bottomNavBar.dart`, `navigationFramework.dart`, `budget/web/**`, `scripts/**`.

## Preparar ambiente
- `export PATH=$HOME/dev/flutter/bin:$PATH` e `cd budget`.

## Roteiro
1. `flutter test test/editorial_test.dart test/desktop_test.dart test/mb_inicio_test.dart test/versao_test.dart` → todos passam.
2. `flutter analyze` → 0 erros (o restante é aviso herdado do Cashew).
3. `flutter build web --base-href /app/` → "Built build/web".
4. `rg -c "gstatic|firebase" build/web/index.html` → 0 ocorrências (sem Firebase em tempo de execução).
5. UI alterada: print do estado real (celular 390x844 e desktop 1440x900, claro e escuro) com `playwright-core` sobre `build/web` servido com `--base-href /app/`; a versão `vX.Y.Z · dd/mm/aaaa HH:mm` aparece sem cobrir conteúdo e sem capturar clique.

## Casos de borda
- Início vazia e carregando; app não pareado mantém o fluxo original do Cashew; página empilhada no desktop mantém a versão visível.

## Evidência obrigatória
- Tail dos testes e do build web; prints em `.verificacao/<data>-<branch>/`.

## Limites
- Sem aparelho Android aqui; widget e notificações ficam na `verificar-meu-banco`.
