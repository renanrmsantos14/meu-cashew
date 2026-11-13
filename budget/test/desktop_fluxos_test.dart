import 'package:budget/database/tables.dart';
import 'package:budget/pages/transacoesDesktop.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/temas.dart';
import 'package:budget/widgets/editorial/painelTransacao.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Transaction _t(String pk, String nome, double valor, {bool receita = false, String nota = ''}) =>
    Transaction(
      transactionPk: pk,
      name: nome,
      amount: valor,
      note: nota,
      categoryFk: 'c1',
      walletFk: '0',
      dateCreated: DateTime(2026, 11, 10),
      income: receita,
      paid: true,
      skipPaid: true,
    );

LinhaTransacao _l(Transaction t, String categoria, String conta) => LinhaTransacao(
    transacao: t, categoria: categoria, conta: conta, valorPrincipal: t.amount);

final _cats = [
  TransactionCategory(
      categoryPk: 'c1', name: 'Mercado', dateCreated: DateTime(2026), order: 0, income: false, methodAdded: null),
];

void main() {
  test('mbLerValor aceita formatos brasileiros e recusa lixo', () {
    expect(mbLerValor('45,90'), 45.9);
    expect(mbLerValor('1.234,56'), 1234.56);
    expect(mbLerValor('R\$ 12'), 12);
    expect(mbLerValor('12.5'), 12.5);
    expect(mbLerValor('1.500'), 1500);
    expect(mbLerValor('2.000.000'), 2000000);
    expect(mbLerValor(''), isNull);
    expect(mbLerValor('abc'), isNull);
  });

  test('mbFiltrarLinhas filtra por tipo e por texto em descrição, categoria, conta e notas', () {
    final linhas = [
      _l(_t('a', 'Pão de Açúcar', -182.3), 'Mercado', 'Nubank'),
      _l(_t('b', 'Salário', 6500, receita: true), 'Renda', 'Itaú'),
      _l(_t('c', 'Uber', -27.9, nota: 'aeroporto'), 'Transporte', 'Nubank'),
    ];
    expect(mbFiltrarLinhas(linhas, '', null).length, 3);
    expect(mbFiltrarLinhas(linhas, '', true).map((l) => l.transacao.name), ['Salário']);
    expect(mbFiltrarLinhas(linhas, 'nubank', false).length, 2);
    expect(mbFiltrarLinhas(linhas, 'AEROPORTO', null).map((l) => l.transacao.name), ['Uber']);
    expect(mbFiltrarLinhas(linhas, 'mercado', null).map((l) => l.transacao.name), ['Pão de Açúcar']);
  });

  Future<void> monta(WidgetTester t, {Transaction? transacao}) async {
    appStateSettings = {
      'materialYou': false,
      'accentSystemColor': false,
      'batterySaver': false,
      'increaseTextContrast': false,
      'selectedWalletPk': '0',
      'autoAddAssociatedTitles': false,
    };
    t.view.physicalSize = const Size(420, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(Provider<AllWallets>.value(
      value: AllWallets(list: const [], indexedByPk: const {}),
      child: MaterialApp(
        theme: temaFlutter(temaPorId('padrao-claro')),
        home: Scaffold(
            body: FormularioTransacao(
                key: UniqueKey(),
                edicao: mbEdicaoDesktop.value,
                transacao: transacao,
                categorias: () async => _cats)),
      ),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('formulário novo: todos os campos à vista e validação antes de salvar', (t) async {
    await monta(t);
    expect(find.text('Nova transação'), findsOneWidget);
    for (final rotulo in ['Valor', 'Descrição', 'Categoria', 'Conta', 'Notas']) {
      expect(find.text(rotulo), findsWidgets, reason: rotulo);
    }
    await t.tap(find.text('Salvar'));
    await t.pump();
    expect(find.text('Informe um valor maior que zero.'), findsOneWidget);

    await t.enterText(find.byKey(const ValueKey('valor')), '45,90');
    await t.tap(find.text('Salvar'));
    await t.pump();
    expect(find.text('Escolha a categoria.'), findsOneWidget);
  });

  testWidgets('editar preenche os campos com a transação', (t) async {
    await monta(t, transacao: _t('x', 'Padaria', -18.9));
    expect(find.text('Editar transação'), findsOneWidget);
    expect(find.text('18,90'), findsOneWidget);
    expect(find.text('Padaria'), findsOneWidget);
  });

  testWidgets('Esc sem alterações fecha; com alterações pede confirmação', (t) async {
    mbEdicaoDesktop.value = const EdicaoDesktop(null);
    await monta(t);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(mbEdicaoDesktop.value, isNull);

    mbEdicaoDesktop.value = const EdicaoDesktop(null);
    await monta(t);
    await t.enterText(find.byKey(const ValueKey('valor')), '10');
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Descartar alterações?'), findsOneWidget);
    await t.tap(find.text('Continuar editando'));
    await t.pumpAndSettle();
    expect(mbEdicaoDesktop.value, isNotNull);
  });

  testWidgets('Tab vai do valor para a descrição', (t) async {
    await monta(t);
    await t.enterText(find.byKey(const ValueKey('valor')), '45,90');
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    final editavel = t.widget<EditableText>(find.descendant(
        of: find.byKey(const ValueKey('descricao')),
        matching: find.byType(EditableText)));
    expect(editavel.focusNode.hasFocus, isTrue);
    await t.enterText(find.byKey(const ValueKey('descricao')), 'Padaria');
    expect(find.text('Padaria'), findsOneWidget);
  });

  testWidgets('escolher a categoria no menu preenche o campo', (t) async {
    await monta(t);
    await t.tap(find.byType(DropdownMenu<String>).first);
    await t.pumpAndSettle();
    await t.tap(find.text('Mercado').last);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('valor')), '45,90');
    await t.tap(find.text('Salvar'));
    await t.pump();
    expect(find.text('Escolha a categoria.'), findsNothing);
  });
}
