# Floating Music

Mini leitor nativo para macOS, em SwiftUI e AppKit. Janela translúcida sempre por cima, arrastável, disponível nos vários espaços e como janela auxiliar em ecrã inteiro.

## Usar

Descarrega o ZIP em [Releases](https://github.com/cristianoalves92/floating-music/releases), extrai-o e move a app para Aplicações. Se o macOS bloquear a abertura e confiares na origem, segue as [instruções da Apple](https://support.apple.com/en-us/102445) em Definições → Privacidade e Segurança → Abrir mesmo assim. Para compilações locais, abre `build/Floating Music.app`. Na primeira ligação, permite que a app controle Music/Spotify no pedido de Automatização do macOS. Se recusares, altera em Definições do Sistema → Privacidade e Segurança → Automatização.

- Capa, título, artista, álbum, tempo e controlos anterior / reproduzir / pausa / seguinte.
- Clica na barra de progresso para mudar de posição.
- Arrasta o fundo para reposicionar; a posição é guardada.
- Menu (…) para escolher Automático, Apple Music ou Spotify.
- O modo automático dá prioridade a uma aplicação que esteja a reproduzir; se ambas estiverem, escolhe Music.
- O × oculta a janela. O ícone musical na barra de menus permite reabri-la ou sair.

Controla as aplicações instaladas através de Apple Events; não requer login nem API key. Não inicia reprodução automaticamente. As capas do Spotify são obtidas do endereço HTTPS fornecido pela própria aplicação.

## Compilar

Requer Xcode / Command Line Tools e macOS 13 ou posterior:

```sh
./scripts/build.sh
open 'build/Floating Music.app'
```

O script gera uma app universal (Apple Silicon e Intel) para macOS 13 ou posterior, com assinatura ad hoc. Não tem assinatura Developer ID nem notarização. Outros Macs podem exigir autorização manual na primeira abertura. Apenas foi testada em execução no Mac Apple Silicon do autor.

## Limites

Esta versão suporta Music e Spotify. Áudio de browsers, jogos e outras aplicações não está integrado. Não usa APIs privadas de MediaRemote. Algumas faixas, rádios ou streams podem não disponibilizar capa ou duração. A reprodução real e as permissões precisam de ser verificadas com uma das aplicações a tocar no Mac.

## Idiomas

Interface disponível em português, inglês, espanhol, francês, alemão e italiano. O menu (…) → Idioma permite escolher uma língua ou seguir o idioma do sistema. A escolha é guardada e aplicada imediatamente. Os títulos das faixas e os nomes dos artistas mantêm-se como são fornecidos pela aplicação de música.

As traduções estão em `Resources/<idioma>.lproj/Localizable.strings`. A mensagem de permissão do macOS está em `InfoPlist.strings` e segue o idioma escolhido pelo sistema, independentemente do seletor interno da app. Idiomas de sistema não suportados usam inglês como alternativa.
