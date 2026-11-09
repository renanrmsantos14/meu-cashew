import 'package:budget/struct/editorial.dart';
import 'package:budget/struct/keyboardIntents.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/editorial/buscaRapida.dart';
import 'package:budget/widgets/editorial/detalheTransacao.dart';
import 'package:budget/widgets/editorial/lateralEditorial.dart';
import 'package:budget/widgets/editorial/layoutDesktop.dart';
import 'package:budget/widgets/navigationFramework.dart' show navigatorKey;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<DetalheModelo?> _detalhe(String pk) async => DetalheModelo(
      pk: pk,
      nome: 'IFOOD *PEDIDO',
      conta: 'Nubank',
      categoria: 'Alimentação',
      data: DateTime(2026, 11, 8),
      valor: 42.5,
      receita: false,
    );

Future<List<ResultadoBusca>> _buscar(String q) async => [
      (pk: 'a', nome: 'IFOOD', quando: 'hoje', valor: 10.0, receita: false)
    ];

Future<void> _montar(WidgetTester t, Size tamanho,
    {Future<void> Function(DetalheModelo)? aoMudar}) async {
  t.view.physicalSize = tamanho;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    navigatorKey: navigatorKey,
    theme: temaEditorial(Brightness.light),
    shortcuts: shortcuts,
    actions: keyboardIntents,
    home: Builder(
      builder: (context) => ehDesktop(context)
          ? LayoutDesktop(
              lateral: const LateralEditorial.comDados(contas: []),
              conteudo: const Focus(autofocus: true, child: SizedBox.expand()),
              carregarDetalhe: _detalhe,
              aoMudarCategoria: aoMudar,
            )
          : const Scaffold(
              body: SizedBox.expand(),
              bottomNavigationBar: SizedBox(key: Key('barra'), height: 56)),
    ),
  ));
  await t.pump();
}

void main() {
  setUp(() {
    mbTransacaoSelecionada.value = null;
    appStateSettings = {
      "materialYou": false,
      "accentSystemColor": false,
      "batterySaver": false,
      "outlinedIcons": false,
      "increaseTextContrast": false,
      "forceFullDarkBackground": false,
    };
  });

  testWidgets('lateral com marca e versão', (t) async {
    await _montar(t, const Size(1280, 800));
    expect(find.text('Meu Banco'), findsOneWidget);
    expect(find.textContaining('· dev'), findsOneWidget);
    expect(t
            .getSize(find
                .ancestor(
                    of: find.byType(LateralEditorial),
                    matching: find.byType(Container))
                .first)
            .width,
        mbLarguraLateral);
  });

  testWidgets('selecionar transação abre detalhe de 360', (t) async {
    await _montar(t, const Size(1280, 800));
    expect(find.byType(DetalheTransacao), findsNothing);
    mbTransacaoSelecionada.value = 'x';
    await t.pump();
    await t.pump();
    expect(find.byType(DetalheTransacao), findsOneWidget);
    expect(t
            .getSize(find
                .ancestor(
                    of: find.byType(DetalheTransacao),
                    matching: find.byType(Container))
                .first)
            .width,
        mbLarguraDetalhe);
    expect(find.text('IFOOD *PEDIDO'), findsWidgets);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(mbTransacaoSelecionada.value, isNull);
  });

  testWidgets('Ctrl+K abre a busca sem animação e Esc fecha', (t) async {
    await _montar(t, const Size(1280, 800));
    await t.sendKeyDownEvent(LogicalKeyboardKey.control);
    await t.sendKeyEvent(LogicalKeyboardKey.keyK);
    await t.sendKeyUpEvent(LogicalKeyboardKey.control);
    await t.pump();
    expect(find.byType(BuscaRapida), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(find.byType(BuscaRapida), findsNothing);
  });

  testWidgets('C com detalhe aberto aciona a troca de categoria', (t) async {
    var chamadas = 0;
    await _montar(t, const Size(1280, 800), aoMudar: (_) async => chamadas++);
    mbTransacaoSelecionada.value = 'x';
    await t.pump();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.keyC);
    await t.pump();
    expect(chamadas, 1);
  });

  testWidgets('390x844 sem lateral e com barra inferior', (t) async {
    await _montar(t, const Size(390, 844));
    expect(find.byType(LateralEditorial), findsNothing);
    expect(find.byKey(const Key('barra')), findsOneWidget);
  });
}
