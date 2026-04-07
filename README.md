# TracX

Aplicativo Flutter voltado para rotinas operacionais de producao, registro, consulta, movimentacao e leitura de QR Code em ambiente industrial.

O projeto foi estruturado para uso principalmente em Android, com suporte a leitura por camera e por coletor, armazenamento local, sincronizacao com APIs internas e recursos de atualizacao do app.

## Visao Geral

O TracX centraliza fluxos operacionais que antes costumam ficar espalhados entre papel, planilhas e consultas manuais. Hoje o app cobre principalmente:

- login e controle basico de acesso
- leitura de QR Code e preenchimento automatico de formularios
- registros de embalagem e tinturaria
- mapa de producao e consulta de mapas
- apontamento de produtividade
- historico de movimentacao
- listagem e exportacao de registros
- gerenciamento basico de usuarios
- atualizacao automatica do app em Android

## Objetivo do Projeto

O foco do app e acelerar operacoes no chao de fabrica, reduzir erro manual e manter o fluxo de dados entre operador, coletor e backend o mais direto possivel.

Na pratica, isso significa:

- menos digitacao manual
- leitura rapida de etiquetas e QR Codes
- registro padronizado das informacoes
- persistencia local para apoio offline/parcial
- integracao com APIs internas da empresa

## Linguagens e Tecnologias

| Camada | Tecnologia | Uso no projeto |
| --- | --- | --- |
| App mobile | Flutter | Interface, navegacao, formularios e logica de tela |
| Linguagem principal | Dart | Desenvolvimento do aplicativo |
| Android nativo | Kotlin | Integracao com DataWedge e recursos nativos |
| Persistencia local | Hive | Armazenamento leve de dados e registros locais |
| Banco local relacional | SQLite via `sqflite` | Cache e dados estruturados locais |
| Comunicacao HTTP | `http` e `dio` | Consumo de APIs, downloads e atualizacoes |
| Leitura de camera | `mobile_scanner`, `flutter_barcode_scanner_plus`, `flutter_zxing` | QR Code e codigos por camera |
| Coletor Android | DataWedge | Leitura por coletor em dispositivos compativeis |
| Exportacao | `pdf`, `excel`, `share_plus`, `printing` | Relatorios, compartilhamento e impressao |
| Atualizacao do app | `install_plugin_v3`, `package_info_plus` | Check e instalacao de novas versoes |

## Principais Dependencias

Algumas bibliotecas importantes usadas no projeto:

- `flutter`
- `mobile_scanner`
- `http`
- `dio`
- `hive` e `hive_flutter`
- `sqflite`
- `intl`
- `pdf`
- `excel`
- `share_plus`
- `path_provider`
- `permission_handler`
- `package_info_plus`
- `install_plugin_v3`
- `connectivity_plus`

## Principais Funcionalidades

### 1. Registro de Embalagem

Arquivo principal: `lib/views/RegistroEmbalagem.dart`

Permite registrar dados de embalagem a partir de:

- leitura por camera
- leitura por coletor
- preenchimento manual

O formulario pode preencher automaticamente campos como:

- ordem
- artigo
- cor
- quantidade
- peso
- metros
- data de tingimento
- numero de corte
- volume
- caixa

### 2. Registro de Tinturaria / Raschelina

Arquivo principal: `lib/views/RegistroTinturaria.dart`

Permite capturar os dados do material via QR Code e registrar informacoes como:

- nome do material
- largura crua
- elasticidade crua
- numero da maquina
- data de corte
- lote elastico

Tambem aceita leitura por:

- camera
- coletor

### 3. Tela Principal de Registro

Arquivo principal: `lib/screens/RegistroPrincipalScreen.dart`

Organiza os dois registros principais em abas:

- Embalagem
- Raschelina

### 4. Apontamento de Produtividade

Arquivo principal: `lib/screens/ApontamentoProdutividadeScreen.dart`

Fluxo de apontamento com foco em produtividade operacional, leitura assistida e integracao com entradas vindas de scanner/coletor.

### 5. Mapa de Producao

Arquivos principais:

- `lib/screens/MapaProducaoScreen.dart`
- `lib/screens/ConsultaMapaProducaoScreen.dart`

Responsavel pela leitura, consulta e sincronizacao de dados relacionados ao mapa de producao.

### 6. Lista e Exportacao de Registros

Arquivo principal: `lib/screens/ListaRegistrosScreen.dart`

Centraliza:

- visualizacao de registros
- selecao em lote
- exportacao em PDF
- exportacao em Excel
- compartilhamento de texto

### 7. Historico de Movimentacao

Arquivo principal: `lib/screens/HistoricoMovimentacaoScreen.dart`

Usado para consultar movimentacoes e apoiar rastreabilidade operacional.

### 8. Gestao de Usuarios

Arquivos principais:

- `lib/screens/CadastrarUsuarioScreen.dart`
- `lib/screens/ListarUsuariosScreen.dart`
- `lib/screens/AlterarSenhaScreen.dart`

Responsavel pelo fluxo de cadastro, listagem e atualizacao de usuarios.

### 9. Atualizacao Automatizada do App

Arquivo principal: `lib/services/update_service.dart`

O projeto possui logica para:

- verificar nova versao no servidor
- comparar com a versao instalada
- baixar APK
- instalar atualizacao no Android

## Leitura de QR Code e Coletor

O TracX trabalha com dois modelos principais de leitura:

### Camera

Usa o scanner da camera do dispositivo para ler QR Code diretamente pela interface do app.

### Coletor

Usa integracao com DataWedge em Android para leitura por dispositivos de coleta.

Arquivo principal:

- `lib/services/datawedge_service.dart`

Esse servico:

- configura o profile do DataWedge
- recebe os dados lidos pelo canal nativo
- entrega o resultado para as telas Flutter via `ValueNotifier`

Observacao importante:

- a integracao com coletor foi pensada para Android
- em outras plataformas o servico e ignorado

## Persistencia Local

O projeto combina dois formatos de armazenamento local:

### Hive

Usado para:

- registros locais
- dados simples de usuario
- estruturas leves e rapidas

Exemplos:

- `lib/models/registro.dart`
- `lib/models/registro_tinturaria.dart`

### SQLite

Usado para:

- cache estruturado
- dados operacionais locais
- apoio a consultas e sincronizacao

Arquivo principal:

- `lib/services/estoque_db_helper.dart`

## Comunicacao com Backend

O app consome APIs internas por HTTP, com varios endpoints apontando para servidor local/rede interna.

Exemplos encontrados no projeto:

- `http://168.190.90.2:5000/consulta/...`
- `http://168.190.90.2:5000/update/check`

Isso indica que o projeto hoje depende de infraestrutura interna para:

- consulta
- envio de registros
- sincronizacao
- verificacao de atualizacao

## Estrutura de Pastas

```text
lib/
|-- core/
|   `-- config/
|       `-- app_config.dart
|-- models/
|   |-- qr_code_data.dart
|   |-- qr_code_data_tinturaria.dart
|   |-- registro.dart
|   `-- registro_tinturaria.dart
|-- screens/
|   |-- login_screen.dart
|   |-- splash_screen.dart
|   |-- home_menu_screen.dart
|   |-- RegistroPrincipalScreen.dart
|   |-- ApontamentoProdutividadeScreen.dart
|   |-- MapaProducaoScreen.dart
|   |-- ConsultaMapaProducaoScreen.dart
|   |-- ListaRegistrosScreen.dart
|   |-- HistoricoMovimentacaoScreen.dart
|   |-- CadastrarUsuarioScreen.dart
|   |-- ListarUsuariosScreen.dart
|   |-- AlterarSenhaScreen.dart
|   |-- LocalizacaoScreen.dart
|   `-- ImpressaoQrScreen.dart
|-- services/
|   |-- auth_service.dart
|   |-- datawedge_service.dart
|   |-- estoque_db_helper.dart
|   |-- movimentacao_service.dart
|   |-- registro_service.dart
|   |-- SyncService.dart
|   `-- update_service.dart
|-- views/
|   |-- RegistroEmbalagem.dart
|   `-- RegistroTinturaria.dart
`-- widgets/
    `-- search_dialog.dart
```

## Fluxo Geral do Aplicativo

1. O app inicializa o Flutter e o DataWedge em `main.dart`
2. O Hive e aberto para dados locais importantes
3. O usuario entra pelo fluxo de login
4. O menu principal organiza os modulos do app
5. As telas operacionais leem QR Code por camera ou coletor
6. Os dados sao exibidos, validados e enviados ao backend
7. Parte das informacoes pode ser armazenada localmente para consulta e suporte operacional

## Tela Inicial e Navegacao

Arquivos importantes:

- `lib/main.dart`
- `lib/screens/splash_screen.dart`
- `lib/screens/login_screen.dart`
- `lib/screens/home_menu_screen.dart`

Esses arquivos controlam:

- bootstrap do app
- localizacao `pt-BR`
- inicializacao de storage local
- carregamento inicial
- autenticacao
- entrada no menu principal

## Ambiente de Desenvolvimento

Para trabalhar no projeto, o ambiente recomendado e:

- Flutter instalado
- Dart SDK compativel com o Flutter em uso
- Android Studio ou VS Code
- dispositivo Android ou emulador
- acesso a rede interna usada pelas APIs

## Como Rodar o Projeto

### 1. Instalar dependencias

```bash
flutter pub get
```

### 2. Rodar o app

```bash
flutter run
```

### 3. Gerar build Android

```bash
flutter build apk
```

## Geracao de Arquivos

O projeto usa geracao de codigo para modelos com Hive.

Quando necessario, rode:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

## Permissoes e Recursos Importantes

Dependendo da tela e do dispositivo, o app pode precisar de:

- camera
- armazenamento
- instalacao de APK
- acesso a internet

Em coletores Android, a configuracao do DataWedge e parte importante do funcionamento.

## Ferramentas e Recursos Utilizados

### Interface

- Material Design
- animacoes em Flutter
- componentes customizados
- design voltado a operacao rapida

### Leitura e Captura

- camera do dispositivo
- coletor Android com DataWedge
- QR Code

### Dados

- JSON
- APIs REST
- Hive
- SQLite

### Exportacao e Compartilhamento

- PDF
- Excel
- share sheet nativo
- impressao

## Pontos de Atencao Para Novos Desenvolvedores

- varios endpoints hoje estao apontando para IP interno fixo
- a integracao com coletor depende de Android e DataWedge
- parte do fluxo mistura persistencia local com envio imediato para API
- existem arquivos com nomes em padroes diferentes, o que pode ser melhorado numa futura padronizacao
- o projeto tem foco operacional, entao pequenas mudancas de UX podem impactar bastante o uso em campo

## Sugestoes de Evolucao

- centralizar URLs e configuracoes em um unico arquivo de ambiente
- separar melhor camadas de UI, dominio e dados
- padronizar nomes de arquivos e classes
- adicionar testes automatizados para parse de QR Code e regras de negocio
- documentar os contratos das APIs internas
- criar guias especificos para onboarding de coletor e atualizacao Android

## Para Quem Este Projeto E Util

Este repositorio e especialmente util para:

- desenvolvedores que vao manter o app
- analistas que precisam entender os modulos existentes
- usuarios internos que querem visualizar o escopo do sistema
- novos membros da equipe que precisam de onboarding rapido

## Resumo Tecnico

- Framework principal: Flutter
- Linguagem principal: Dart
- Plataforma alvo principal: Android
- Leitura: camera e coletor
- Persistencia local: Hive e SQLite
- Integracao externa: APIs HTTP internas
- Exportacao: PDF, Excel e compartilhamento
- Atualizacao: check de versao e instalacao de APK

## Observacao Final

Este README foi pensado para servir como documentacao inicial do projeto. Se o time quiser, o proximo passo natural e expandir a documentacao com:

- guia de instalacao por ambiente
- manual de uso por modulo
- documentacao de API
- padrao de contribuicao
- checklist de release
