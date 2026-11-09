---
name: verificar-meu-banco
description: "Verifica o sync Meu Banco do app (LWW, pareamento por QR e deep link meubanco://, Pluggy, alertas em segundo plano, widget). Use após mudar budget/lib/struct/mbSync, budget/lib/struct/meuBanco*.dart, budget/lib/pages/meuBanco*.dart, appLinks.dart ou budget/android, ou quando pedirem para testar o sync."
---
# Verificar Meu Banco

## Cobre
- Código: `budget/lib/struct/mbSync/**`, `budget/lib/struct/meuBancoSync.dart`, `meuBancoMapping.dart`, `budget/lib/pages/meuBancoPage.dart`, `meuBancoParear.dart`, `meuBancoConectar.dart`, `budget/lib/widgets/util/appLinks.dart`, manifest e widget Android.
- Schema do Drift continua em 46: as tabelas `mb_registros`, `mb_estado` e `mb_aplicado` nascem por `mbCriarTabelas()`, fora do Drift.

## Preparar ambiente
- `export PATH=$HOME/dev/flutter/bin:$PATH JAVA_HOME=$HOME/dev/jdk17 ANDROID_HOME=$HOME/Android/Sdk` e `cd budget`.
- Sem rede nem token real: os testes usam cliente falso e Drift em memória.

## Roteiro
1. `flutter test test/mb_sync_nucleo_test.dart test/mb_sync_drift_test.dart test/mb_pareamento_test.dart test/mb_pluggy_test.dart test/mb_segundo_plano_test.dart test/mb_mapeamento_test.dart test/meu_banco_mapping_test.dart` → todos passam.
2. `flutter analyze lib/struct/mbSync lib/struct/meuBancoSync.dart lib/pages` → sem erros novos.
3. Se tocou em Android: `flutter build apk --debug` → "Built build/app/outputs/flutter-apk/app-debug.apk".
4. Segurança (leitura do diff): token só em `flutter_secure_storage`, nunca em `appStateSettings`; `meubanco://parear` só grava depois de `mbConfirmarEParear`; origem só https (http só em debug para localhost/10.0.2.2); toda entrada manual de token/endereço passa pelo mesmo caminho do QR.

## Casos de borda
- Troca de conta apaga espelho, fila, estado, `mb:` importado, carteiras e categorias `mb:` sem uso, e preserva o que nasceu no Cashew.
- Registro remoto mais velho não sobrescreve o espelho; exclusão local vira tombstone.
- Token inválido (401) e limite de 30 min (429) mostram mensagem fixa em pt-BR.

## Evidência obrigatória
- Tail da saída de `flutter test` (todos passando) e de `flutter analyze`.

## Limites
- Pareamento com câmera, Pluggy Connect, workmanager e widget só em aparelho; nada de produção (`wrangler`, `pnpm push`).
