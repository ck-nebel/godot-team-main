# godot-team

Projeto Godot 4.7 em `temp/`. Abra `temp/project.godot` no editor e aperte F5.

## Protótipo: perseguidor + blocos redimensionáveis

Plataforma 2D em que você foge para a direita enquanto um perseguidor surge **sempre à
esquerda, atrás de você**, em pontos diferentes de cada fase. Para avançar, você aumenta e
diminui os blocos azuis (a mecânica que já existia em `resizable_box.gd`).

### Controles

| Tecla | Ação |
|---|---|
| A / D | andar |
| W | pular (segurar = pulo mais alto) |
| Mouse | arrastar as bordas/cantos dos blocos azuis |
| R | reiniciar a fase |
| 1, 2, 3 | pular direto para uma fase (atalho de teste) |

Você perde se o perseguidor encostar, se cair num buraco ou se for esmagado por um bloco.
A fase reinicia sozinha.

### As 3 fases de teste

1. **Primeiros passos**: aumentar um bloco para subir um degrau e esticar outro para virar ponte.
2. **Subida**: usar blocos como elevador. Encolher um bloco depois de usá-lo deixa o perseguidor preso para trás.
3. **Fantasma**: o perseguidor atravessa paredes (modo `GHOST`), mas é mais lento. É preciso diminuir o bloco que tapa o túnel.

### Como o perseguidor nasce

Cada fase tem um nó `ChaserSpawns` com vários `Marker2D`. Na hora de nascer, a fase:

1. considera só os pontos **à esquerda do player**, a pelo menos `min_spawn_distance` px;
2. prefere os que estão até `max_spawn_distance` atrás e na faixa de altura `max_vertical_distance`;
3. sorteia um deles, evitando repetir o último;
4. mostra um aviso vermelho no ponto por `warning_time` s (e uma seta na borda da tela se ele estiver fora dela);
5. se nesse meio-tempo o player recuar para perto do ponto, sorteia outro.

Depois de nascer, ele **reaparece em outro ponto** (seguindo as mesmas regras) quando:
fica preso por `stuck_time` s (por exemplo, atrás de um bloco que você encolheu), fica mais
de `max_lag_distance` px para trás ou cai num buraco.

Na fase, os pontos possíveis aparecem como um "x" vermelho apagado (desligue em `show_spawn_points`).

### Criar uma fase nova

1. Duplique uma cena de `scenes/levels/` (ex.: `level_01.tscn`).
2. Monte o cenário em `World` com `platform.tscn` (origem no canto superior esquerdo; ajuste `size` no Inspetor) e `resizable_box.tscn`.
3. Mova os `Marker2D` de `ChaserSpawns` (pode adicionar quantos quiser), o `Player`, a `Goal` e ajuste os limites da `Camera2D` dentro do Player.
4. Adicione a cena à lista `levels` do nó `Game` em `scenes/game.tscn`.

### Ajustes rápidos

| Onde | Propriedade | Para quê |
|---|---|---|
| Nó raiz da fase (`level.gd`) | `first_spawn_delay`, `respawn_delay`, `warning_time` | ritmo do perseguidor |
| | `min_spawn_distance`, `max_spawn_distance`, `max_vertical_distance` | onde ele pode nascer |
| | `fall_limit_y` | altura em que cair = perder |
| Nó `Chaser` da fase (`chaser.gd`) | `mode` | `RUNNER` (corre, pula, é bloqueado por blocos) ou `GHOST` (voa e atravessa tudo) |
| | `max_speed`, `jump_height`, `ghost_speed` | dificuldade (o player corre a 300) |
| | `stuck_time`, `max_lag_distance` | quando ele reaparece |

### Arquivos

Novos em `temp/scenes/`: `game.tscn/.gd` (cena principal, HUD e troca de fases),
`level.gd`, `chaser.tscn/.gd`, `goal.tscn/.gd`, `platform.tscn/.gd`, `spawn_warning.gd`,
`threat_indicator.gd` e `levels/level_01..03.tscn`.

Mudanças na base:
- `project.godot`: cena principal agora é `scenes/game.tscn`; ação `restart` (R); nomes das camadas de física (1 player, 2 world, 3 chaser); cor de fundo.
- `resizable_box.tscn`: `collision_mask` de 3 para 7, para os blocos também colidirem com o perseguidor (dá para bloqueá-lo e empurrá-lo ao crescer um bloco).
- `player.gd` e `resizable_box.gd` não foram alterados. `root.tscn` continua lá como cena de testes.
