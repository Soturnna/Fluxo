# Fluxo

App pessoal de controle financeiro para iPhone, com Open Finance (via Meu Pluggy)
e um agente de IA (Google Gemini). Feito em SwiftUI e compilado sem Mac,
pelo GitHub Actions.

## Etapas

| Parte | Conteúdo | Situação |
|---|---|---|
| 1 | Fundação: visual, navegação, bloqueio por Face ID, Keychain, proteção no alternador, pipeline da `.ipa` | ✅ |
| 2 | Conexão com o Meu Pluggy: autenticação, contas e transações | ✅ |
| 3 | Cofre local criptografado, sincronização e tela de transações | ✅ |
| 3b | Categorias editáveis (trocar, criar, regras por estabelecimento) e orçamentos | ✅ |
| 4 | Agente com Gemini (consultas, gastos previstos, alterações com confirmação), filtros de privacidade e registro do que foi enviado | ✅ |

## Modelo de segurança

1. **Nenhum segredo no código.** Chaves do Pluggy e do Gemini são digitadas no app
   e guardadas no Keychain (`WhenUnlockedThisDeviceOnly`): só legíveis com o iPhone
   desbloqueado e fora de backups.
2. **Varredura de segredos.** Todo push passa pelo Gitleaks antes de compilar.
3. **Bloqueio do app.** Face ID (ou código do iPhone) ao abrir e ao voltar do
   segundo plano, numa janela própria acima de tudo (inclusive alertas e telas
   cheias). O tempo é medido por relógio monotônico, que não muda se o horário
   do aparelho for alterado.
4. **Afrouxar exige identidade.** Desligar qualquer proteção, salvar credenciais
   ou apagar dados pede Face ID.
5. **Alternador de apps.** Uma janela acima de tudo cobre a tela quando o app sai
   do primeiro plano.
6. **Só HTTPS.** Nenhuma exceção ao App Transport Security.
7. **Agente sem acesso ao dinheiro.** Nenhuma ferramenta de pagamento ou de escrita
   no banco existe no código. O agente lê dados e *propõe* mudanças locais (gasto
   previsto, categoria, nota, orçamento, categoria nova); cada proposta vira um
   cartão que só é aplicado quando você toca em Confirmar, e é validada de novo
   nesse momento. Isso também neutraliza injeção de instruções: um texto malicioso
   numa descrição de Pix não consegue alterar nada sozinho.
   Para a IA vão só data, valor, categoria, título e nota; ids reais viram
   referências curtas (t1, p1), nomes em Pix viram "Pessoa N" (revertidos só na
   tela) e sequências longas de dígitos são mascaradas. Tudo o que é enviado fica
   num registro cifrado que você pode auditar em Ajustes.
8. **Lista de permissão na leitura do Pluggy.** Os modelos decodificam só os campos
   usados. CPF, número da conta, agência, `paymentData` e CNPJ de estabelecimentos
   são ignorados já na leitura do JSON e nunca entram na memória do app.
9. **Cliente de rede restrito.** Endereço fixo (`api.pluggy.ai`), sessão efêmera sem
   cache nem cookies, TLS 1.2+, token de vida curta só na memória, cursor de
   paginação extraído (o link enviado pelo servidor nunca é seguido) e limite de páginas.
10. **Sessão com prazo.** Saldos, contas, token e textos digitados vivem na sessão.
   Voltar ao app em menos de 5 minutos só exige Face ID e retoma de onde parou;
   depois disso, a sessão é descartada e tudo é recriado do zero. Nenhuma tela
   com dados é montada antes do primeiro desbloqueio da sessão.
11. **Cofre local cifrado.** Contas e transações ficam num único arquivo cifrado com
   AES-GCM (256 bits). A chave é gerada no iPhone e guardada no Keychain como
   `ThisDeviceOnly`, então uma cópia do arquivo em outro lugar é ilegível; o GCM
   também detecta adulteração. O arquivo usa Proteção de Dados completa, gravação
   atômica e fica fora do backup.
12. **Sincronização robusta.** A tarefa pertence ao armazenamento, não à tela: trocar
   de aba não a interrompe. Cancelamentos nunca sobrescrevem dados bons.
13. **Seus dados à parte.** Categorias, trocas, regras e orçamentos ficam numa
   gaveta separada do cofre (`meus-dados.cofre`), com leitura tolerante a versões.
   Uma ressincronização das transações nunca apaga o que você configurou. Nomes
   digitados são limpos (sem caracteres de controle, até 30 caracteres) e ícones
   só podem vir de uma lista fixa.
14. **Ações fixadas por hash.** As GitHub Actions de terceiros usam o hash do commit,
   não a tag, para evitar troca maliciosa de versão.

## Estrutura

- `project.yml`: definição do projeto para o XcodeGen
- `Fluxo/App`: ponto de entrada e troca entre bloqueio e app
- `Fluxo/Security`: bloqueio, Keychain, proteção do alternador, preferências
- `Fluxo/Pluggy`: cliente da API e modelos com lista de permissão
- `Fluxo/Storage`: cofre cifrado, modelos guardados, categorias e sincronização
- `Fluxo/Agent`: cliente do Gemini, ferramentas, filtro de privacidade e registro
- `Fluxo/Design`: tema e componentes visuais
- `Fluxo/Views`: telas
- `design/icon.svg`: ícone (convertido em PNG na compilação)
- `.github/workflows/build-ipa.yml`: varredura de segredos + compilação

## Compilar e instalar

Cada push na `main` gera um `.ipa` sem assinatura na página **Releases**
(com o SHA-256 do arquivo). Instale pelo iOSGods App+.
