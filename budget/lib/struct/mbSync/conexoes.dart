import 'package:budget/struct/mbSync/cliente.dart';
import 'package:budget/struct/mbSync/estadoInicio.dart';

/// Situação de uma conexão (item do Pluggy) para a tela "Contas conectadas".
enum MbSituacao { emDia, atualizando, reconectar }

class MbContaConexao {
  const MbContaConexao(
      {required this.nome,
      required this.tipo,
      required this.saldo,
      required this.cartao});
  final String nome;
  final String tipo;
  final double? saldo;
  final bool cartao;

  static const _subtipos = {
    'CHECKING_ACCOUNT': 'Conta corrente',
    'SAVINGS_ACCOUNT': 'Poupança',
    'CREDIT_CARD': 'Cartão',
  };

  factory MbContaConexao.deJson(Map<String, dynamic> j) {
    final cartao = j['type'] == 'CREDIT';
    return MbContaConexao(
      nome: '${j['name'] ?? j['bank'] ?? 'Conta'}',
      tipo: _subtipos[j['subtype']] ?? (cartao ? 'Cartão' : 'Conta'),
      saldo: (j['balance'] as num?)?.toDouble(),
      cartao: cartao,
    );
  }
}

class MbConexao {
  const MbConexao(
      {required this.id,
      required this.banco,
      required this.status,
      required this.precisaReconectar,
      required this.atualizado,
      required this.contas});
  final String id;
  final String banco;
  final String? status;
  final bool precisaReconectar;
  final DateTime? atualizado;
  final List<MbContaConexao> contas;

  factory MbConexao.deJson(Map<String, dynamic> j) => MbConexao(
        id: '${j['id']}',
        banco: '${j['banco'] ?? 'Banco'}',
        status: j['status'] as String?,
        precisaReconectar: j['precisaReconectar'] == true,
        atualizado: DateTime.tryParse('${j['atualizado']}')?.toLocal(),
        contas: [
          for (final c in (j['contas'] as List? ?? const []))
            if (c is Map) MbContaConexao.deJson(c.cast<String, dynamic>())
        ],
      );

  // O servidor decide quando pede novo login (mesma regra dos avisos); aqui só vira texto.
  ({MbSituacao situacao, String rotulo}) get situacao => precisaReconectar
      ? (
          situacao: MbSituacao.reconectar,
          rotulo: status == 'WAITING_USER_INPUT'
              ? 'Pede confirmação'
              : 'Senha mudou'
        )
      : switch (status) {
          'UPDATED' => (situacao: MbSituacao.emDia, rotulo: 'Em dia'),
          'OUTDATED' => (
              situacao: MbSituacao.atualizando,
              rotulo: 'Falha temporária'
            ),
          null => (situacao: MbSituacao.atualizando, rotulo: 'Aguardando'),
          _ => (situacao: MbSituacao.atualizando, rotulo: 'Atualizando'),
        };

  String get sigla => mbSigla(banco);
}

Future<MbCliente> _cliente() async {
  final cliente = await mbClienteConfigurado();
  if (cliente == null)
    throw 'Pareie o app com o Meu Banco para ver as contas conectadas.';
  return cliente;
}

Future<List<MbConexao>> mbCarregarConexoes() async =>
    (await _cliente()).conexoes();

Future<void> mbRemoverConexao(String itemId) async =>
    (await _cliente()).removerConexao(itemId);
