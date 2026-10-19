# ADR 0001: Endurecimento de segurança em scripts executados como root

## Status

Aceito

## Data

2026-10-19

## Contexto

A revisão de segurança semanal (issue #1) identificou que `scripts/fix_libexpat.sh` — executado como root em dispositivos iOS rootless (Dopamine / Procursus) — compilava o shim `libexpat.1.dylib` para um caminho fixo e previsível em `/tmp` (`/tmp/libexpat.1.dylib`), um diretório gravável por todos os usuários. Isso abria duas rotas de escalada de privilégio local para um atacante não privilegiado (ex.: processo `mobile` em dispositivo jailbroken, onde `/tmp` é compartilhado):

- **Symlink pré-plantado (CWE-59):** o atacante cria `/tmp/libexpat.1.dylib` como symlink para um arquivo-alvo; `clang -o` e `cp -f` seguem o link e o root sobrescreve o arquivo-alvo.
- **TOCTOU (CWE-367):** na janela entre a compilação (`clang`) e a instalação (`cp`), o atacante troca o arquivo temporário, e o root instala um dylib malicioso como biblioteca do sistema (`/var/jb/usr/lib/libexpat.1.dylib`) — execução de código persistente em qualquer processo que carregue libexpat.

O mesmo padrão de caminho fixo em `/tmp` era replicado nas instruções manuais de `README.md` e `skills/fix-libexpat-ios.md`.

## Decisão

1. Todo arquivo ou diretório temporário criado por script executado como root deve ser criado com `mktemp` / `mktemp -d` — nunca com caminho fixo em diretório gravável por todos. O diretório temporário recebe `chmod 700`.
2. O ciclo de vida do temporário é garantido por `trap` de limpeza no `EXIT`, com `HUP`/`INT`/`TERM` redirecionando para `exit`, de modo que a limpeza execute mesmo em erro ou interrupção.
3. Antes de instalar o artefato no sistema, o script valida que ele é um arquivo regular (não symlink: `[ -f ]` + `[ ! -L ]`) e pertence ao usuário efetivo/root (`[ -O ]`).
4. As instruções manuais em `README.md` e `skills/fix-libexpat-ios.md` foram atualizadas para usar `mktemp` em vez de caminhos fixos em `/tmp`, incluindo o passo de verificação pós-instalação.

## Consequências

- **Positivas:** elimina as rotas de escalada de privilégio local (CWE-59 e CWE-367) reportadas na issue #1; o artefato compilado permanece em diretório exclusivo do root durante todo o ciclo de build→assinatura→instalação; a limpeza é garantida mesmo em falha ou interrupção; a documentação deixa de ensinar um padrão inseguro.
- **Negativas / limitações:** exige `mktemp` disponível no ambiente (presente no Procursus/coreutils; alternativa é compilar direto para diretório de propriedade exclusiva do root fora de `/tmp`); a verificação de posse `[ -O ]` depende do suporte do `test` do shell (bash, zsh, dash e busybox suportam).
- **Neutras:** o comportamento funcional visível ao usuário final permanece idêntico — mesmos comandos, mesma saída e mesmo resultado da instalação.
