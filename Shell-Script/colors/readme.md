> Função Bash que converte marcações simples (@red, @green, @b, @u...) em cores e estilos ANSI no terminal, usando sed e tput.

```
colors "@red[[Erro]] texto normal"
colors "@green@b[[Sucesso em negrito]] e o resto sem cor"
colors "@u@cyan[[Sublinhado ciano]]"
```
