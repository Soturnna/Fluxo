# Fluxo

App pessoal de controle financeiro para iPhone, com Open Finance (via Meu Pluggy)
e um agente de IA (Google Gemini). Feito em SwiftUI e compilado sem Mac,
pelo GitHub Actions.

## Etapas

| Parte | Conteúdo | Situação |
|---|---|---|
| 1 | Fundação: visual, navegação, bloqueio por Face ID, Keychain, proteção no alternador, pipeline da `.ipa` | ✅ |
| 2 | Conexão com o Meu Pluggy: autenticação, contas e transações | ✅ |
| 3 | Banco de dados local criptografado e telas com dados reais | ⏳ |
| 4 | Agente com Gemini, filtros de privacidade e registro do que foi enviado | ⏳ |

## Modelo de segurança

1. **Nenhum segredo no código.** Chaves do Pluggy e do Gemini são digitadas no app
   e guardadas no Keychain (`WhenUnlockedThisDeviceOnly`): só legíveis com o iPhone
   desbloqueado e fora de backups.
2. **Varredura de segredos.** Todo push passa pelo Gitleaks antes de compilar.
3. **Bloqueio do app.** Face ID (ou código do iPhone) ao abrir e ao voltar do
   segundo plano. O tempo é medido por relógio monotônico, que não muda se o
   horário do aparelho for alterado.
4. **Afrouxar exige identidade.** Desligar qualquer proteção, salvar credenciais
   ou apagar dados pede Face ID.
5. **Alternador de apps.** Uma janela acima de tudo cobre a tela quando o app sai
   do primeiro plano.
6. **Só HTTPS.** Nenhuma exceção ao App Transport Security.
7. **Agente só de leitura** (Parte 4). Nenhuma ferramenta de pagamento existe no
   código. Apenas data, valor, categoria e estabelecimento vão para a IA; CPF,
   contas, agências e o bloco `paymentData` nunca saem do aparelho.
8. **Lista de permissão na leitura do Pluggy.** Os modelos decodificam só os campos
   usados. CPF, número da conta, agência, `paymentData` e CNPJ de estabelecimentos
   são ignorados já na leitura do JSON e nunca entram na memória do app.
9. **Cliente de rede restrito.** Endereço fixo (`api.pluggy.ai`), sessão efêmera sem
   cache nem cookies, TLS 1.2+, token de vida curta só na memória, cursor de
   paginação extraído (o link enviado pelo servidor nunca é seguido) e limite de páginas.
10. **Dados só enquanto desbloqueado.** Saldos e contas vivem na árvore de telas do app
   desbloqueado e são descartados ao bloquear.
11. **Ações fixadas por hash.** As GitHub Actions de terceiros usam o hash do commit,
   não a tag, para evitar troca maliciosa de versão.

## Estrutura

- `project.yml`: definição do projeto para o XcodeGen
- `Fluxo/App`: ponto de entrada e troca entre bloqueio e app
- `Fluxo/Security`: bloqueio, Keychain, proteção do alternador, preferências
- `Fluxo/Pluggy`: cliente da API, modelos com lista de permissão, estado das conexões
- `Fluxo/Design`: tema e componentes visuais
- `Fluxo/Views`: telas
- `design/icon.svg`: ícone (convertido em PNG na compilação)
- `.github/workflows/build-ipa.yml`: varredura de segredos + compilação

## Compilar e instalar

Cada push na `main` gera um `.ipa` sem assinatura na página **Releases**
(com o SHA-256 do arquivo). Instale pelo iOSGods App+.
