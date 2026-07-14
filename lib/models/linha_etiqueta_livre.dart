enum AlinhamentoLinhaLivre { esquerda, centro, direita }

enum TamanhoLinhaLivre { pequeno, medio, grande }

class LinhaEtiquetaLivre {
  final String texto;
  final TamanhoLinhaLivre tamanho;
  final AlinhamentoLinhaLivre alinhamento;
  final bool negrito;

  const LinhaEtiquetaLivre({
    required this.texto,
    this.tamanho = TamanhoLinhaLivre.medio,
    this.alinhamento = AlinhamentoLinhaLivre.esquerda,
    this.negrito = false,
  });
}
